import 'dart:convert';

class TutorialModel {
  final String id;
  final String title;
  final String username;
  final String? coverImage;
  final String? summary;
  final String? avatar;
  final List<String> tags;
  final int likes;
  final int views;
  final int createdAt;

  const TutorialModel({
    required this.id,
    required this.title,
    required this.username,
    this.coverImage,
    this.summary,
    this.avatar,
    this.tags = const [],
    required this.likes,
    required this.views,
    required this.createdAt,
  });

  factory TutorialModel.fromJson(Map<String, dynamic> json) {
    return TutorialModel(
      id: json['id'].toString(),
      title: json['title']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      coverImage: json['cover_image']?.toString(),
      summary: json['summary']?.toString(),
      avatar: json['avatar']?.toString(),
      tags: _parseTags(json['tags']),
      likes: _parseInt(json['likes']),
      views: _parseInt(json['views']),
      // 后端时间戳是秒级，DateTime 需要毫秒，所以 ×1000
      createdAt: _parseInt(json['created_at']) * 1000,
    );
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
      return tags.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    }
    return [];
  }
}
