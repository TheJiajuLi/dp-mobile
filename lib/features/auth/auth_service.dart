import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../../core/locale_provider.dart';
import '../../core/network/api_client.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/models/user_model.dart';

// 当前登录用户状态
final currentUserProvider = StateProvider<UserModel?>((ref) => null);

// 当前登录用户的"关注"数——UserProfileScreen 在查看自己主页时会用抓到的
// 真实值初始化它，在任意其他用户主页上关注/取关时也会更新它，这样底部
// 导航"我的" tab 里那个常驻的 UserProfileScreen 实例（IndexedStack 不会
// 销毁它）能立刻反映变化，不用等它重新 initState
final myFollowingCountProvider = StateProvider<int?>((ref) => null);

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.read(apiClientProvider), ref);
});

class AuthService {
  final ApiClient _api;
  final Ref _ref;
  final _storage = const FlutterSecureStorage();

  AuthService(this._api, this._ref);

  Future<bool> login(String email, String password) async {
    try {
      final res = await _api.post(
        '/auth/login',
        data: {'email': email, 'password': password},
      );
      if (!res.success || res.data == null) return false;
      final token = res.data['accessToken'] as String;
      final location = res.data['location'] as String? ?? '未知位置';

      // 直接传 token，不依赖拦截器（此时 userId 未知，拦截器也找不到 token）
      final meRes = await _api.getWithToken('/auth/me', token: token);
      if (!meRes.success || meRes.data == null) return false;
      final user = UserModel.fromJson(meRes.data);

      await _persistSession(user, token);
      unawaited(_recordLogin(user.id, location));
      return true;
    } catch (e) {
      return false;
    }
  }

  // Google/GitHub OAuth 回调（见 main.dart 的 deep link 监听）只给
  // accessToken，userId/username 都靠这里重新拉一次 /auth/me 拿权威数据，
  // 跟密码登录走同一条路径，不能只拿回调 query 里那几个字段拼一个残缺
  // 的 UserModel。
  //
  // 已知限制：后端 /auth/oauth/*/callback 重定向时带的 refreshToken
  // 目前客户端用不上——/auth/refresh 只认 dp_refresh 这个 HttpOnly
  // cookie，不接受请求体里传的 refresh token；而这次 OAuth 流程是外部
  // 浏览器发起的，cookie 落在 Safari 那边，不会进到 App 自己的
  // CookieJar。所以 OAuth 登录当前只能撑到这个 accessToken 过期
  // （15分钟）——到期后 tryAutoLogin/silentRefresh 都会失败，用户需要
  // 重新走一次登录。要修需要后端加一个接受客户端 refreshToken 的
  // /auth/refresh 变体，这是后端范围的事，先如实标注这个限制
  Future<bool> completeOAuthLogin(String accessToken) async {
    try {
      final meRes = await _api.getWithToken('/auth/me', token: accessToken);
      if (!meRes.success || meRes.data == null) return false;
      final user = UserModel.fromJson(meRes.data);
      await _persistSession(user, accessToken);
      return true;
    } catch (e) {
      return false;
    }
  }

  // Sign in with Apple：用原生拿到的凭证换后端 accessToken（POST /auth/apple），
  // 再走跟 OAuth 一样的 /auth/me + 持久化路径。native 侧的调用/取消处理放在
  // 登录页，这里只负责 token 交换。跟 OAuth 同样的 refreshToken 限制（后端
  // /auth/apple 返回体里带 refreshToken，但客户端 /auth/refresh 只认 dp_refresh
  // cookie，所以本次也只撑到 accessToken 过期）
  Future<bool> appleLogin({
    required String? identityToken,
    String? authorizationCode,
    String? fullName,
    String? email,
  }) async {
    try {
      if (identityToken == null) return false;
      final res = await _api.post(
        '/auth/apple',
        data: {
          'identityToken': identityToken,
          'authorizationCode': authorizationCode,
          'fullName': fullName,
          'email': email,
        },
      );
      if (!res.success || res.data == null) return false;
      final token = res.data['accessToken'] as String?;
      if (token == null) return false;
      return completeOAuthLogin(token);
    } catch (e) {
      return false;
    }
  }

  // 数据隔离：所有 key 带 userId 前缀，防止账号串数据
  Future<void> _persistSession(UserModel user, String token) async {
    await _storage.write(key: AppConstants.keyCurrentUserId, value: user.id);
    await _storage.write(key: AppConstants.keyToken(user.id), value: token);
    await _storage.write(
      key: AppConstants.keyUsername(user.id),
      value: user.username,
    );
    _ref.read(currentUserProvider.notifier).state = user;
    unawaited(_rememberAccount(user));
  }

  // "切换账号"列表页要展示的最近登录账号（设备级别，最多3个，最近的排前面）
  Future<List<Map<String, dynamic>>> getRecentAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(AppConstants.keyRecentAccounts) ?? '[]';
    try {
      return List<Map<String, dynamic>>.from(
        (jsonDecode(raw) as List).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
      );
    } catch (_) {
      return [];
    }
  }

  Future<void> _rememberAccount(UserModel user) async {
    final prefs = await SharedPreferences.getInstance();
    var list = await getRecentAccounts();
    list.removeWhere((e) => e['id'] == user.id);
    list.insert(0, {
      'id': user.id,
      'username': user.username,
      'avatar': user.avatar,
    });
    if (list.length > AppConstants.maxRecentAccounts) {
      list = list.sublist(0, AppConstants.maxRecentAccounts);
    }
    await prefs.setString(AppConstants.keyRecentAccounts, jsonEncode(list));
  }

  Future<void> _forgetRecentAccount(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getRecentAccounts();
    list.removeWhere((e) => e['id'] == userId);
    await prefs.setString(AppConstants.keyRecentAccounts, jsonEncode(list));
  }

  // "管理"里手动移除一个账号——跟单纯切走不一样，这里要把 token 也删掉，
  // 下次要用这个账号得重新输密码
  Future<void> removeRecentAccount(String userId) async {
    await _storage.delete(key: AppConstants.keyToken(userId));
    await _storage.delete(key: AppConstants.keyUsername(userId));
    await _forgetRecentAccount(userId);
  }

  // 切到本机之前登录过、还存着 token 的另一个账号，不需要重新输密码。
  //
  // 已知限制：refresh token 走的是全局共享的一个 CookieJar（dp_refresh
  // cookie），不是按账号分开存的。如果目标账号存的 access token 已经过期
  // （15分钟有效期），普通走 ApiClient.get() 触发 403 时，拦截器会用
  // *当前 cookie 里那个账号* 的 refresh token 去刷新——刷出来的新 token
  // 实际上可能是别的账号的，还会被错误地写进目标账号的存储位置，甚至让
  // currentUserProvider 显示成刷新所属的那个账号。所以这里特意不走
  // ApiClient 的封装方法，直接用 dio + skipAuthRefresh（跟
  // ApiClient._doRefresh 里防递归用的是同一个标记）绕开拦截器的自动刷新，
  // 403 就直接判定这个账号过期，让用户老老实实重新登录，不冒险信任一次
  // 可能串号的刷新结果
  Future<bool> switchToAccount(String userId) async {
    final token = await _storage.read(key: AppConstants.keyToken(userId));
    if (token == null) {
      await _forgetRecentAccount(userId);
      return false;
    }

    // 先只验证 token，不touch keyCurrentUserId——校验失败的话，当前
    // 账号的登录状态完全不受影响，用不着回滚
    Map<String, dynamic>? data;
    try {
      final res = await _api.dio.get(
        '/auth/me',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          extra: {'skipAuthRefresh': true},
        ),
      );
      data = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : null;
    } on DioException {
      data = null;
    }

    if (data == null) {
      await removeRecentAccount(userId);
      return false;
    }

    // 确认目标账号的 token 真的有效之后，再切 keyCurrentUserId，让
    // ApiClient 拦截器后续的请求都用这个账号的 token
    await _storage.write(key: AppConstants.keyCurrentUserId, value: userId);
    final user = UserModel.fromJson(data);
    _ref.read(currentUserProvider.notifier).state = user;
    unawaited(_rememberAccount(user));
    return true;
  }

  // 登录记录目前只在本地存（后端没有专门存登录记录的接口，但 /auth/login
  // 响应本身就带了 location 字段，是基于请求 IP 的地理位置）——只记显式的
  // 账号密码登录，静默换 token/session 恢复不算一次"登录"，不写进这份记录
  Future<void> _recordLogin(String userId, String location) async {
    final prefs = await SharedPreferences.getInstance();
    final historyRaw = prefs.getString('${userId}_login_history') ?? '[]';
    final history = List<Map<String, dynamic>>.from(
      (jsonDecode(historyRaw) as List).map((e) => e as Map<String, dynamic>),
    );
    history.add({
      'time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'device': Platform.isIOS
          ? 'iPhone'
          : Platform.isAndroid
          ? 'Android 设备'
          : '未知设备',
      'location': location,
    });
    if (history.length > 20) {
      history.removeRange(0, history.length - 20);
    }
    await prefs.setString('${userId}_login_history', jsonEncode(history));
  }

  // /auth/register 本身不返回 token（实测只有 {message: '注册成功'} / 409 时
  // {message: '该邮箱已注册'}），拿 token 得走一遍完整的 /auth/login。
  // 抛具体异常而不是返回 bool——注册失败的原因（邮箱重复等）比登录失败
  // 更值得让用户看到具体文案，不能只给一句通用提示。
  // inviteCode 是可选的邀请码——后端 register 接口会在事务里校验+消耗
  // 名额并写 is_founding_creator，这里不用等注册成功再另外调一次接口
  Future<void> register({
    required String username,
    required String email,
    required String password,
    String? inviteCode,
    // 好友推荐码——跟 invite_code（元老邀请码）是两套：注册时带上后端把
    // referred_by 绑到推荐人，好友发布首篇文章时双方各得 7 天 Pro
    String? referralCode,
  }) async {
    final registerRes = await _api.post(
      '/auth/register',
      data: {
        'username': username,
        'email': email,
        'password': password,
        if (inviteCode != null && inviteCode.isNotEmpty)
          'invite_code': inviteCode,
        if (referralCode != null && referralCode.isNotEmpty)
          'referralCode': referralCode,
      },
    );
    if (!registerRes.success) {
      throw Exception(
        registerRes.message ?? _currentL10n().registerFailedRetry,
      );
    }

    final loggedIn = await login(email, password);
    if (!loggedIn) {
      throw Exception(_currentL10n().registerSuccessAutoLoginFailed);
    }
  }

  // 没有 BuildContext 可用（AuthService 不是 widget），按 localeProvider
  // 当前选的语言查表——跟 ApiClient._currentL10n() 是同一套逻辑
  AppLocalizations _currentL10n() {
    final pref = _ref.read(localeProvider);
    final locale = localeFor(pref) ?? PlatformDispatcher.instance.locale;
    if (AppLocalizations.supportedLocales.any(
      (l) => l.languageCode == locale.languageCode,
    )) {
      return lookupAppLocalizations(locale);
    }
    return lookupAppLocalizations(const Locale('zh'));
  }

  // 编辑资料成功后，用最新数据直接刷新内存态，避免为了这一次更新再打一次 /auth/me
  void updateCurrentUser(UserModel updated) {
    _ref.read(currentUserProvider.notifier).state = updated;
  }

  // 权益变更（内购成功/恢复购买后）重新拉一次 /auth/me，让 currentUserProvider
  // 里的 membership 立刻反映最新档位。用当前账号自己的 token 直连（跟
  // tryAutoLogin 同一套 skipAuthRefresh 打法），避开账号切换时拦截器可能拿
  // 错 cookie 刷 token 的坑（见 tryAutoLogin 上方注释）。失败静默返回，不改动
  // 内存态。
  Future<void> refreshMe() async {
    try {
      final userId =
          await _storage.read(key: AppConstants.keyCurrentUserId) ?? '';
      if (userId.isEmpty) return;
      final token = await _storage.read(key: AppConstants.keyToken(userId));
      if (token == null) return;
      final res = await _api.dio.get(
        '/auth/me',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          extra: {'skipAuthRefresh': true},
        ),
      );
      final data = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : null;
      if (data == null) return;
      _ref.read(currentUserProvider.notifier).state = UserModel.fromJson(data);
    } catch (_) {
      // 网络/解析失败不影响购买已完成的事实，下次进页面/自动登录会补上
    }
  }

  // 彻底退出登录——跟"切换账号"不一样，这里要把本地token和"最近账号"
  // 列表里的记录一起清掉，下次要用这个账号必须重新输密码
  Future<void> logout() async {
    // 先解绑本设备的 APNs token（后端按当前会话删除），趁 cookie 还有效。
    // 失败不阻塞登出
    try {
      await _api.delete('/auth/device/token');
    } catch (_) {}
    final userId =
        await _storage.read(key: AppConstants.keyCurrentUserId) ?? '';
    if (userId.isNotEmpty) {
      await _storage.delete(key: AppConstants.keyToken(userId));
      await _storage.delete(key: AppConstants.keyUsername(userId));
      await _forgetRecentAccount(userId);
    }
    await _storage.delete(key: AppConstants.keyCurrentUserId);
    _ref.read(currentUserProvider.notifier).state = null;
  }

  // App 冷启动时 SplashScreen 会调这个方法。2026-07-05 实测复现过的真实
  // bug：这里原来用的是 _api.get('/auth/me')——那个方法会走 ApiClient
  // 拦截器的完整链路，包括 403 自动刷新。如果本地存的 access token 恰好
  // 过期（15分钟有效期），拦截器会用*全局共享 CookieJar 里当前那个*
  // dp_refresh cookie 去刷新——账号切换（见 switch_account_screen.dart）
  // 之后这个 cookie 不一定是当前账号的（cookie 不是按账号分开存的），
  // 刷出来的新 token 可能属于另一个账号，却被当成当前账号的新 token 存下
  // 去，重试请求也换上这个混淆的 token，最终 /auth/me 返回错的账号数据，
  // 还会污染两个账号的本地 token，越用越乱。
  //
  // 修法跟 switchToAccount() 里验证 token 时一样：显式传 Authorization
  // 头 + skipAuthRefresh，绕开拦截器的自动刷新，只做一次性验证。token
  // 如果真过期了就老实返回 false，交给调用方（SplashScreen）走后面的
  // silentRefresh 兜底分支，而不是冒险触发一次可能串号的自动刷新
  Future<bool> tryAutoLogin() async {
    try {
      final userId =
          await _storage.read(key: AppConstants.keyCurrentUserId) ?? '';
      if (userId.isEmpty) return false;
      final token = await _storage.read(key: AppConstants.keyToken(userId));
      if (token == null) return false;

      Map<String, dynamic>? data;
      try {
        final res = await _api.dio.get(
          '/auth/me',
          options: Options(
            headers: {'Authorization': 'Bearer $token'},
            extra: {'skipAuthRefresh': true},
          ),
        );
        data = res.data is Map
            ? Map<String, dynamic>.from(res.data as Map)
            : null;
      } on DioException {
        data = null;
      }
      if (data == null) return false;

      final user = UserModel.fromJson(data);
      _ref.read(currentUserProvider.notifier).state = user;
      unawaited(_rememberAccount(user));
      return true;
    } catch (e) {
      return false;
    }
  }

  // 后台静默换新 token，不阻塞启动流程。失败（比如临时网络问题，或者
  // refresh token/cookie 本身也过期了）不强制登出——调用方决定要不要
  // 基于返回值做进一步处理（SplashScreen 会在这个失败时才跳登录页）。
  // 注意：这里换到的新 access token 只是延长了有效期，currentUserProvider
  // 里的用户数据不会跟着更新——那是 tryAutoLogin/login 走 /auth/me 才做的事
  Future<bool> silentRefresh() async {
    final userId = await _storage.read(key: AppConstants.keyCurrentUserId);
    if (userId == null || userId.isEmpty) return false;
    final res = await _api.post('/auth/refresh');
    if (!res.success || res.data == null) return false;
    final newToken = res.data['accessToken'] as String?;
    if (newToken != null) {
      await _storage.write(key: AppConstants.keyToken(userId), value: newToken);
      return true;
    }
    return false;
  }
}
