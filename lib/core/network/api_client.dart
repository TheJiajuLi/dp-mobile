import 'dart:ui';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import '../constants/app_constants.dart';
import '../locale_provider.dart';
import '../router/app_router.dart';
import '../../features/auth/auth_service.dart';
import '../../l10n/generated/app_localizations.dart';
import 'api_response.dart';

// main() 里会用真正落盘的 PersistCookieJar override 掉这个默认实现——
// 这里的内存版只是保证没走 override 时（比如测试）也不会直接崩
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(ref));

class ApiClient {
  final Ref _ref;
  final Dio dio;
  final _storage = const FlutterSecureStorage();

  // 多个请求同时撞上 403 时，只真正发一次 /auth/refresh，其余的等同一个
  // Future，不然峰值时刻会打出一堆重复的刷新请求
  Future<bool>? _refreshing;

  ApiClient(this._ref, {CookieJar? cookieJar})
    : dio = Dio(
        BaseOptions(
          baseUrl: AppConstants.baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      ) {
    // /auth/refresh 认的是登录时后端用 Set-Cookie 下发的 dp_refresh
    // （HttpOnly + Secure cookie），不是 Authorization 头。Dio 默认不会
    // 存/带任何 cookie——没有这个 CookieManager，silentRefresh() 实测
    // 永远拿到 401「未携带 Refresh Token」，是个从没真正生效过的空调用。
    // dio_cookie_manager 明确不支持 Web（浏览器自己管 cookie），项目里
    // 那个 web/ 目录是 flutter create 留下来没用过的默认脚手架，但这里
    // 还是加个 kIsWeb 判断，免得哪天真跑到 Web 上直接断言崩溃
    if (!kIsWeb) {
      dio.interceptors.add(CookieManager(cookieJar ?? CookieJar()));
    }

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // 如果调用方已显式设置了 Authorization，不覆盖
          if (options.headers.containsKey('Authorization')) {
            return handler.next(options);
          }
          final userId = await _storage.read(key: AppConstants.keyCurrentUserId);
          if (userId != null && userId.isNotEmpty) {
            final token = await _storage.read(key: AppConstants.keyToken(userId));
            if (token != null) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          }
          handler.next(options);
        },
        onError: (err, handler) async {
          // /auth/refresh 这个请求本身失败时不要再递归尝试刷新
          if (err.requestOptions.extra['skipAuthRefresh'] == true) {
            return handler.next(err);
          }
          // 实测确认：401 是完全没带 token（刷新也没意义，本来就没登录），
          // 403「Token 无效或已过期」才是 access token 过期的信号
          if (err.response?.statusCode != 403) {
            return handler.next(err);
          }

          final refreshed = await _refreshToken();
          if (!refreshed) {
            await _forceLogout();
            return handler.next(err);
          }

          try {
            final userId =
                await _storage.read(key: AppConstants.keyCurrentUserId) ?? '';
            final newToken = await _storage.read(key: AppConstants.keyToken(userId));
            final opts = err.requestOptions;
            opts.headers['Authorization'] = 'Bearer $newToken';
            final response = await dio.fetch(opts);
            return handler.resolve(response);
          } catch (_) {
            // 用新 token 重试也失败，就把原始错误原样交回去，别吞掉
            return handler.next(err);
          }
        },
      ),
    );

    dio.interceptors.add(
      PrettyDioLogger(
        requestBody: true,
        responseBody: true,
        compact: true,
        maxWidth: 120,
        logPrint: (obj) {
          final str = obj.toString();
          // 截断 base64 图片数据，避免日志被一大坨 base64 刷屏
          final truncated = str.replaceAllMapped(
            RegExp(r'(data:image/[^;]+;base64,)[A-Za-z0-9+/=]{50,}'),
            (m) => '${m.group(1)}[base64 截断...]',
          );
          debugPrint(truncated);
        },
      ),
    );
  }

  Future<bool> _refreshToken() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<bool> _doRefresh() async {
    try {
      final userId = await _storage.read(key: AppConstants.keyCurrentUserId) ?? '';
      if (userId.isEmpty) return false;

      final res = await dio.post(
        '/auth/refresh',
        options: Options(extra: {'skipAuthRefresh': true}),
      );
      final data = res.data;
      final newToken = data is Map ? data['accessToken'] as String? : null;
      if (res.statusCode == 200 && newToken != null) {
        await _storage.write(key: AppConstants.keyToken(userId), value: newToken);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _forceLogout() async {
    final userId = await _storage.read(key: AppConstants.keyCurrentUserId) ?? '';
    if (userId.isNotEmpty) {
      await _storage.delete(key: AppConstants.keyToken(userId));
      await _storage.delete(key: AppConstants.keyUsername(userId));
    }
    await _storage.delete(key: AppConstants.keyCurrentUserId);
    _ref.read(currentUserProvider.notifier).state = null;
    appRouter.go('/login');
  }

  Future<ApiResponse<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final res = await dio.get(path, queryParameters: queryParameters);
      return ApiResponse.success(res.data, statusCode: res.statusCode);
    } on DioException catch (e) {
      return ApiResponse.error(_message(e), statusCode: e.response?.statusCode);
    }
  }

  Future<ApiResponse<dynamic>> post(String path, {dynamic data}) async {
    try {
      final res = await dio.post(path, data: data);
      return ApiResponse.success(res.data, statusCode: res.statusCode);
    } on DioException catch (e) {
      return ApiResponse.error(_message(e), statusCode: e.response?.statusCode);
    }
  }

  Future<ApiResponse<dynamic>> patch(String path, {dynamic data}) async {
    try {
      final res = await dio.patch(path, data: data);
      return ApiResponse.success(res.data, statusCode: res.statusCode);
    } on DioException catch (e) {
      return ApiResponse.error(_message(e), statusCode: e.response?.statusCode);
    }
  }

  Future<ApiResponse<dynamic>> put(String path, {dynamic data}) async {
    try {
      final res = await dio.put(path, data: data);
      return ApiResponse.success(res.data, statusCode: res.statusCode);
    } on DioException catch (e) {
      return ApiResponse.error(_message(e), statusCode: e.response?.statusCode);
    }
  }

  Future<ApiResponse<dynamic>> delete(String path, {dynamic data}) async {
    try {
      final res = await dio.delete(path, data: data);
      return ApiResponse.success(res.data, statusCode: res.statusCode);
    } on DioException catch (e) {
      return ApiResponse.error(_message(e), statusCode: e.response?.statusCode);
    }
  }

  // 显式传入 token，不依赖拦截器读取本地存储
  // 用于登录流程中 userId 尚未落盘、拦截器还找不到 token 的场景
  Future<ApiResponse<dynamic>> getWithToken(String path, {required String token}) async {
    try {
      final res = await dio.get(
        path,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return ApiResponse.success(res.data, statusCode: res.statusCode);
    } on DioException catch (e) {
      return ApiResponse.error(_message(e), statusCode: e.response?.statusCode);
    }
  }

  String _message(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['message'] != null) {
      return data['message'].toString();
    }
    // 这几条是纯客户端兜底文案（后端没返回message时才用得到），没有
    // BuildContext可用，所以不能走AppLocalizations.of(context)——按
    // localeProvider当前选的语言（跟随系统时退回设备locale）直接查表
    final l10n = _currentL10n();
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return l10n.networkTimeout;
      case DioExceptionType.connectionError:
        return l10n.networkConnectionFailed;
      default:
        return e.message ?? l10n.requestFailed;
    }
  }

  AppLocalizations _currentL10n() {
    final pref = _ref.read(localeProvider);
    final locale = localeFor(pref) ?? PlatformDispatcher.instance.locale;
    if (AppLocalizations.supportedLocales.any((l) => l.languageCode == locale.languageCode)) {
      return lookupAppLocalizations(locale);
    }
    // 设备语言不在支持列表里（不是zh/en）——退回中文，跟这个App一直以来
    // 默认展示中文的行为保持一致
    return lookupAppLocalizations(const Locale('zh'));
  }
}
