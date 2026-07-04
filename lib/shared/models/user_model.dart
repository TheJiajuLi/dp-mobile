class UserModel {
  final String id;
  final String username;
  final String email;
  final String? handle;
  final String? avatar;
  final String? bio;
  final String? website;
  final int? createdAt;
  // 后端目前还没有这4个字段（截至2026-07-04实测 PATCH /auth/me 会静默
  // 丢弃，GET /auth/me 不返回）——后端接口上线前这几个值只会停留在内存里，
  // App重启后会丢，等后端加了字段这里就能直接生效，不用再改Flutter
  final String? gender;
  final String? location;
  final String? birthday; // YYYY-MM-DD
  final String? zodiac;
  final int followerCount;
  final int followingCount;

  const UserModel({
    required this.id,
    required this.username,
    required this.email,
    this.handle,
    this.avatar,
    this.bio,
    this.website,
    this.createdAt,
    this.gender,
    this.location,
    this.birthday,
    this.zodiac,
    this.followerCount = 0,
    this.followingCount = 0,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
    id: json['id'] ?? '',
    username: json['username'] ?? '',
    email: json['email'] ?? '',
    handle: json['handle'] as String?,
    avatar: json['avatar'],
    bio: json['bio'],
    website: json['website'],
    createdAt: json['created_at'],
    gender: json['gender'] as String?,
    location: json['location'] as String?,
    birthday: json['birthday'] as String?,
    zodiac: json['zodiac'] as String?,
    followerCount: (json['follower_count'] as num?)?.toInt() ?? 0,
    followingCount: (json['following_count'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'email': email,
    'handle': handle,
    'avatar': avatar,
    'bio': bio,
    'website': website,
    'created_at': createdAt,
    'gender': gender,
    'location': location,
    'birthday': birthday,
    'zodiac': zodiac,
    'follower_count': followerCount,
    'following_count': followingCount,
  };

  UserModel copyWith({
    String? username,
    String? bio,
    String? website,
    String? avatar,
    String? gender,
    String? location,
    String? birthday,
    String? zodiac,
    int? followerCount,
    int? followingCount,
  }) => UserModel(
    id: id,
    username: username ?? this.username,
    email: email,
    handle: handle,
    avatar: avatar ?? this.avatar,
    bio: bio ?? this.bio,
    website: website ?? this.website,
    createdAt: createdAt,
    gender: gender ?? this.gender,
    location: location ?? this.location,
    birthday: birthday ?? this.birthday,
    zodiac: zodiac ?? this.zodiac,
    followerCount: followerCount ?? this.followerCount,
    followingCount: followingCount ?? this.followingCount,
  );
}
