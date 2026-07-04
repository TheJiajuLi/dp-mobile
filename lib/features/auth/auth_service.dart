import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/constants/app_constants.dart';
import '../../core/network/api_client.dart';
import '../../shared/models/user_model.dart';

// 当前登录用户状态
final currentUserProvider = StateProvider<UserModel?>((ref) => null);

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
      return true;
    } catch (e) {
      return false;
    }
  }

  // 跟 login() 走同一套模式：注册接口本身只返回 {accessToken, username}
  // （CONTEXT.md 里确认过，没有 id），所以拿到 token 后还是要单独调
  // /auth/me 换完整 profile，再按 userId 落盘。跟 login() 不同的是这里
  // 抛具体异常而不是返回 bool——注册失败的原因（邮箱重复/用户名重复等）
  // 比登录失败更值得让用户看到具体文案，不能只给一句通用提示。
  Future<void> register({
    required String username,
    required String email,
    required String password,
  }) async {
    final res = await _api.post(
      '/auth/register',
      data: {'username': username, 'email': email, 'password': password},
    );
    if (!res.success || res.data == null) {
      throw Exception(res.message ?? '注册失败，请重试');
    }
    final token = res.data['accessToken'] as String?;
    final regUsername = res.data['username'] as String? ?? username;
    if (token == null) {
      throw Exception('注册失败，请重试');
    }

    final meRes = await _api.getWithToken('/auth/me', token: token);
    if (!meRes.success || meRes.data == null) {
      throw Exception('注册成功，但获取用户信息失败，请重新登录');
    }
    final user = UserModel.fromJson(meRes.data);

    await _storage.write(key: AppConstants.keyCurrentUserId, value: user.id);
    await _storage.write(key: AppConstants.keyToken(user.id), value: token);
    await _storage.write(
      key: AppConstants.keyUsername(user.id),
      value: regUsername,
    );

    _ref.read(currentUserProvider.notifier).state = user;
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

  // 后台静默换新 token，不阻塞启动流程。失败（比如临时网络问题）不强制登出——
  // tryAutoLogin 已经用 /auth/me 验证过 session 有效，这里只是顺手延长有效期
  Future<void> silentRefresh() async {
    final userId = await _storage.read(key: AppConstants.keyCurrentUserId);
    if (userId == null || userId.isEmpty) return;
    final res = await _api.post('/auth/refresh');
    if (!res.success || res.data == null) return;
    final newToken = res.data['accessToken'] as String?;
    if (newToken != null) {
      await _storage.write(key: AppConstants.keyToken(userId), value: newToken);
    }
  }
}
