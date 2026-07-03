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
      await _storage.write(key: AppConstants.keyUsername(user.id), value: username);

      _ref.read(currentUserProvider.notifier).state = user;
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> logout() async {
    final userId = await _storage.read(key: AppConstants.keyCurrentUserId) ?? '';
    if (userId.isNotEmpty) {
      await _storage.delete(key: AppConstants.keyToken(userId));
      await _storage.delete(key: AppConstants.keyUsername(userId));
    }
    await _storage.delete(key: AppConstants.keyCurrentUserId);
    _ref.read(currentUserProvider.notifier).state = null;
  }

  Future<bool> tryAutoLogin() async {
    try {
      final userId = await _storage.read(key: AppConstants.keyCurrentUserId) ?? '';
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
}
