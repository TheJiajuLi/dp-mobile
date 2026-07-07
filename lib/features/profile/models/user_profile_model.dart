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
  // 小红书风格的"IP属地"，系统判定、不可编辑，跟上面用户自己填的
  // location（"所在地"）是两码事。实测确认 2026-07-05 GET /auth/users/
  // profile/:identifier 不返回这个字段，先按 gender/location/zodiac
  // 同款套路加上，等后端上线直接生效
  final String? ipLocation;
  // 兴趣标签——2026-07-06 后端上线，GET /auth/me、GET /auth/users/
  // profile/:identifier 都已经返回这个字段，不是像上面几个字段那样的
  // 过渡期占位
  final List<String> tags;
  // 认证徽章——后端目前没有这个字段，恒为 false，UI 已经按"false 就不显示"
  // 处理，等后端加上 is_verified 字段直接生效，不需要再改这里
  final bool isVerified;
  // 会员等级——GET /auth/users/profile/:identifier 目前的 SELECT 列表里
  // 没有这个字段（只有 GET /auth/storage/usage 会返回，且只针对当前登录
  // 用户自己），所以查看"别人"的主页时这里恒为 'free'，VIP 徽章会先默认
  // 显示成灰色，不是真的知道对方不是会员。等后端 SELECT 里加上
  // membership 列，这里直接生效
  final String membership;
  // 职业——后端还没有这个字段，先跟 gender/location/zodiac 一样走
  // "本地存底，等后端上线直接生效"的过渡套路
  final String? occupation;
  // 元老创作者标识——后端还没有这个字段，先跟 occupation 一样走
  // "本地/恒为false，等后端上线直接生效"的过渡套路
  final bool isFoundingCreator;

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
    this.ipLocation,
    this.tags = const [],
    this.isVerified = false,
    this.membership = 'free',
    this.occupation,
    this.isFoundingCreator = false,
  });

  UserProfile copyWith({String? avatar, List<String>? tags}) => UserProfile(
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
    ipLocation: ipLocation,
    tags: tags ?? this.tags,
    isVerified: isVerified,
    membership: membership,
    occupation: occupation,
    isFoundingCreator: isFoundingCreator,
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
    ipLocation: j['ip_location']?.toString(),
    tags: (j['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    isVerified: j['is_verified'] == true,
    membership: j['membership']?.toString() ?? 'free',
    occupation: j['occupation']?.toString(),
    isFoundingCreator:
        j['is_founding_creator'] == true || j['is_founding_creator'] == 1,
  );
}
