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
  // 小红书风格的"IP属地"——IP 反查出的地区，系统判定、用户不可编辑，
  // 跟上面用户自己填的 location（"所在地"）是两码事。实测确认 2026-07-05
  // 当天 GET /auth/me 完全不返回这个字段，先按后端还没上线的其它字段
  // （gender/location/birthday/zodiac）同款套路加上，等后端加了字段直接生效
  final String? ipLocation;
  // 兴趣标签，2026-07-06 后端上线（GET/PATCH /auth/me 都已经支持）
  final List<String> tags;
  // 职业——后端还没有这个字段（跟 gender/location/birthday/zodiac 当初
  // 上线前一样），PATCH /auth/me 现在会静默丢弃，先靠本地 SharedPreferences
  // 存底，等后端加了字段直接生效
  final String? occupation;
  // 元老创作者——早期加入且持续产出的创作者标识，后端还没有这个字段
  // （截至2026-07-07），先按 gender/occupation 这些字段同样的套路加上，
  // 恒为 false 不影响现有用户，等后端 ALTER TABLE 加了这一列直接生效
  final bool isFoundingCreator;
  // 极光创作者——达标（月度活跃满足任意3项）自动获得，跟 is_founding_creator
  // 同款语义。实测确认（2026-07-09）is_aurora_creator 列已经在 users 表里，
  // GET /auth/me 也已经把它加进 SELECT 列表了，不是过渡期占位字段
  final bool isAuroraCreator;
  // 会员等级——实测确认（2026-07-08）GET /auth/me 的 SELECT 列表里已经有
  // membership/membership_expires_at 这两列，不是"后端还没上线"的过渡态
  // 字段，可以直接读。之前 VIP 徽章/Pro 权限判断都是绕道另外请求
  // GET /auth/storage/usage 才能拿到 membership，现在能直接从
  // currentUserProvider 读，不用再多打一次网络请求
  final String? membership;
  final int? membershipExpiresAt;

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
    this.ipLocation,
    this.tags = const [],
    this.occupation,
    this.isFoundingCreator = false,
    this.isAuroraCreator = false,
    this.membership,
    this.membershipExpiresAt,
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
    ipLocation: json['ip_location'] as String?,
    tags:
        (json['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    occupation: json['occupation'] as String?,
    isFoundingCreator:
        json['is_founding_creator'] == true ||
        json['is_founding_creator'] == 1,
    isAuroraCreator:
        json['is_aurora_creator'] == true || json['is_aurora_creator'] == 1,
    membership: json['membership'] as String?,
    membershipExpiresAt: (json['membership_expires_at'] as num?)?.toInt(),
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
    'ip_location': ipLocation,
    'tags': tags,
    'occupation': occupation,
    'is_founding_creator': isFoundingCreator,
    'is_aurora_creator': isAuroraCreator,
    'membership': membership,
    'membership_expires_at': membershipExpiresAt,
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
    String? ipLocation,
    List<String>? tags,
    String? occupation,
    bool? isFoundingCreator,
    bool? isAuroraCreator,
    String? membership,
    int? membershipExpiresAt,
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
    ipLocation: ipLocation ?? this.ipLocation,
    tags: tags ?? this.tags,
    occupation: occupation ?? this.occupation,
    // 会员/元老标识之前 copyWith 完全没带这两个字段——不是没暴露覆写
    // 参数，是连"原样保留"都没做，调用方每次 copyWith（换头像/改资料）
    // 都会把这两个字段悄悄重置成默认值（isFoundingCreator=false、
    // membership=null）。这是一个真实存在的 latent bug，现在补上
    isFoundingCreator: isFoundingCreator ?? this.isFoundingCreator,
    isAuroraCreator: isAuroraCreator ?? this.isAuroraCreator,
    membership: membership ?? this.membership,
    membershipExpiresAt: membershipExpiresAt ?? this.membershipExpiresAt,
  );
}
