class TutorialModel {
  final String id;
  final String title;
  final String author;
  final int likes;
  final int? createdAt;

  const TutorialModel({
    required this.id,
    required this.title,
    required this.author,
    required this.likes,
    this.createdAt,
  });

  factory TutorialModel.fromJson(Map<String, dynamic> json) {
    final authorField = json['author'];
    final authorName = authorField is Map
        ? (authorField['username']?.toString() ?? '')
        : (authorField?.toString() ?? '');
    final likesField = json['likes'];
    final likes = likesField is int
        ? likesField
        : int.tryParse(likesField?.toString() ?? '') ?? 0;
    final createdAtField = json['created_at'];

    return TutorialModel(
      id: json['id'].toString(),
      title: json['title']?.toString() ?? '',
      author: authorName,
      likes: likes,
      // 后端时间戳是秒级，DateTime 需要毫秒，所以 ×1000
      createdAt: createdAtField is num ? createdAtField.toInt() * 1000 : null,
    );
  }
}
