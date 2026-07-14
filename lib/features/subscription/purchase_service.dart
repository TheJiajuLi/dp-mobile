import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';

import '../../core/network/api_client.dart';
import '../auth/auth_service.dart';

// App Store Connect 里注册的 Product ID（自动续订订阅）。年度只有 Pro 有，
// Pro Max 目前只做月度——跟 subscription_screen.dart 的档位一一对应。
const String kProProductMonthly = 'com.dreamingpolar.pro.monthly';
const String kProProductYearly = 'com.dreamingpolar.pro.yearly';
const String kProMaxProductMonthly = 'com.dreamingpolar.promax.monthly';

const Set<String> kProductIds = {
  kProProductMonthly,
  kProProductYearly,
  kProMaxProductMonthly,
};

// 一次购买/恢复的最终结果，通过 PurchaseService.results 广播给 UI 弹 SnackBar。
enum PurchaseOutcome { success, restored, canceled, error }

class PurchaseResult {
  final PurchaseOutcome outcome;
  final String? productId;
  final String? message;
  const PurchaseResult(this.outcome, {this.productId, this.message});
}

// 单例式的内购服务，用 Riverpod Provider 托管（不是项目里没有的 GetIt）。
// 构造时拿 Ref，验证收据要用 apiClientProvider、发放权益后要刷 currentUser。
// 继承 ChangeNotifier：products/购买中状态变化时 notifyListeners，订阅页
// ref.watch 到就重建；一次性结果（成功/失败/取消）走单独的广播 Stream。
final purchaseServiceProvider = ChangeNotifierProvider<PurchaseService>((ref) {
  return PurchaseService(ref);
});

class PurchaseService extends ChangeNotifier {
  PurchaseService(this._ref);

  final Ref _ref;
  final InAppPurchase _iap = InAppPurchase.instance;

  StreamSubscription<List<PurchaseDetails>>? _subscription;
  final StreamController<PurchaseResult> _resultCtrl =
      StreamController<PurchaseResult>.broadcast();

  /// 一次性结果流（成功/恢复/取消/失败），UI 订阅它弹提示。
  Stream<PurchaseResult> get results => _resultCtrl.stream;

  bool isAvailable = false;
  bool _initialized = false;
  List<ProductDetails> products = [];

  // 正在等待结果的 productId 集合——驱动对应套餐按钮转圈+禁用。
  final Set<String> _pending = {};

  bool get isBusy => _pending.isNotEmpty;
  bool isPurchasing(String? productId) =>
      productId != null && _pending.contains(productId);

  ProductDetails? productById(String id) {
    for (final p in products) {
      if (p.id == id) return p;
    }
    return null;
  }

  // 在 main.dart 的 MyApp.initState 里调一次；幂等，重复调用直接返回。
  // 尽早监听 purchaseStream 才能接住上次被系统中断/挂起的交易。
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    isAvailable = await _iap.isAvailable();
    if (!isAvailable) {
      notifyListeners();
      return;
    }

    // iOS 必须设置 delegate 才能正确处理排队中的延迟交易（家长同意等）。
    if (Platform.isIOS) {
      final iosAddition =
          _iap.getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>();
      await iosAddition.setDelegate(_PaymentQueueDelegate());
    }

    _subscription = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onError: (e) => debugPrint('purchaseStream error: $e'),
    );

    await loadProducts();
    notifyListeners();
  }

  Future<void> loadProducts() async {
    if (!isAvailable) return;
    final response = await _iap.queryProductDetails(kProductIds);
    if (response.error != null) {
      debugPrint('queryProductDetails error: ${response.error}');
    }
    if (response.notFoundIDs.isNotEmpty) {
      // ASC 里还没配好这些产品时会落在这里——不是崩溃，只是商品加载不出来，
      // 订阅页会退回写死的兜底价格文案
      debugPrint('product ids not found: ${response.notFoundIDs}');
    }
    products = response.productDetails;
    notifyListeners();
  }

  // 发起购买（订阅是 non-consumable 语义走这个接口）。
  Future<void> buy(ProductDetails product) async {
    if (_pending.contains(product.id)) return;
    _pending.add(product.id);
    notifyListeners();
    try {
      final param = PurchaseParam(productDetails: product);
      await _iap.buyNonConsumable(purchaseParam: param);
    } catch (e) {
      _pending.remove(product.id);
      notifyListeners();
      _resultCtrl.add(
        PurchaseResult(
          PurchaseOutcome.error,
          productId: product.id,
          message: '$e',
        ),
      );
    }
  }

  Future<void> restore() async {
    if (!isAvailable) return;
    await _iap.restorePurchases();
  }

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> details) async {
    for (final purchase in details) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          // 交易挂起（等家长同意/银行确认），保持按钮转圈，不做处理
          break;
        case PurchaseStatus.error:
          _pending.remove(purchase.productID);
          _resultCtrl.add(
            PurchaseResult(
              PurchaseOutcome.error,
              productId: purchase.productID,
              message: purchase.error?.message ?? '购买出错',
            ),
          );
          break;
        case PurchaseStatus.canceled:
          _pending.remove(purchase.productID);
          _resultCtrl.add(
            PurchaseResult(
              PurchaseOutcome.canceled,
              productId: purchase.productID,
            ),
          );
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _verifyAndDeliver(purchase);
          _pending.remove(purchase.productID);
          break;
      }

      // 无论成功失败，pendingCompletePurchase 为真都必须 complete，否则
      // StoreKit 会反复重发这笔交易
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
      notifyListeners();
    }
  }

  Future<void> _verifyAndDeliver(PurchaseDetails purchase) async {
    final restored = purchase.status == PurchaseStatus.restored;
    try {
      // serverVerificationData 是给后端校验的凭据：iOS 上是 base64 收据，
      // 后端拿去调 Apple verifyReceipt / App Store Server API 核验后发放权益
      final receipt = purchase.verificationData.serverVerificationData;
      if (receipt.isEmpty) {
        _resultCtrl.add(
          PurchaseResult(
            PurchaseOutcome.error,
            productId: purchase.productID,
            message: '未取到收据',
          ),
        );
        return;
      }

      final api = _ref.read(apiClientProvider);
      final res = await api.post(
        '/auth/storekit/verify',
        data: {
          'receiptData': receipt,
          'productId': purchase.productID,
          'transactionId': purchase.purchaseID,
          'source': purchase.verificationData.source,
        },
      );

      if (res.success) {
        // 后端更新了 membership，重新拉一次 /auth/me 让全局用户态跟上
        await _ref.read(authServiceProvider).refreshMe();
        _resultCtrl.add(
          PurchaseResult(
            restored ? PurchaseOutcome.restored : PurchaseOutcome.success,
            productId: purchase.productID,
          ),
        );
      } else {
        _resultCtrl.add(
          PurchaseResult(
            PurchaseOutcome.error,
            productId: purchase.productID,
            message: res.message ?? '收据验证失败',
          ),
        );
      }
    } catch (e) {
      _resultCtrl.add(
        PurchaseResult(
          PurchaseOutcome.error,
          productId: purchase.productID,
          message: '$e',
        ),
      );
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _resultCtrl.close();
    super.dispose();
  }
}

// iOS StoreKit 支付队列 delegate：始终继续交易、不弹价格同意弹窗。
class _PaymentQueueDelegate implements SKPaymentQueueDelegateWrapper {
  @override
  bool shouldContinueTransaction(
    SKPaymentTransactionWrapper transaction,
    SKStorefrontWrapper storefront,
  ) => true;

  @override
  bool shouldShowPriceConsent() => false;
}
