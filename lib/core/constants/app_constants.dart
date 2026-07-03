class AppConstants {
  static const String baseUrl = 'https://api.dreamingpolar.com';

  // 当前登录用户 id，用于拼接下面所有按用户隔离的缓存 key
  static const String keyCurrentUserId = 'current_user_id';

  static String keyToken(String userId) => 'user_${userId}_token';
  static String keyUsername(String userId) => 'user_${userId}_username';
}
