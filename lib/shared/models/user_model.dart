class UserModel {
  final String id;
  final String username;
  final String email;
  final String? avatar;
  final String? bio;
  final int? createdAt;

  const UserModel({
    required this.id,
    required this.username,
    required this.email,
    this.avatar,
    this.bio,
    this.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
    id: json['id'] ?? '',
    username: json['username'] ?? '',
    email: json['email'] ?? '',
    avatar: json['avatar'],
    bio: json['bio'],
    createdAt: json['created_at'],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'email': email,
    'avatar': avatar,
    'bio': bio,
    'created_at': createdAt,
  };
}
