import 'dart:convert';

class TutorialModel {
  final String id;
  final String title;
  final String username;
  final String? userId;
  final String? coverImage;
  final String? summary;
  // 摘要为空时的展示兜底——后端 GET /auth/tutorials 优先返回作者填写的
  // summary，没填就回退成正文（blocks）前120字纯文本。前端这里再兜底
  // 一层 summary，是防后端还没部署这个字段/旧缓存响应里没有这个 key
  // 的情况，不是重复实现同一套截断逻辑
  final String? preview;
  final String? avatar;
  final List<String> tags;
  final int likes;
  final int views;
  final int createdAt;
  // 元老创作者标识——后端还没有这个字段，恒为 false，等后端在
  // 教程列表接口的 SELECT 里加上 is_founding_creator 直接生效
  final bool isFoundingCreator;
  // 状态：draft / published / deleted(下架) / private(仅自己可见)。
  // 后端 listTutorials/getTutorial 都会返回，创作者中心「作品管理」按它分区
  final String status;
  // 收藏/评论/分享——后端已在 listTutorials 的 SELECT 里补上子查询
  // （save_count/comment_count/shares），作品管理页的数据行/统计卡直接用
  final int saveCount;
  final int commentCount;
  final int shares;
  // 是否允许转载——后端字段 allow_repost，默认 1（允许）。关闭时详情页
  // 隐藏 PDF 导出/分享入口。缺字段时默认 true（安全降级：拿不到就照常显示）
  final bool allowRepost;

  const TutorialModel({
    required this.id,
    required this.title,
    required this.username,
    this.userId,
    this.coverImage,
    this.summary,
    this.preview,
    this.avatar,
    this.tags = const [],
    required this.likes,
    required this.views,
    required this.createdAt,
    this.isFoundingCreator = false,
    this.status = 'published',
    this.saveCount = 0,
    this.commentCount = 0,
    this.shares = 0,
    this.allowRepost = true,
  });

  factory TutorialModel.fromJson(Map<String, dynamic> json) {
    return TutorialModel(
      id: json['id'].toString(),
      title: json['title']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      userId: json['user_id']?.toString(),
      coverImage: json['cover_image']?.toString(),
      summary: json['summary']?.toString(),
      preview: json['preview']?.toString() ?? json['summary']?.toString(),
      avatar: json['avatar']?.toString(),
      tags: _parseTags(json['tags']),
      likes: _parseInt(json['likes']),
      views: _parseInt(json['views']),
      // 后端时间戳是秒级，DateTime 需要毫秒，所以 ×1000
      createdAt: _parseInt(json['created_at']) * 1000,
      isFoundingCreator:
          json['is_founding_creator'] == true ||
          json['is_founding_creator'] == 1,
      status: json['status']?.toString() ?? 'published',
      saveCount: _parseInt(json['save_count']),
      commentCount: _parseInt(json['comment_count']),
      shares: _parseInt(json['shares']),
      // 后端返回 int 0/1，也兼容 bool；缺字段默认 true（允许）
      allowRepost: _parseBool(json['allow_repost'], fallback: true),
    );
  }

  TutorialModel copyWith({String? status}) {
    return TutorialModel(
      id: id,
      title: title,
      username: username,
      userId: userId,
      coverImage: coverImage,
      summary: summary,
      preview: preview,
      avatar: avatar,
      tags: tags,
      likes: likes,
      views: views,
      createdAt: createdAt,
      isFoundingCreator: isFoundingCreator,
      status: status ?? this.status,
      saveCount: saveCount,
      commentCount: commentCount,
      shares: shares,
      allowRepost: allowRepost,
    );
  }

  static bool _parseBool(dynamic v, {bool fallback = false}) {
    if (v == null) return fallback;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v.toString().toLowerCase();
    if (s == '0' || s == 'false' || s == '') return false;
    if (s == '1' || s == 'true') return true;
    return fallback;
  }

  static int _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static List<String> _parseTags(dynamic tags) {
    if (tags == null) return [];
    if (tags is List) return List<String>.from(tags.map((e) => e.toString()));
    if (tags is String) {
      try {
        final decoded = jsonDecode(tags);
        if (decoded is List) {
          return List<String>.from(decoded.map((e) => e.toString()));
        }
      } catch (_) {}
      return tags
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return [];
  }
}
