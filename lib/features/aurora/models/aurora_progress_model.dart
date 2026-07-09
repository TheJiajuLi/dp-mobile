// GET /auth/aurora/progress 的响应模型——跟 subscription_screen.dart 里
// 的申请门槛（10篇/100赞/50粉丝，一次性达标）是两码事：这里是已经是极光
// 创作者之后，每月续期要满足的 6 项活跃指标（满足任意3项）
class AuroraMonthlyActivity {
  final String yearMonth;
  final int publishedCount;
  final int likedOthersCount;
  final int commentedCount;
  final int repliedCount;
  final int newFollowersCount;
  final int receivedLikesSavesCount;
  final int metConditions;
  final bool isQualified;

  const AuroraMonthlyActivity({
    required this.yearMonth,
    required this.publishedCount,
    required this.likedOthersCount,
    required this.commentedCount,
    required this.repliedCount,
    required this.newFollowersCount,
    required this.receivedLikesSavesCount,
    required this.metConditions,
    required this.isQualified,
  });

  factory AuroraMonthlyActivity.fromJson(Map<String, dynamic> j) =>
      AuroraMonthlyActivity(
        yearMonth: j['yearMonth']?.toString() ?? '',
        publishedCount: (j['publishedCount'] as num?)?.toInt() ?? 0,
        likedOthersCount: (j['likedOthersCount'] as num?)?.toInt() ?? 0,
        commentedCount: (j['commentedCount'] as num?)?.toInt() ?? 0,
        repliedCount: (j['repliedCount'] as num?)?.toInt() ?? 0,
        newFollowersCount: (j['newFollowersCount'] as num?)?.toInt() ?? 0,
        receivedLikesSavesCount:
            (j['receivedLikesSavesCount'] as num?)?.toInt() ?? 0,
        metConditions: (j['metConditions'] as num?)?.toInt() ?? 0,
        isQualified: j['isQualified'] == true,
      );
}

// 历史记录条目——跟 currentMonth 不是同一套字段命名，后端这里直接把
// aurora_activity 表的行原样透出，是 snake_case（year_month/met_conditions/
// is_qualified/renewed_at），不是 currentMonth 那套 camelCase，读的时候
// 不能偷懒复用同一个 key 名
class AuroraHistoryEntry {
  final String yearMonth;
  final int metConditions;
  final bool isQualified;
  final int? renewedAt;

  const AuroraHistoryEntry({
    required this.yearMonth,
    required this.metConditions,
    required this.isQualified,
    this.renewedAt,
  });

  factory AuroraHistoryEntry.fromJson(Map<String, dynamic> j) =>
      AuroraHistoryEntry(
        yearMonth: j['year_month']?.toString() ?? '',
        metConditions: (j['met_conditions'] as num?)?.toInt() ?? 0,
        isQualified: j['is_qualified'] == true || j['is_qualified'] == 1,
        renewedAt: (j['renewed_at'] as num?)?.toInt(),
      );
}

class AuroraProgress {
  final AuroraMonthlyActivity currentMonth;
  final bool isAuroraCreator;
  final String? membership;
  final int? membershipExpiresAt;
  final List<AuroraHistoryEntry> history;

  const AuroraProgress({
    required this.currentMonth,
    required this.isAuroraCreator,
    this.membership,
    this.membershipExpiresAt,
    this.history = const [],
  });

  factory AuroraProgress.fromJson(Map<String, dynamic> j) => AuroraProgress(
    currentMonth: AuroraMonthlyActivity.fromJson(
      Map<String, dynamic>.from(j['currentMonth'] as Map? ?? {}),
    ),
    isAuroraCreator: j['isAuroraCreator'] == true,
    membership: j['membership']?.toString(),
    membershipExpiresAt: (j['membershipExpiresAt'] as num?)?.toInt(),
    history: (j['history'] as List? ?? [])
        .map(
          (e) => AuroraHistoryEntry.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList(),
  );
}
