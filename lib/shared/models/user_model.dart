class UserModel {
  final String id;
  final String username;
  final String email;
  final String? avatar;
  final String? bio;
  final String? website;
  final int? createdAt;

  const UserModel({
    required this.id,
    required this.username,
    required this.email,
    this.avatar,
    this.bio,
    this.website,
    this.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
    id: json['id'] ?? '',
    username: json['username'] ?? '',
    email: json['email'] ?? '',
    avatar: json['avatar'],
    bio: json['bio'],
    website: json['website'],
    createdAt: json['created_at'],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'email': email,
    'avatar': avatar,
    'bio': bio,
    'website': website,
    'created_at': createdAt,
  };

  UserModel copyWith({
    String? username,
    String? bio,
    String? website,
    String? avatar,
  }) => UserModel(
    id: id,
    username: username ?? this.username,
    email: email,
    avatar: avatar ?? this.avatar,
    bio: bio ?? this.bio,
    website: website ?? this.website,
    createdAt: createdAt,
  );
}
