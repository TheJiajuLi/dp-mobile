class AppConstants {
  static const String baseUrl = 'https://api.dreamingpolar.com';

  // 当前登录用户 id，用于拼接下面所有按用户隔离的缓存 key
  static const String keyCurrentUserId = 'current_user_id';

  static String keyToken(String userId) => 'user_${userId}_token';
  static String keyUsername(String userId) => 'user_${userId}_username';

  // 设备级别（不带 userId 前缀）——记录这台设备最近登录过的几个账号，
  // 用来支持"切换账号"列表页的免密切换
  static const String keyRecentAccounts = 'recent_accounts';
  static const int maxRecentAccounts = 3;

  // 搜索历史按账号隔离——跟 token/username 同一套per-user前缀规则，见
  // flutter_implementation_pitfalls.md 里"账号数据隔离"那条
  static String keySearchHistory(String userId) =>
      'user_${userId}_search_history';
  static const int maxSearchHistory = 10;
}
