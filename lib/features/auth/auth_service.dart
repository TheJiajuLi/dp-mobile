import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../../core/network/api_client.dart';
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
      final username = res.data['username'] as String;

      // 直接传 token，不依赖拦截器（此时 userId 未知，拦截器也找不到 token）
      final meRes = await _api.getWithToken('/auth/me', token: token);
      if (!meRes.success || meRes.data == null) return false;
      final user = UserModel.fromJson(meRes.data);

      // 数据隔离：所有 key 带 userId 前缀，防止账号串数据
      await _storage.write(key: AppConstants.keyCurrentUserId, value: user.id);
      await _storage.write(key: AppConstants.keyToken(user.id), value: token);
      await _storage.write(
        key: AppConstants.keyUsername(user.id),
        value: username,
      );

      _ref.read(currentUserProvider.notifier).state = user;
      unawaited(_recordLogin(user.id));
      return true;
    } catch (e) {
      return false;
    }
  }

  // 登录记录目前只在本地存（后端没有这个接口）——只记显式的账号密码登录，
  // 静默换 token/session 恢复不算一次"登录"，不写进这份记录
  Future<void> _recordLogin(String userId) async {
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
  Future<void> register({
    required String username,
    required String email,
    required String password,
  }) async {
    final registerRes = await _api.post(
      '/auth/register',
      data: {'username': username, 'email': email, 'password': password},
    );
    if (!registerRes.success) {
      throw Exception(registerRes.message ?? '注册失败，请重试');
    }

    final loggedIn = await login(email, password);
    if (!loggedIn) {
      throw Exception('注册成功，但自动登录失败，请手动登录');
    }
  }

  // 编辑资料成功后，用最新数据直接刷新内存态，避免为了这一次更新再打一次 /auth/me
  void updateCurrentUser(UserModel updated) {
    _ref.read(currentUserProvider.notifier).state = updated;
  }

  Future<void> logout() async {
    final userId =
        await _storage.read(key: AppConstants.keyCurrentUserId) ?? '';
    if (userId.isNotEmpty) {
      await _storage.delete(key: AppConstants.keyToken(userId));
      await _storage.delete(key: AppConstants.keyUsername(userId));
    }
    await _storage.delete(key: AppConstants.keyCurrentUserId);
    _ref.read(currentUserProvider.notifier).state = null;
  }

  Future<bool> tryAutoLogin() async {
    try {
      final userId =
          await _storage.read(key: AppConstants.keyCurrentUserId) ?? '';
      if (userId.isEmpty) return false;
      final token = await _storage.read(key: AppConstants.keyToken(userId));
      if (token == null) return false;
      final res = await _api.get('/auth/me');
      if (!res.success) return false;
      final user = UserModel.fromJson(res.data);
      _ref.read(currentUserProvider.notifier).state = user;
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
