import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../auth/auth_service.dart';
import '../purchase_service.dart';

const _primary = Color(0xFF6366F1);
const _danger = Color(0xFFEF4444);
const _appStoreSubs = 'https://apps.apple.com/account/subscriptions';

// 订阅管理页——跟老的「会员中心」(/settings/subscription) 分开，从创作者
// 中心的会员入口进 (/subscription/manage)。按 membership 分两态：
// 免费(灰卡+三栏+7天试用) / 已订阅(渐变卡+订阅详情+切换套餐+管理)。
class SubscriptionManagementScreen extends ConsumerStatefulWidget {
  const SubscriptionManagementScreen({super.key});
  @override
  ConsumerState<SubscriptionManagementScreen> createState() =>
      _SubscriptionManagementScreenState();
}

class _SubscriptionManagementScreenState
    extends ConsumerState<SubscriptionManagementScreen> {
  StreamSubscription<PurchaseResult>? _resultSub;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _bg => _isDark ? AppColors.darkBg : const Color(0xFFFAFAF8);
  Color get _card => _isDark ? AppColors.darkCard : Colors.white;
  Color get _ink =>
      _isDark ? AppColors.darkTextPrimary : const Color(0xFF1A1A1A);
  Color get _muted =>
      _isDark ? AppColors.darkTextSecondary : const Color(0xFF999999);
  Color get _border => _isDark ? AppColors.darkBorder : const Color(0xFFEBEBEB);
  Color get _fill =>
      _isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF5F5F7);

  @override
  void initState() {
    super.initState();
    final svc = ref.read(purchaseServiceProvider);
    if (svc.products.isEmpty) svc.loadProducts();
    _resultSub = svc.results.listen(_onResult);
  }

  @override
  void dispose() {
    _resultSub?.cancel();
    super.dispose();
  }

  void _onResult(PurchaseResult r) {
    if (!mounted) return;
    switch (r.outcome) {
      case PurchaseOutcome.success:
        showAppToast(context, '订阅成功，欢迎加入！', ok: true);
      case PurchaseOutcome.restored:
        showAppToast(context, '已恢复购买', ok: true);
      case PurchaseOutcome.canceled:
        break;
      case PurchaseOutcome.error:
        showAppToast(context, r.message ?? '购买失败，请稍后重试');
    }
  }

  String _expiryDate(int? expiresSec) {
    if (expiresSec == null || expiresSec == 0) return '长期有效';
    final dt = DateTime.fromMillisecondsSinceEpoch(expiresSec * 1000);
    return '${dt.year}年${dt.month}月${dt.day}日';
  }

  void _buy(String productId) {
    final svc = ref.read(purchaseServiceProvider);
    final p = svc.productById(productId);
    if (p == null) {
      showAppToast(context, '商品信息加载中，请稍后重试');
      return;
    }
    svc.buy(p);
  }

  Future<void> _openAppStore() async {
    await launchUrl(
      Uri.parse(_appStoreSubs),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    // products 变化时重建（价格从 loading 变成真实价）
    ref.watch(purchaseServiceProvider);
    final membership = user?.membership ?? 'free';
    final isProMax = membership == 'pro_max';
    final isPro = membership == 'pro';
    final subscribed = isPro || isProMax;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _topBar(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: subscribed
                    ? _subscribedBody(user, isProMax)
                    : _freeBody(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              child: Icon(Icons.arrow_back_ios_new, size: 18, color: _ink),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '订阅管理',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
        ],
      ),
    );
  }

  // ================= 已订阅 =================
  List<Widget> _subscribedBody(dynamic user, bool isProMax) {
    final expiry = _expiryDate(user?.membershipExpiresAt as int?);
    final svc = ref.read(purchaseServiceProvider);
    final priceMax = svc.productById(kProMaxProductMonthly)?.price ?? '¥68 / 月';
    final priceMonthly = svc.productById(kProProductMonthly)?.price ?? '¥38';
    final priceYearly = svc.productById(kProProductYearly)?.price ?? '¥348';

    return [
      _gradientCard(isProMax, expiry),
      const SizedBox(height: 16),
      _actionButtons(isProMax),
      const SizedBox(height: 20),
      _sectionLabel('订阅详情'),
      _infoCard([
        _infoRow('订阅套餐', isProMax ? '极梦 PRO MAX 月度' : '极梦 PRO'),
        _infoRow('订阅价格', isProMax ? priceMax : priceMonthly),
        _infoRow('下次续费', expiry, valueColor: _primary),
        _infoRow('订阅平台', 'Apple App Store', valueMuted: true),
        _infoRow('自动续订', '已开启', valueColor: const Color(0xFF16A34A)),
      ]),
      const SizedBox(height: 20),
      _sectionLabel('切换套餐'),
      _planRow(
        membership: isProMax ? 'pro_max' : 'pro',
        priceMonthly: priceMonthly,
        priceYearly: priceYearly,
        priceMax: svc.productById(kProMaxProductMonthly)?.price ?? '¥68',
      ),
      const SizedBox(height: 20),
      _sectionLabel('管理'),
      _infoCard([
        _infoRow(
          '在 App Store 管理订阅',
          '',
          trailing: Icon(Icons.open_in_new, size: 15, color: _muted),
          onTap: _openAppStore,
        ),
        _infoRow(
          '取消自动续订',
          '',
          labelColor: _danger,
          trailing: Icon(Icons.chevron_right, size: 18, color: _muted),
          onTap: _openAppStore,
        ),
      ]),
      const SizedBox(height: 12),
      _cancelNote(),
    ];
  }

  Widget _gradientCard(bool isProMax, String expiry) {
    final colors = isProMax
        ? const [Color(0xFFB45309), Color(0xFFD97706), Color(0xFFF59E0B)]
        : const [Color(0xFF4F46E5), Color(0xFF6366F1), Color(0xFF818CF8)];
    final perks = isProMax
        ? ['20GB 存储', 'AI 无限次', '100MB 视频', '优先体验']
        : ['5GB 存储', '代码运行', 'AI 20次/天', '音视频'];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colors[1].withValues(alpha: 0.32),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '当前订阅',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isProMax ? '极梦 PRO MAX' : '极梦 PRO',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            expiry == '长期有效' ? '长期有效' : '有效期至 $expiry',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: perks
                .map(
                  (p) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      p,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _actionButtons(bool isProMax) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 46,
            child: ElevatedButton(
              onPressed: isProMax
                  ? _openAppStore
                  : () => _buy(kProMaxProductMonthly),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1A1A),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                isProMax ? '管理套餐' : '升级 PRO MAX',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            height: 46,
            child: OutlinedButton(
              onPressed: () => ref.read(purchaseServiceProvider).restore(),
              style: OutlinedButton.styleFrom(
                foregroundColor: _ink,
                side: BorderSide(color: _border, width: 1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                '恢复购买',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _cancelNote() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border, width: 0.5),
      ),
      child: Text(
        '取消后当前订阅周期结束前仍可使用全部权益。退款申请请通过 Apple App Store 提交。',
        style: TextStyle(fontSize: 12, height: 1.7, color: _muted),
      ),
    );
  }

  // ================= 免费 =================
  List<Widget> _freeBody() {
    final svc = ref.read(purchaseServiceProvider);
    return [
      _freeCard(),
      const SizedBox(height: 20),
      _sectionLabel('选择套餐'),
      _planRow(
        membership: 'free',
        priceMonthly: svc.productById(kProProductMonthly)?.price ?? '¥38',
        priceYearly: svc.productById(kProProductYearly)?.price ?? '¥348',
        priceMax: svc.productById(kProMaxProductMonthly)?.price ?? '¥68',
      ),
      const SizedBox(height: 16),
      _trialHint(),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: () => _buy(kProProductYearly),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1A1A1A),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: const Text(
            '开始 7 天免费试用',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Center(
        child: GestureDetector(
          onTap: () => ref.read(purchaseServiceProvider).restore(),
          child: Text(
            '恢复购买',
            style: TextStyle(
              fontSize: 13,
              color: _muted,
              decoration: TextDecoration.underline,
              decorationColor: _muted,
            ),
          ),
        ),
      ),
    ];
  }

  Widget _freeCard() {
    const chips = ['200MB 存储', '浏览内容', '发布文章'];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '当前套餐',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _muted,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '免费版',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '200MB 存储 · 基础功能',
            style: TextStyle(fontSize: 13, color: _muted),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: chips
                .map(
                  (c) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _fill,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: _border, width: 0.5),
                    ),
                    child: Text(c, style: TextStyle(fontSize: 12, color: _ink)),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _trialHint() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _isDark
            ? _primary.withValues(alpha: 0.14)
            : const Color(0xFFEEF0FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _isDark
              ? _primary.withValues(alpha: 0.3)
              : const Color(0xFFC7C9F0),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '7 天免费试用',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF4F46E5),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '首次订阅可免费体验 7 天，随时取消。',
            style: TextStyle(
              fontSize: 12,
              color: const Color(0xFF6366F1).withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }

  // ================= 三栏套餐 =================
  Widget _planRow({
    required String membership,
    required String priceMonthly,
    required String priceYearly,
    required String priceMax,
  }) {
    final isFree = membership == 'free';
    final isPro = membership == 'pro';
    final isProMax = membership == 'pro_max';
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _planCard(
              name: 'PRO 月度',
              price: priceMonthly,
              unit: '/ 月',
              features: const ['5GB 存储', '代码运行', 'AI 20次'],
              current: isPro,
              onTap: () => _buy(kProProductMonthly),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _planCard(
              name: 'PRO 年度',
              price: priceYearly,
              unit: '/ 年 省24%',
              features: const ['5GB 存储', '代码运行', 'AI 20次'],
              current: isPro,
              badge: isFree ? '推荐' : null,
              highlight: isFree,
              onTap: () => _buy(kProProductYearly),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _planCard(
              name: 'PRO MAX',
              price: priceMax,
              unit: '/ 月',
              features: const ['20GB 存储', 'AI 无限次', '100MB 视频'],
              current: isProMax,
              badge: isProMax ? '当前' : null,
              onTap: () => _buy(kProMaxProductMonthly),
            ),
          ),
        ],
      ),
    );
  }

  Widget _planCard({
    required String name,
    required String price,
    required String unit,
    required List<String> features,
    required VoidCallback onTap,
    bool current = false,
    bool highlight = false,
    String? badge,
  }) {
    final outlined = current || highlight;
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(10, 16, 10, 14),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: outlined ? _primary : _border,
                width: outlined ? 1.5 : 0.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Text(
                    name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _ink,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    price,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Center(
                  child: Text(
                    unit,
                    style: TextStyle(fontSize: 11, color: _muted),
                  ),
                ),
                const SizedBox(height: 12),
                ...features.map(
                  (f) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.check,
                          size: 13,
                          color: Color(0xFF16A34A),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            f,
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.3,
                              color: _ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (badge != null)
            Positioned(
              top: -9,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _primary,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ================= 通用小件 =================
  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: _muted,
        ),
      ),
    );
  }

  Widget _infoCard(List<Widget> rows) {
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) {
        children.add(Divider(height: 0.5, thickness: 0.5, color: _border));
      }
      children.add(rows[i]);
    }
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border, width: 0.5),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(children: children),
    );
  }

  Widget _infoRow(
    String label,
    String value, {
    Color? valueColor,
    bool valueMuted = false,
    Color? labelColor,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: labelColor ?? _ink,
                fontWeight: labelColor != null
                    ? FontWeight.w500
                    : FontWeight.w400,
              ),
            ),
            const Spacer(),
            if (value.isNotEmpty)
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: valueColor ?? (valueMuted ? _muted : _ink),
                ),
              ),
            if (trailing != null) ...[const SizedBox(width: 6), trailing],
          ],
        ),
      ),
    );
  }
}
