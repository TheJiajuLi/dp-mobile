class UserProfile {
  final String id;
  final String username;
  final String? handle;
  final String? avatar;
  final String? bio;
  final String? website;
  // 后端目前还没有这3个字段（截至2026-07-04实测不返回）——后端接口
  // 上线前这几个值恒为 null，UI 那边已经做了 null 就不显示的兼容
  final String? gender;
  final String? location;
  final String? zodiac;
  int followerCount;
  final int followingCount;
  final int tutorialCount;
  final int createdAt; // 毫秒
  bool isFollowing;

  UserProfile({
    required this.id,
    required this.username,
    this.handle,
    this.avatar,
    this.bio,
    this.website,
    this.gender,
    this.location,
    this.zodiac,
    required this.followerCount,
    required this.followingCount,
    required this.tutorialCount,
    required this.createdAt,
    this.isFollowing = false,
  });

  UserProfile copyWith({String? avatar}) => UserProfile(
    id: id,
    username: username,
    handle: handle,
    avatar: avatar ?? this.avatar,
    bio: bio,
    website: website,
    gender: gender,
    location: location,
    zodiac: zodiac,
    followerCount: followerCount,
    followingCount: followingCount,
    tutorialCount: tutorialCount,
    createdAt: createdAt,
    isFollowing: isFollowing,
  );

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
    id: j['id']?.toString() ?? '',
    username: j['username']?.toString() ?? '',
    handle: j['handle']?.toString(),
    avatar: j['avatar']?.toString(),
    bio: j['bio']?.toString(),
    website: j['website']?.toString(),
    gender: j['gender']?.toString(),
    location: j['location']?.toString(),
    zodiac: j['zodiac']?.toString(),
    followerCount: (j['follower_count'] as num?)?.toInt() ?? 0,
    followingCount: (j['following_count'] as num?)?.toInt() ?? 0,
    tutorialCount: (j['tutorial_count'] as num?)?.toInt() ?? 0,
    // 后端时间戳是秒级，×1000 转毫秒
    createdAt: ((j['created_at'] as num?) ?? 0).toInt() * 1000,
  );
}
