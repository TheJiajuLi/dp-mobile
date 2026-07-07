// 实测确认（2026-07-05）：GET /auth/columns/mine、/auth/columns/:id、
// /auth/users/:id/columns 三个接口返回的 column 对象字段完全一致，包括
// view_count/like_count/save_count——这三个字段虽然 db.ts 里的建表语句
// 没有定义，但线上库实际有这几列，接口稳定返回 0（没有任何接口会去真的
// +1，纯展示占位，不代表真的在统计浏览/点赞/收藏）
class ColumnModel {
  final String id;
  final String userId;
  final String name;
  final String? description;
  final String? coverImage;
  final int articleCount;
  final int viewCount;
  final int likeCount;
  final int saveCount;
  final int subscriberCount;
  final String? username;
  final String? avatar;
  final String? handle;
  final int createdAt;
  // 元老创作者标识——后端还没有这个字段，恒为 false，等后端在
  // 专栏接口的 SELECT 里加上 is_founding_creator 直接生效
  final bool isFoundingCreator;

  const ColumnModel({
    required this.id,
    required this.userId,
    required this.name,
    this.description,
    this.coverImage,
    required this.articleCount,
    required this.viewCount,
    required this.likeCount,
    required this.saveCount,
    required this.subscriberCount,
    this.username,
    this.avatar,
    this.handle,
    required this.createdAt,
    this.isFoundingCreator = false,
  });

  factory ColumnModel.fromJson(Map<String, dynamic> j) => ColumnModel(
    id: j['id'] as String? ?? '',
    userId: j['user_id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    description: j['description'] as String?,
    coverImage: j['cover_image'] as String?,
    articleCount: (j['article_count'] as num?)?.toInt() ?? 0,
    viewCount: (j['view_count'] as num?)?.toInt() ?? 0,
    likeCount: (j['like_count'] as num?)?.toInt() ?? 0,
    saveCount: (j['save_count'] as num?)?.toInt() ?? 0,
    subscriberCount: (j['subscriber_count'] as num?)?.toInt() ?? 0,
    username: j['username'] as String?,
    avatar: j['avatar'] as String?,
    handle: j['handle'] as String?,
    createdAt: (j['created_at'] as num?)?.toInt() ?? 0,
    isFoundingCreator:
        j['is_founding_creator'] == true || j['is_founding_creator'] == 1,
  );
}
