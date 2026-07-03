class UserProfile {
  final String id;
  final String username;
  final String? handle;
  final String? avatar;
  final String? bio;
  final String? website;
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
    required this.followerCount,
    required this.followingCount,
    required this.tutorialCount,
    required this.createdAt,
    this.isFollowing = false,
  });

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
    id: j['id']?.toString() ?? '',
    username: j['username']?.toString() ?? '',
    handle: j['handle']?.toString(),
    avatar: j['avatar']?.toString(),
    bio: j['bio']?.toString(),
    website: j['website']?.toString(),
    followerCount: (j['follower_count'] as num?)?.toInt() ?? 0,
    followingCount: (j['following_count'] as num?)?.toInt() ?? 0,
    tutorialCount: (j['tutorial_count'] as num?)?.toInt() ?? 0,
    // 后端时间戳是秒级，×1000 转毫秒
    createdAt: ((j['created_at'] as num?) ?? 0).toInt() * 1000,
  );
}
