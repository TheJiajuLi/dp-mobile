import 'dart:convert';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme_provider.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/models/tutorial_model.dart';
import '../../../shared/utils/avatar_upload.dart';
import '../../../shared/utils/gender_label.dart';
import '../../../shared/widgets/zodiac_icon.dart';
import '../../auth/auth_service.dart';
import '../../column/models/column_model.dart';
import '../../messages/models/conversation_model.dart';
import '../../notebook/services/notebook_service.dart';
import '../../settings/providers/storage_provider.dart';
import '../../../shared/widgets/interest_tag.dart';
import '../models/user_profile_model.dart';
import '../widgets/tutorial_list_card.dart';

const _primary = Color(0xFF6366F1);
// 网易云风格视觉语言（2026-07-05 重设计）：米白底 + 近黑正文 + 紫蓝只做
// 点缀，卡片用 0.5px 细线不用阴影。深色模式下这几个不跟着主题走的固定色
// 只在浅色场景使用，深色场景仍然读 Theme.of(context) 已有的那一套
const _ink = Color(0xFF1A1A1A);
const _muted = Color(0xFF999999);
// 2026-07-06 起改成 AppColors.bg（跟首页/发现页/消息页/底部导航栏统一），
// 原来自己配的 #FAFAF8 跟 Theme.of(context).scaffoldBackgroundColor 拿到的
// #F7F7FB 是两个非常接近但不相同的浅灰白，页面之间拼接处会露出一条很淡
// 但看得出来的接缝
const _heroBg = AppColors.bg;

String _initial(String? name) {
  if (name == null || name.isEmpty) return '?';
  return name.substring(0, 1).toUpperCase();
}

// 个人主页下半部（tab内容区）深色主题下的背景色——直接复用
// app_theme.dart 深色 ThemeData 的 scaffoldBackgroundColor（#1C1C1E），
// 不是自己另配一个更深的藏青色。跟全局深色主题背景不一致，会显得这个
// 页面是另外拼上去的，不像同一个 app
const _profileDarkBg = Color(0xFF1C1C1E);
// tab栏 pinned header 顶部圆角半径——头图背景要往下多铺这么多才能让圆角
// 裁掉的三角形露出头图颜色而不是页面主背景色，两处必须用同一个值
const _kTabBarRadius = 20.0;

class UserProfileScreen extends ConsumerStatefulWidget {
  final String identifier; // username 或 handle
  // 作为底部导航"我的" tab 用时是根级页面，没有可以返回的上一页；
  // 同时也是"这是不是我自己"最可靠的信号——路由层已经明确告诉我们了，
  // 不用等 profile 异步加载完再去比对 id
  final bool showBackButton;
  const UserProfileScreen({
    super.key,
    required this.identifier,
    this.showBackButton = true,
  });

  @override
  ConsumerState<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends ConsumerState<UserProfileScreen>
    with SingleTickerProviderStateMixin {
  late final bool _showNotebookTab = !widget.showBackButton;
  late final TabController _tabCtrl;
  UserProfile? _profile;
  List<TutorialModel> _tutorials = [];
  List<Map<String, dynamic>> _notebooks = [];
  List<ColumnModel> _columns = [];
  String? _zodiac;
  List<String> _links = [];
  bool _loading = true;
  // 对方设置了"主页不公开"——GET /auth/users/profile/:id 会整体 403
  // 拒绝，不带任何资料数据。这种情况下退化成只显示头像/用户名/id 这几项
  // 基础信息，发布的内容/收藏这些直接隐藏，而不是一直转圈
  bool _profileBlocked = false;
  // 防止 build() 里那个"账号对不上就重新加载"的保险重复触发——异步加载
  // 完成、_profile 更新之前，同一批连续几帧 build() 都会看到"对不上"，
  // 不加这个会对着同一次账号变化打好几次一样的请求
  bool _reloadingForAccountChange = false;
  bool _startingChat = false;
  bool _uploadingAvatar = false;
  String? _coverImageUrl;
  bool _uploadingCover = false;

  int get _totalLikes => _tutorials.fold(0, (sum, t) => sum + t.likes);
  int get _totalViews => _tutorials.fold(0, (sum, t) => sum + t.views);

  // 真实计算的"连续创作天数"——从今天开始倒推，_tutorials 里有发布记录的
  // 那些自然日连续多少天，不是后端字段（后端和Web参考站都没有这个统计），
  // 今天没发布过就是 0（不给"昨天算不算"的宽限），streak 为 0 时头图区
  // 那张卡片直接不显示，不用假数字凑颜值
  int get _creationStreak {
    if (_tutorials.isEmpty) return 0;
    final days = _tutorials.map((t) {
      final d = DateTime.fromMillisecondsSinceEpoch(t.createdAt);
      return DateTime(d.year, d.month, d.day);
    }).toSet();
    var streak = 0;
    var cursor = DateTime.now();
    cursor = DateTime(cursor.year, cursor.month, cursor.day);
    while (days.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  // 2026-07-06 起改为用户在编辑资料页自己选的"兴趣标签"（最多3个，后端
  // users.tags 字段），不再从发布过的教程 tags 里统计频率——那套自动推断
  // 已经被编辑资料页里可以直接设置的显式字段取代
  List<String> _interestTags() => _profile?.tags.take(3).toList() ?? [];

  // 头图右上角链接图标要展示的全部个人链接——_links（本地存储）+
  // website（后端字段）合并去重，保持原有顺序
  List<String> _allLinks() {
    final all = [
      ..._links,
      if (_profile?.website?.isNotEmpty == true) _profile!.website!,
    ];
    return all.toSet().toList();
  }

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _showNotebookTab ? 5 : 4, vsync: this);
    _loadProfile();
    if (_showNotebookTab) _loadNotebooks();
  }

  Future<void> _loadColumns(String userId) async {
    final res = await ref
        .read(apiClientProvider)
        .get('/auth/users/$userId/columns');
    if (!mounted) return;
    if (res.success && res.data != null) {
      setState(() {
        _columns = ((res.data as Map)['columns'] as List? ?? [])
            .map(
              (j) => ColumnModel.fromJson(Map<String, dynamic>.from(j as Map)),
            )
            .toList();
      });
    }
  }

  Future<void> _loadProfile() async {
    final api = ref.read(apiClientProvider);
    final currentUser = ref.read(currentUserProvider);
    final isOwnProfile =
        currentUser != null &&
        (widget.identifier == currentUser.username ||
            widget.identifier == currentUser.handle ||
            widget.identifier == currentUser.id);

    // 自己的主页：直接用 currentUserProvider（/auth/me 的数据）拼，完全
    // 不走 GET /auth/users/profile/:identifier——实测确认过，那个接口的
    // "该用户已设置主页不公开" 403 连用户查看自己都拦：一旦自己把
    // publicProfile 关掉，就会被自己的隐私设置锁在自己主页外面（403，
    // 走到上面 _profileBlocked 那条兜底分支，显示"该用户已设置主页不
    // 公开"——但"该用户"其实就是自己）。自己的资料本来就不该受这个
    // 限制，也没有必要为了看自己的主页多打一次网络请求
    if (isOwnProfile) {
      final profile = UserProfile(
        id: currentUser.id,
        username: currentUser.username,
        handle: currentUser.handle,
        avatar: currentUser.avatar,
        bio: currentUser.bio,
        website: currentUser.website,
        gender: currentUser.gender,
        location: currentUser.location,
        zodiac: currentUser.zodiac,
        followerCount: currentUser.followerCount,
        followingCount: currentUser.followingCount,
        tutorialCount: 0,
        createdAt: (currentUser.createdAt ?? 0) * 1000,
        ipLocation: currentUser.ipLocation,
        tags: currentUser.tags,
      );
      await _loadLocalPrefs(profile);
      if (!widget.showBackButton) {
        ref.read(myFollowingCountProvider.notifier).state =
            profile.followingCount;
      }
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _profileBlocked = false;
        _loading = false;
      });
      await _loadTutorials(currentUser.id, currentUser.username);
      await _loadColumns(currentUser.id);
      return;
    }

    final profileRes = await api.get(
      '/auth/users/profile/${widget.identifier}',
    );

    // 主页被对方设置为"不公开"：接口整体 403 拒绝，实测不带任何资料
    // 字段（不是"隐藏部分字段"，是完全不给）。退回老的
    // GET /auth/users/:identifier 兜底——这个接口不受隐私开关影响，
    // 只能拿到 id/用户名/handle/头像 这几项基础信息，够拼一个 NetEase
    // 风格的受限资料页：发布的内容/收藏这些都拿不到就不展示
    if (!profileRes.success && profileRes.statusCode == 403) {
      final basicRes = await api.get('/auth/users/${widget.identifier}');
      if (!mounted) return;
      if (basicRes.success && basicRes.data != null) {
        final profile = UserProfile.fromJson(
          basicRes.data as Map<String, dynamic>,
        );
        // 关注状态接口不受隐私开关影响（实测私密资料照样 200），能拿就拿，
        // 让受限视图里的关注按钮显示真实状态
        final currentUserId = currentUser?.id;
        if (currentUserId != null && currentUserId != profile.id) {
          final followRes = await api.get(
            '/auth/users/${profile.id}/follow-status',
          );
          if (followRes.success && followRes.data != null) {
            profile.isFollowing = followRes.data['isFollowing'] == true;
          }
        }
        if (!mounted) return;
        setState(() {
          _profile = profile;
          _profileBlocked = true;
          _tutorials = [];
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
      return;
    }

    if (!profileRes.success || profileRes.data == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final profile = UserProfile.fromJson(
      profileRes.data as Map<String, dynamic>,
    );

    // 检查是否已关注
    final currentUserId = currentUser?.id;
    if (currentUserId != null && currentUserId != profile.id) {
      final followRes = await api.get(
        '/auth/users/${profile.id}/follow-status',
      );
      if (followRes.success && followRes.data != null) {
        profile.isFollowing = followRes.data['isFollowing'] == true;
      }
    }

    await _loadLocalPrefs(profile);

    if (!mounted) return;
    setState(() {
      _profile = profile;
      _profileBlocked = false;
      _loading = false;
    });
    await _loadTutorials(profile.id, profile.username);
    await _loadColumns(profile.id);
  }

  // 实测 GET /auth/tutorials?author=xxx 这个后端参数目前不生效——传什么
  // 都返回全站已发布教程，不是这个用户自己的。后端修好之前先客户端过滤，
  // 否则每个人的主页都会显示别人的教程（数据串读）。自己的主页/别人的
  // 主页都要这份过滤，抽成共用方法，不要两处各写一份容易走样
  Future<void> _loadTutorials(String userId, String username) async {
    final api = ref.read(apiClientProvider);
    var tuts = <TutorialModel>[];
    final tutRes = await api.get(
      '/auth/tutorials',
      queryParameters: {'author': username, 'status': 'published'},
    );
    if (tutRes.success && tutRes.data != null) {
      final rawList = (tutRes.data['tutorials'] as List?) ?? [];
      tuts = rawList
          .map((j) => TutorialModel.fromJson(j as Map<String, dynamic>))
          .where((t) => t.userId == userId)
          .toList();
    }
    if (!mounted) return;
    setState(() => _tutorials = tuts);
  }

  // 个人链接/背景图目前只存在本地 SharedPreferences（后端没有这几个
  // 字段——背景图倒是可以真的传去 COS，只是没有专门的"背景图 URL"字段能
  // 存回用户资料，只能借用 /auth/files/upload 传完之后自己存本地）
  //
  // 星座优先用后端 profile.zodiac；后端字段没上线前这里恒为 null，
  // 退回读本地 legacy key（只有"我自己"之前用编辑资料页存过才会命中，
  // 别人的主页本来就读不到别人设备上的本地存储）
  Future<void> _loadLocalPrefs(UserProfile profile) async {
    final userId = profile.id;
    final prefs = await SharedPreferences.getInstance();
    final zodiac = profile.zodiac ?? prefs.getString('${userId}_zodiac');
    final linksJson = prefs.getString('${userId}_links') ?? '[]';
    final coverImageUrl = prefs.getString('${userId}_cover_image');
    var links = <String>[];
    try {
      final decoded = jsonDecode(linksJson);
      if (decoded is List) links = decoded.map((e) => e.toString()).toList();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _zodiac = zodiac;
      _links = links.take(3).toList();
      _coverImageUrl = coverImageUrl;
    });
  }

  Future<void> _pickAndUploadCover() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 640,
      imageQuality: 85,
    );
    if (file == null) return;

    final bytes = await file.readAsBytes();
    setState(() => _uploadingCover = true);
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: 'cover.jpg',
          contentType: DioMediaType('image', 'jpeg'),
        ),
      });

      // ApiClient.post 内部吞掉了 DioException，不会抛异常——失败与否要看
      // res.success，不能只靠 try/catch
      final res = await ref
          .read(apiClientProvider)
          .post('/auth/files/upload', data: formData);
      if (!res.success) {
        // 下面 catch 块会用 l10n.uploadFailedWithReason(...) 再套一层
        // "上传失败：" 前缀，这里只能给纯原因文本，不能是完整句子，否则
        // 会跟外层前缀重复。widget 已经卸载的话这个 Exception 反正不会被
        // 展示出来（catch 块自己也会先判 mounted），随便给个占位原因即可，
        // 不值得为了这一步再去访问已经不安全的 context
        final reason =
            res.message ??
            (mounted
                ? AppLocalizations.of(context)!.requestFailed
                : 'request failed');
        throw Exception(reason);
      }

      final url = (res.data as Map)['url'] as String?;
      if (url != null) {
        final userId = _profile?.id ?? '';
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('${userId}_cover_image', url);
        setState(() => _coverImageUrl = url);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.coverUpdated)),
        );
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.uploadFailedWithReason(
                e.toString().replaceAll('Exception: ', ''),
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingCover = false);
    }
  }

  Future<void> _loadNotebooks() async {
    final userId = ref.read(currentUserProvider)?.id ?? 'guest';
    final list = await NotebookService(userId).getRecentList();
    if (!mounted) return;
    setState(() => _notebooks = list);
  }

  Future<void> _toggleFollow() async {
    if (_profile == null) return;
    final api = ref.read(apiClientProvider);
    final res = _profile!.isFollowing
        ? await api.delete('/auth/users/${_profile!.id}/follow')
        : await api.post('/auth/users/${_profile!.id}/follow');

    if (!res.success) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(
              context,
            )!.actionFailedWithReason('${res.message}'),
          ),
        ),
      );
      return;
    }
    final willFollow = !_profile!.isFollowing;
    setState(() {
      if (_profile!.isFollowing) {
        _profile!.isFollowing = false;
        _profile!.followerCount--;
      } else {
        _profile!.isFollowing = true;
        _profile!.followerCount++;
      }
    });

    // 这里改的是"对方"的粉丝数（上面已经更新）。这个动作同时也让"我"的
    // 关注数 +1/-1——这个数字显示在我自己主页那个常驻的 UserProfileScreen
    // 实例上，不会自动重新加载，所以要通过共享 provider 通知它
    final current = ref.read(myFollowingCountProvider);
    ref.read(myFollowingCountProvider.notifier).state =
        (current ?? 0) + (willFollow ? 1 : -1);

    if (willFollow) {
      await _checkMutualFollowAndNotify();
    }
  }

  // 实测确认：GET /auth/users/:id/follow-status 永远是"当前登录用户是否
  // 关注了 :id"，查的是调用者自己的方向，没法用来问"对方是否关注了我"——
  // 刚关注完对方之后拿这个接口查对方的 follow-status，问到的其实还是
  // "我是否关注了对方"（当然是 true，没有意义）。真正能确认"对方是否
  // 关注我"的办法是查自己的粉丝列表 GET /auth/users/:myId/followers，
  // 看对方 id 在不在里面——这个列表本来就是"谁关注了我"，方向是对的
  Future<void> _checkMutualFollowAndNotify() async {
    final l10n = AppLocalizations.of(context)!;
    final currentUserId = ref.read(currentUserProvider)?.id;
    if (currentUserId == null || _profile == null) return;

    final res = await ref
        .read(apiClientProvider)
        .get('/auth/users/$currentUserId/followers');
    if (!mounted) return;
    final followers = (res.success && res.data != null)
        ? ((res.data['followers'] as List?) ?? [])
        : const [];
    final theyFollowMe = followers.any(
      (f) => f['id']?.toString() == _profile!.id,
    );

    if (theyFollowMe) {
      _showMutualFollowDialog();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.followedWaitingForFollowBack(_profile!.username),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 3),
          backgroundColor: _primary,
        ),
      );
    }
  }

  void _showMutualFollowDialog() {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Color(0xFFEEF0FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.favorite, color: _primary, size: 32),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.mutualFollowTitle(_profile!.username),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.mutualFollowBody,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.grey,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _startChat();
            },
            child: Text(
              l10n.sendMessageAction,
              style: const TextStyle(color: Colors.white),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.gotIt, style: const TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  Future<void> _startChat() async {
    if (_profile == null || _startingChat) return;

    final currentUserId = ref.read(currentUserProvider)?.id;
    debugPrint('[Chat] 发消息按钮点击');
    debugPrint('[Chat] profileId: ${_profile?.id}');
    debugPrint('[Chat] currentUserId: $currentUserId');

    // 未登录时跳登录页，而不是让后面的请求带着空 token 去打后端再报错
    if (currentUserId == null) {
      debugPrint('[Chat] 未登录，跳转登录页');
      if (mounted) context.push('/login');
      return;
    }

    setState(() => _startingChat = true);
    try {
      final api = ref.read(apiClientProvider);

      // 查找现有会话
      final res = await api.get('/auth/conversations');
      if (!res.success) {
        debugPrint('[Chat] /auth/conversations 请求失败: ${res.message}');
      }
      if (res.success && res.data != null) {
        final convs = (res.data['conversations'] as List?) ?? [];
        final existing = convs.cast<Map<String, dynamic>?>().firstWhere(
          (c) => c?['other_user_id']?.toString() == _profile!.id,
          orElse: () => null,
        );
        if (existing != null) {
          if (!mounted) return;
          context.push(
            '/messages/chat/${existing['id']}',
            extra: Conversation.fromJson(existing),
          );
          return;
        }
      }

      // 没有现成会话，发一条消息创建新会话
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      final msgRes = await api.post(
        '/auth/messages',
        data: {
          'toUserId': _profile!.id,
          'content': l10n.defaultGreetingMessage,
          'type': 'text',
        },
      );
      if (!msgRes.success || msgRes.data == null) {
        debugPrint('[Chat] /auth/messages 请求失败: ${msgRes.message}');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.sendFailedWithReason('${msgRes.message}')),
          ),
        );
        return;
      }
      if (!mounted) return;
      // /auth/messages 只返回 {message, messageId, conversationId}，没有
      // 对方的 username/avatar——用已经加载好的 _profile 拼一个 Conversation，
      // 不然 ChatScreen 拿到的 conversation 是 null，发消息会因为
      // otherUserId 是空字符串而在 _send() 里直接静默 return
      context.push(
        '/messages/chat/${msgRes.data['conversationId']}',
        extra: Conversation(
          id: msgRes.data['conversationId'].toString(),
          otherUserId: _profile!.id,
          otherUsername: _profile!.username,
          otherAvatar: _profile!.avatar,
          unreadCount: 0,
        ),
      );
    } finally {
      if (mounted) setState(() => _startingChat = false);
    }
  }

  void _todo(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showAvatarOptions() {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      // showModalBottomSheet 传 backgroundColor: Colors.transparent 时，
      // 弹层自带的 Material 会变成 MaterialType.transparency（没有颜色）。
      // 下面的 ListTile 找 Material 祖先画点击水波纹时，会往上找到这个
      // 透明 Material，而不是这层 Container——Container 不是 Material，
      // 水波纹就没有画布可画，Flutter 会打印"ListTile background color
      // or ink splashes may be invisible"警告。用 Material 包一层给
      // ListTile 一个真正带颜色的画布，而不是 Container
      //
      // 颜色用 scaffoldBackgroundColor 而不是 cardColor——底部导航栏
      // （main_shell.dart）用的就是 scaffoldBackgroundColor 这一套
      // （浅色 AppColors.bg / 深色 #1C1C1E），cardColor 在两个主题下都是
      // 另一个更浅/更亮的色号，弹层跟导航栏会撞出一条不统一的接缝
      builder: (ctx) => Material(
        color: Theme.of(ctx).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: Text(l10n.selectFromAlbum),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndUploadAvatar(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: Text(l10n.takePhoto),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndUploadAvatar(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.auto_awesome_outlined,
                  color: _primary,
                ),
                title: const Text('AI 生成头像'),
                subtitle: const Text(
                  '描述你想要的风格，小梦帮你生成',
                  style: TextStyle(fontSize: 11),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showAiAvatarSheet();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUploadAvatar(ImageSource source) async {
    setState(() => _uploadingAvatar = true);
    try {
      final newAvatar = await pickAndUploadAvatar(ref, source);
      if (newAvatar != null && _profile != null) {
        // 同一个固定 COS key 覆盖写——见 _setAvatarFromUrl 里的详细说明，
        // 不清缓存的话这里换头像也会遇到一样的"设置成功但界面没变"
        await CachedNetworkImage.evictFromCache(newAvatar);

        final updated = _profile!.copyWith(avatar: newAvatar);
        // 自己的主页：头像也是 currentUserProvider 里那份 UserModel 的字段，
        // 首页顶栏等其他地方的头像才会跟着一起换
        if (!widget.showBackButton) {
          final currentUser = ref.read(currentUserProvider);
          if (currentUser != null) {
            ref
                .read(authServiceProvider)
                .updateCurrentUser(currentUser.copyWith(avatar: newAvatar));
          }
        }
        setState(() => _profile = updated);
      }
      if (mounted && newAvatar != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.avatarUpdated)),
        );
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.uploadFailedWithReason(
                e.toString().replaceAll('Exception: ', ''),
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  void _showAiAvatarSheet() {
    final descCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(ctx).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF0FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_outlined,
                      size: 14,
                      color: _primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'AI 生成头像',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                decoration: InputDecoration(
                  hintText: '描述你想要的风格（可选），如"极地风景，极光，简约"',
                  hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
                  filled: true,
                  fillColor: Colors.grey[50],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _primary),
                  ),
                ),
                maxLines: 2,
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: ['极地风光', '几何抽象', '赛博朋克', '水彩插画', '星空宇宙'].map((t) {
                  return GestureDetector(
                    onTap: () => descCtrl.text = t,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        t,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF555555),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _aiGenerateAvatar(descCtrl.text.trim());
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A1A),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    '开始生成（约20秒）',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _aiGenerateAvatar(String description) async {
    // dialog 是否还在显示——避免网络异常提前抛出、或用户手动划走弹窗后，
    // 结果回来时再 pop 一次把个人主页本身也顶掉
    var dialogShowing = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: _primary),
            SizedBox(height: 16),
            Text('小梦正在生成头像...', style: TextStyle(fontSize: 14)),
            SizedBox(height: 4),
            Text(
              '通常需要15-25秒',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );

    try {
      // 图像生成实测要 15-25 秒，Dio 默认 10 秒 receiveTimeout 会提前超时——
      // 只给这一个请求单独放宽，不动全局默认值影响其他接口
      final res = await ref
          .read(apiClientProvider)
          .post(
            '/auth/xmeng/avatar',
            data: {'description': description},
            options: Options(
              sendTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 90),
            ),
          );

      if (mounted && dialogShowing) {
        dialogShowing = false;
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (!mounted) return;

      if (!res.success) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(res.message ?? '生成失败')));
        return;
      }

      final urls = List<String>.from(
        (res.data as Map?)?['urls'] as List? ?? [],
      );
      if (urls.isEmpty) return;

      if (urls.length == 1) {
        _showSingleAvatarConfirm(urls.first);
      } else {
        _showAvatarPickerSheet(urls);
      }
    } catch (e) {
      if (mounted && dialogShowing) {
        dialogShowing = false;
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('生成失败，请稍后重试')));
      }
    }
  }

  // 生成接口目前会因上游并发限流偶尔只成功1张而不是预期的多张——只有1张时
  // 不套用选择网格（网格布局在只有1个格子时显得很空），改成大图+二选一
  void _showSingleAvatarConfirm(String url) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                url,
                width: 160,
                height: 160,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '使用这张头像？',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _aiGenerateAvatar('');
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      side: const BorderSide(color: Color(0xFFD0D0D0)),
                    ),
                    child: const Text(
                      '重新生成',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _setAvatarFromUrl(url);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A1A1A),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      '使用',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAvatarPickerSheet(List<String> urls) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF0FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_outlined,
                    size: 14,
                    color: _primary,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  '选择一个头像',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              '点击即可设为头像',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 14),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1,
              ),
              itemCount: urls.length,
              itemBuilder: (ctx, i) => GestureDetector(
                onTap: () async {
                  Navigator.pop(ctx);
                  await _setAvatarFromUrl(urls[i]);
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    urls[i],
                    fit: BoxFit.cover,
                    loadingBuilder: (ctx, child, progress) => progress == null
                        ? child
                        : Container(
                            color: Colors.grey[100],
                            child: const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: _primary,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 生成结果的 url 是小梦后端另外生成的图，不是走 /auth/update-avatar 那套
  // 上传流程拿到的 COS 链接——实测确认 PATCH /auth/me 传 avatar 字段会被
  // 后端静默丢弃（响应显示"更新成功"，但回读 GET /auth/me 时 avatar 仍是
  // 传入前的值，不会报错也不生效，属于后端没接这个字段而不是权限/参数问题）。
  // 所以这里改成把生成图下载下来，再走已经验证过真正能生效的
  // /auth/update-avatar multipart 上传，跟相册/拍照选头像走同一条已验证路径
  Future<void> _setAvatarFromUrl(String url) async {
    setState(() => _uploadingAvatar = true);
    try {
      final download = await Dio().get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = download.data;
      if (bytes == null) throw Exception('下载失败');

      final formData = FormData.fromMap({
        'avatar': MultipartFile.fromBytes(
          bytes,
          filename: 'ai_avatar.jpg',
          contentType: DioMediaType('image', 'jpeg'),
        ),
      });
      final res = await ref
          .read(apiClientProvider)
          .post('/auth/update-avatar', data: formData);
      if (!res.success) throw Exception(res.message ?? '设置失败');

      final newAvatar = (res.data as Map?)?['avatar'] as String?;
      if (newAvatar != null && _profile != null) {
        // /auth/update-avatar 每次都写回同一个固定 COS key（avatars/{userId}
        // .jpg，同一用户永远是这条 URL），换头像只是覆盖同一个文件的内容——
        // _profile/currentUserProvider 的状态其实一直更新对了，界面"看起来"
        // 没变是因为 CachedNetworkImageProvider 按 URL 做缓存 key，URL 没变
        // 就不会重新拉取，头像组件继续画着旧的缓存字节。这里手动把这个 URL
        // 从磁盘+内存缓存里都清掉，逼下一次绘制重新走网络
        await CachedNetworkImage.evictFromCache(newAvatar);

        final updated = _profile!.copyWith(avatar: newAvatar);
        if (!widget.showBackButton) {
          final currentUser = ref.read(currentUserProvider);
          if (currentUser != null) {
            ref
                .read(authServiceProvider)
                .updateCurrentUser(currentUser.copyWith(avatar: newAvatar));
          }
        }
        setState(() => _profile = updated);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('头像已更新'),
            backgroundColor: Color(0xFF16A34A),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('设置失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Widget _linkRow(String displayText, String rawLink) {
    return GestureDetector(
      onTap: () => _openLink(rawLink),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.link, size: 13, color: _primary),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              displayText,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: _primary,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openLink(String link) async {
    final url = link.startsWith('http') ? link : 'https://$link';
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await canLaunchUrl(uri);
    if (!ok) {
      if (mounted) _todo(AppLocalizations.of(context)!.cannotOpenLink);
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // 对方主页设置了"不公开"：只展示头像/用户名/id 这几项基础信息（像
  // 网易云那样），发布的内容/收藏这些直接不显示——不复用下面那套带
  // Positioned 精确定位的头图布局，那套是为了让操作按钮/用户名跟正常
  // 资料页的九宫格对齐设计的，这里没有九宫格，简单摆一个居中布局即可
  Widget _buildBlockedProfile(AppLocalizations l10n, double topPad, bool isMe) {
    return Column(
      children: [
        // 真机实测抓到的真正崩溃根因：_CoverGradient 自己的注释就说明它是
        // 设计给 Stack 里的 Positioned.fill 用的（靠 Stack 已经解出来的
        // 有限尺寸撑开），但这里直接把它当 Stack 的裸的非定位子项放，Stack
        // 外层又是 Column 直接摆放、没有任何地方给出高度上限——
        // Container(height: double.infinity) 在无边界高度约束下解不出
        // 数值，直接炸 "BoxConstraints forces an infinite height"，然后
        // 每一帧重新布局都再炸一次，表现为疯狂反复的崩溃日志。点一个设置了
        // "主页不公开" 的用户头像、落到这个受限视图，就是这么崩的——
        // 用固定高度的 SizedBox 包一层，配合 Positioned.fill 用法一致
        SizedBox(
          height: 200,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Positioned.fill(child: _CoverGradient()),
              if (widget.showBackButton)
                Positioned(
                  top: topPad + 8,
                  left: 8,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                    onPressed: () => context.pop(),
                  ),
                ),
              Positioned(
                bottom: -40,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.fromBorderSide(
                        BorderSide(color: Colors.white, width: 3),
                      ),
                    ),
                    child: _buildAvatar(radius: 40),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 48),
        Text(
          _profile!.username,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        if (_profile!.handle != null) ...[
          const SizedBox(height: 4),
          Text(
            '@${_profile!.handle}',
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
        const SizedBox(height: 16),
        if (!isMe)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _startingChat ? null : _startChat,
                icon: _startingChat
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _primary,
                        ),
                      )
                    : const Icon(Icons.message_outlined, size: 16),
                label: Text(l10n.sendMessageAction),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _primary,
                  side: const BorderSide(color: _primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _toggleFollow,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _profile!.isFollowing
                      ? Theme.of(context).cardColor
                      : _primary,
                  foregroundColor: _profile!.isFollowing
                      ? Theme.of(context).textTheme.bodyLarge?.color
                      : Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                ),
                child: Text(
                  _profile!.isFollowing
                      ? l10n.followingAction
                      : l10n.followAction,
                ),
              ),
            ],
          ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 40,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.profileIsPrivate,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 头像图片本身排除出语义树——用户名在旁边另有文字承载，头像纯装饰；
  // 这个页面刚好是"点头像跳转过来"的落地页，头像图片异步解码/加载完成
  // 触发的 relayout 跟自己入场的转场动画抢语义树更新会炸断言，跟上面
  // 封面图是同一个坑
  Widget _buildAvatar({double radius = 40}) {
    final p = _profile;
    if (p?.avatar != null && p!.avatar!.isNotEmpty) {
      if (p.avatar!.startsWith('data:image')) {
        final base64Data = p.avatar!.split(',').last;
        try {
          return ExcludeSemantics(
            child: CircleAvatar(
              radius: radius,
              backgroundImage: MemoryImage(base64Decode(base64Data)),
            ),
          );
        } catch (_) {
          // 解码失败落到下面的首字母占位
        }
      } else {
        return ExcludeSemantics(
          child: CircleAvatar(
            radius: radius,
            backgroundImage: CachedNetworkImageProvider(p.avatar!),
          ),
        );
      }
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: _primary,
      child: Text(
        _initial(_profile?.username),
        style: TextStyle(
          fontSize: radius * 0.6,
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // 头图区——封面背景铺满，内容按截图参考重排：顶部图标行、头像+用户名/
  // 认证勾/handle、简介、位置+星座+链接一行（右侧挂编辑资料/关注+发消息
  // 按钮）、内容计数统计行、连续创作卡片。不再用固定屏幕高度的 Positioned
  // 绝对定位堆叠——高度跟内容走，封面图作为背景层用 Stack 撑到内容实际
  // 高度（Stack 默认按非 Positioned 子项——也就是这条内容 Column——来定
  // 尺寸，Positioned.fill 的背景层会跟着一起伸缩）
  Widget _buildProfileHeader({
    required AppLocalizations l10n,
    required bool isSelfView,
    required bool isMe,
    required String displayUsername,
    required String? displayBio,
    required String? displayLocation,
    required String? displayOccupation,
    required String? displayGender,
    required ZodiacSign? displayZodiacSign,
    required List<String> interestTags,
    required double topPad,
  }) {
    final links = _allLinks();
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      // 默认 Clip.hardEdge 会把下面圆角"卡片沿"故意超出 Stack 底边的
      // 2px 出血裁掉——那 2px 就是专门用来盖住跟下一个 sliver（pinned
      // 的 TabBar）拼接处那条灰线的，不能被裁
      clipBehavior: Clip.none,
      children: [
        // 封面图/渐变纯装饰，排除出语义树——跟 tutorial_detail_screen.dart/
        // column_detail_screen.dart 的封面图同一个坑：图片异步加载完成的
        // relayout 可能跟这个页面自己入场的转场动画抢语义树更新
        Positioned.fill(
          child: ExcludeSemantics(
            child: GestureDetector(
              onTap: isSelfView && !_uploadingCover
                  ? _pickAndUploadCover
                  : null,
              child: _coverImageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: _coverImageUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) =>
                          const _CoverGradient(),
                    )
                  : const _CoverGradient(),
            ),
          ),
        ),
        const Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x33000000), Color(0xCC000000)],
                ),
              ),
            ),
          ),
        ),
        if (_uploadingCover)
          const Positioned.fill(
            child: IgnorePointer(
              ignoring: false,
              child: ColoredBox(
                color: Colors.black38,
                child: Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
            ),
          ),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (widget.showBackButton)
                      _heroIconButton(
                        Icons.arrow_back_ios_new,
                        () => context.pop(),
                      ),
                    const Spacer(),
                    // VIP 标识不分自己/别人都显示——自己会员是真实数据
                    // （storageUsageProvider），看别人主页时目前后端
                    // GET /auth/users/profile/:identifier 还没把
                    // membership 字段加进 SELECT 列表，_profile.membership
                    // 会先恒为 'free'（灰色），等后端加了这一列直接生效
                    _buildVipBadge(isSelfView: isSelfView),
                    if (isSelfView) ...[
                      _heroIconButton(
                        Theme.of(context).brightness == Brightness.dark
                            ? Icons.dark_mode_outlined
                            : Icons.light_mode_outlined,
                        _toggleTheme,
                      ),
                      _heroIconButton(
                        Icons.people_outline,
                        () => context.push('/friends'),
                      ),
                      _heroIconButton(
                        Icons.article_outlined,
                        () => context.push('/creator'),
                      ),
                      _heroIconButton(
                        Icons.settings_outlined,
                        () => context.push('/settings'),
                      ),
                    ] else if (links.isNotEmpty)
                      _heroIconButton(
                        Icons.link_rounded,
                        () => _showLinksSheet(l10n),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.fromBorderSide(
                              BorderSide(color: Colors.white, width: 2.5),
                            ),
                          ),
                          child: _buildAvatar(radius: 34),
                        ),
                        if (_uploadingAvatar)
                          const CircleAvatar(
                            radius: 34,
                            backgroundColor: Colors.black45,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          ),
                        if (isSelfView)
                          Positioned(
                            right: -4,
                            bottom: -4,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _showAvatarOptions,
                              child: Container(
                                width: 32,
                                height: 32,
                                alignment: Alignment.center,
                                child: Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: _primary,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.camera_alt,
                                    color: Colors.white,
                                    size: 10,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  displayUsername,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              // 认证徽章——UserProfile.isVerified 目前后端恒为
                              // false，这里只是把渲染逻辑接好，字段一旦上线
                              // 直接生效，不需要再改这里
                              if (_profile!.isVerified) ...[
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.verified,
                                  size: 16,
                                  color: _primary,
                                ),
                              ],
                            ],
                          ),
                          if (_profile!.handle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              '@${_profile!.handle}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white60,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                if (interestTags.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: interestTags
                        .map((tag) => InterestTag(label: tag))
                        .toList(),
                  ),
                ],
                if (displayBio?.isNotEmpty == true) ...[
                  const SizedBox(height: 12),
                  Text(
                    displayBio!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (displayGender?.isNotEmpty ?? false)
                            _infoChip(
                              genderIconFor(displayGender!),
                              genderDisplayLabel(l10n, displayGender),
                            ),
                          if (displayLocation?.isNotEmpty ?? false)
                            _infoChip(
                              Icons.location_on_outlined,
                              displayLocation!,
                            ),
                          if (displayOccupation?.isNotEmpty ?? false)
                            _infoChip(Icons.work_outline, displayOccupation!),
                          if (displayZodiacSign != null)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ZodiacIcon(sign: displayZodiacSign, size: 12),
                                const SizedBox(width: 3),
                                Text(
                                  zodiacDisplayName(l10n, displayZodiacSign),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          if (links.isNotEmpty)
                            GestureDetector(
                              onTap: () => _openLink(links.first),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.language,
                                    size: 12,
                                    color: Colors.white70,
                                  ),
                                  const SizedBox(width: 3),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 150,
                                    ),
                                    child: Text(
                                      links.first
                                          .replaceAll('https://', '')
                                          .replaceAll('http://', ''),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isMe) ...[
                      _headerActionButton(
                        label: l10n.editProfile,
                        filled: true,
                        onTap: () async {
                          await context.push('/edit-profile');
                          if (mounted) _loadProfile();
                        },
                      ),
                      const SizedBox(width: 6),
                      _heroIconButton(
                        Icons.link_rounded,
                        () => _showLinksSheet(l10n),
                      ),
                    ] else ...[
                      _headerActionButton(
                        label: _profile!.isFollowing
                            ? l10n.followingAction
                            : l10n.followAction,
                        filled: !_profile!.isFollowing,
                        onTap: _toggleFollow,
                      ),
                      const SizedBox(width: 6),
                      _headerActionButton(
                        label: l10n.sendMessageAction,
                        filled: false,
                        loading: _startingChat,
                        onTap: _startingChat ? null : _startChat,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                _buildStatsRow(l10n),
                if (_creationStreak > 0) ...[
                  const SizedBox(height: 14),
                  _buildStreakCard(l10n),
                ],
                // 给下面圆角"卡片沿"留出空间——内容到这里为止，圆角沿贴在
                // 正下方，不会互相压着
                const SizedBox(height: _kTabBarRadius),
              ],
            ),
          ),
        ),
        // 网易云那种"卡片浮在头图上"的圆角沿——必须放在头图区自己这个
        // Stack 里（跟封面图渐变同一层，不隔着 Sliver 边界），圆角裁掉的
        // 两个直角三角形才能露出正下方的头图渐变色。之前想靠 tab栏
        // pinned header 自己的圆角去露头图颜色，指望它的绘制能"溢出"到
        // 上一个 sliver 的画面里——NestedScrollView 的普通 sliver 之间
        // 没有这种重叠机制（那是 SliverOverlapAbsorber 专门解决的问题，
        // 这里没用那套），所以完全不显示，圆角形同虚设
        //
        // bottom 故意给 -2 配 22px 高（顶部圆角位置不变，只是底边往下
        // 多铺 2px）：这块纯色矩形跟紧接着的 pinned TabBar 背景理论上是
        // 同一个颜色，但两块分属不同 sliver/RenderObject，各自独立走
        // 反走样光栅化，紧贴边界处会露出一条极淡的灰线（RRect 反走样在
        // 直边上也会画一点半透明像素，不是 TabBar 的 divider，dividerHeight
        // 设成0也去不掉）。让色块本身多铺出 2px 盖过这条拼接线，比继续
        // 在 TabBar 那边找原因更直接可靠
        Positioned(
          left: 0,
          right: 0,
          bottom: -2,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: isDarkMode ? _profileDarkBg : _heroBg,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(_kTabBarRadius),
                  topRight: Radius.circular(_kTabBarRadius),
                ),
              ),
              child: const SizedBox(
                height: _kTabBarRadius + 2,
                width: double.infinity,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _headerActionButton({
    required String label,
    required bool filled,
    VoidCallback? onTap,
    bool loading = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? Colors.white : Colors.transparent,
          border: filled ? null : Border.all(color: Colors.white54),
          borderRadius: BorderRadius.circular(8),
        ),
        child: loading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: filled ? _ink : Colors.white,
                ),
              ),
      ),
    );
  }

  // 内容计数统计行——文章/专栏/文件/收藏/点赞/阅读，纯展示不可点
  // （截图里这行没有任何一项有"可点"的视觉提示，真正的切 tab 交给下面
  // 单独的白底 TabBar）。收藏数没有真实后端聚合数据（只有单条save/unsave
  // 接口，没有"我收藏了多少篇"这个统计），显示"-"而不是编个假数字
  Widget _buildStatsRow(AppLocalizations l10n) {
    Widget stat(String value, String label) => Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: Colors.white60),
          ),
        ],
      ),
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          stat('${_tutorials.length}', l10n.articlesCountLabel),
          stat('${_columns.length}', l10n.tabColumnsLabel),
          if (_showNotebookTab)
            stat('${_notebooks.length}', l10n.tabFilesLabel),
          stat('-', l10n.tabBookmarksLabel),
          stat(_formatCount(_totalLikes), l10n.tabLikesLabel),
          stat(_formatCount(_totalViews), l10n.viewsCountLabel),
        ],
      ),
    );
  }

  // 连续创作天数卡片——真实计算（见 _creationStreak），streak 为 0 时
  // 上层已经不渲染这个 widget 了
  Widget _buildStreakCard(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Text('🔥', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.creationStreakDays(_creationStreak),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.creationStreakSubtitle,
                  style: const TextStyle(fontSize: 11, color: Colors.white60),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currentUser = ref.watch(currentUserProvider);
    // "我的" tab 是 IndexedStack 里的常驻实例，不会随便重新 initState。
    // 正常情况下账号切换会整个走一遍 /splash 让整个底部导航 shell 重新
    // 搭建，这个实例本身也会被销毁重建；这里额外加一层保险——万一哪次
    // 这个实例活了下来（或者它 initState 时 currentUserProvider 恰好还
    // 没填上，_loadProfile() 里 isOwnProfile 判断成了"查看别人"），只要
    // 发现当前登录用户跟已加载的资料对不上号，强制重新加载，不指望这个
    // 常驻实例自己会知道要刷新
    if (!widget.showBackButton &&
        !_loading &&
        !_reloadingForAccountChange &&
        currentUser != null &&
        currentUser.id != _profile?.id) {
      _reloadingForAccountChange = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted) await _loadProfile();
        _reloadingForAccountChange = false;
      });
    }
    final isMe = currentUser != null && currentUser.id == _profile?.id;
    final isSelfView = !widget.showBackButton;

    // 自己的主页：优先用 currentUserProvider（/auth/me 出的数据，编辑资料
    // 保存成功后会立刻更新，不用等这个页面重新拉一次接口）。
    // /auth/users/profile/:identifier 这个接口目前还没跟上 gender/
    // location/zodiac 这几个新字段（实测2026-07-04不返回），所以自己的
    // 主页不能靠它展示这几项，只能靠 currentUserProvider；查看别人主页时
    // 没有别的数据源，还是老老实实用 _profile
    final displayUsername = isSelfView
        ? (currentUser?.username ?? _profile?.username ?? '')
        : (_profile?.username ?? '');
    final displayBio = isSelfView
        ? (currentUser?.bio ?? _profile?.bio)
        : _profile?.bio;
    final displayLocation = isSelfView
        ? (currentUser?.location ?? _profile?.location)
        : _profile?.location;
    // 职业目前只有 currentUserProvider（本地存底）有值，_profile 走的
    // GET /auth/users/profile/:identifier 还没有这个字段，查看别人主页
    // 时恒为 null，UI 已经按"null 就不显示"处理
    final displayOccupation = isSelfView ? currentUser?.occupation : null;
    // 性别选了"保密"就当没填——不展示一个写着"保密"的标签，那样反而
    // 暴露了"这个人特意选择不说"，比干脆不出现这一项更奇怪
    final rawGender = isSelfView
        ? (currentUser?.gender ?? _profile?.gender)
        : _profile?.gender;
    final displayGender = (rawGender == null || rawGender == '保密')
        ? null
        : rawGender;
    final displayZodiacName = isSelfView
        ? (currentUser?.zodiac ?? _zodiac)
        : _zodiac;
    ZodiacSign? displayZodiacSign;
    if (displayZodiacName != null) {
      for (final sign in ZodiacSign.values) {
        if (sign.name == displayZodiacName) {
          displayZodiacSign = sign;
          break;
        }
      }
    }
    // 头像/背景 Stack 里的按钮直接手动加状态栏高度，不要再套一层 SafeArea——
    // Positioned(top: 8) 再包 SafeArea 会把状态栏高度加两遍，导致按钮比预期
    // 靠下很多，紫色背景在右上角看起来像是"没盖满"
    final topPad = MediaQuery.paddingOf(context).top;
    final interestTags = _interestTags();
    // 重设计规范给的是明确的米白 #FAFAF8，不是全局主题那个 #F7F7FB——
    // 只在浅色模式按规范覆盖，深色模式继续用主题自己的背景色，不强行套
    // 一套没设计过深色版本的固定色值
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // 状态栏图标固定用白色——头图区是深色玻璃背景，状态栏几乎总是叠在它
    // 上面；往下滚动很远、头图完全滚出视口之后状态栏区域会露出白色Tab栏
    // 背景，白图标短暂不好辨认，这是个已知的、可接受的取舍，没有再加一层
    // 监听滚动位置动态切换图标颜色的复杂度
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: isDarkMode
            ? Theme.of(context).scaffoldBackgroundColor
            : _heroBg,
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _profile == null
            ? Center(child: Text(l10n.userNotFound))
            : _profileBlocked
            ? _buildBlockedProfile(l10n, topPad, isMe)
            // 下半部（Tab栏+内容区）背景跟着主题走：深色主题用
            // _profileDarkBg，浅色主题保持原来的米白——之前改成不跟随
            // ThemePreference 的固定深色，浅色主题下背景变黑但文字/
            // Tab栏都还是按浅色配的颜色，反而看不清，这里改回去
            : Container(
                color: isDarkMode ? _profileDarkBg : _heroBg,
                child: NestedScrollView(
                  headerSliverBuilder: (ctx, _) => [
                    SliverToBoxAdapter(
                      child: _buildProfileHeader(
                        l10n: l10n,
                        isSelfView: isSelfView,
                        isMe: isMe,
                        displayUsername: displayUsername,
                        displayBio: displayBio,
                        displayLocation: displayLocation,
                        displayOccupation: displayOccupation,
                        displayGender: displayGender,
                        displayZodiacSign: displayZodiacSign,
                        interestTags: interestTags,
                        topPad: topPad,
                      ),
                    ),
                    // Tab 栏——42px 白底，跟头图区分开，选中态黑字+黑色下划线；
                    // 加了 SliverPersistentHeader(pinned:true) 让它在往下滚动
                    // 内容时贴在头图底下不消失，教程九宫格/Notebook列表比头图
                    // 长很多时，切 tab 不用先滚回顶部
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _ProfileTabBarDelegate(
                        isDark: isDarkMode,
                        tabBar: TabBar(
                          controller: _tabCtrl,
                          labelColor: isDarkMode ? Colors.white : _ink,
                          unselectedLabelColor: isDarkMode
                              ? Colors.white54
                              : const Color(0xFFBBBBBB),
                          // 5个tab挤在一行，字号跟padding都比4个tab时更紧凑
                          labelPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                          ),
                          labelStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                          unselectedLabelStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                          indicatorColor: isDarkMode ? _primary : _ink,
                          indicatorSize: TabBarIndicatorSize.label,
                          indicatorWeight: 2,
                          // Material 3 的 TabBar 即使 dividerColor 设成透明，
                          // 默认的 dividerHeight（1.0）还是会占位/画出那条
                          // 灰线——两个都要设才能真正去掉，这是 Flutter 一个
                          // 广为人知的坑
                          dividerColor: Colors.transparent,
                          dividerHeight: 0,
                          tabs: [
                            Tab(text: l10n.articlesCountLabel),
                            Tab(text: l10n.tabColumnsLabel),
                            if (_showNotebookTab) Tab(text: l10n.tabFilesLabel),
                            Tab(text: l10n.tabBookmarksLabel),
                            Tab(text: l10n.tabLikesLabel),
                          ],
                        ),
                      ),
                    ),
                  ],
                  body: TabBarView(
                    controller: _tabCtrl,
                    children: [
                      // 发布的教程——截图参考改成缩略图在左的横向列表卡片，
                      // 不再是九宫格瀑布流（那套挪到 tutorial_list_card.dart，
                      // 这里跟专栏页九宫格是不同场景各自的正确呈现方式）。
                      // padding 显式传 EdgeInsets.all(12) 而不是零——ListView
                      // 不像 GridView 那样会自动用 MediaQuery padding 当
                      // SliverPadding，这里是嵌套在 NestedScrollView+
                      // TabBarView 里的子滚动视图，顶部已经有头图+Tab栏挡着，
                      // 只是想要普通的四周留白
                      _tutorials.isEmpty
                          ? Center(
                              key: const PageStorageKey(
                                'profile-tab-tutorials-empty',
                              ),
                              child: Text(
                                l10n.noTutorialsPublished,
                                style: const TextStyle(color: Colors.grey),
                              ),
                            )
                          : ListView.builder(
                              key: const PageStorageKey(
                                'profile-tab-tutorials',
                              ),
                              padding: const EdgeInsets.all(12),
                              itemCount: _tutorials.length,
                              itemBuilder: (ctx, i) {
                                final t = _tutorials[i];
                                return TutorialListCard(
                                  tutorial: t,
                                  onTap: () =>
                                      context.push('/tutorial/${t.id}'),
                                  onMoreTap: () =>
                                      _todo(l10n.comingSoonStayTuned),
                                );
                              },
                            ),
                      _buildColumnsTab(l10n, isSelfView),
                      if (_showNotebookTab)
                        _notebooks.isEmpty
                            ? Center(
                                key: const PageStorageKey(
                                  'profile-tab-notebooks-empty',
                                ),
                                child: Text(
                                  l10n.noNotebooksYet,
                                  style: const TextStyle(color: Colors.grey),
                                ),
                              )
                            // Notebook 这个 tab 按规范是列表式（文件名+语言badge+
                            // cells数量+时间），不是跟文章/收藏/点赞一样的九宫格
                            : ListView.separated(
                                key: const PageStorageKey(
                                  'profile-tab-notebooks',
                                ),
                                padding: EdgeInsets.zero,
                                itemCount: _notebooks.length,
                                separatorBuilder: (_, _) => Divider(
                                  height: 1,
                                  color: isDarkMode
                                      ? Colors.white12
                                      : const Color(0xFFF0F0F0),
                                ),
                                itemBuilder: (ctx, i) {
                                  final nb = _notebooks[i];
                                  return _NotebookListItem(
                                    notebook: nb,
                                    onTap: () =>
                                        context.push('/notebook/${nb['id']}'),
                                  );
                                },
                              ),
                      // 收藏（占位）
                      Center(
                        key: const PageStorageKey('profile-tab-bookmarks'),
                        child: Text(
                          l10n.bookmarksComingSoon,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ),
                      // 点赞（占位）
                      Center(
                        key: const PageStorageKey('profile-tab-likes'),
                        child: Text(
                          l10n.likesListComingSoon,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  // 统计数字内联文字排列——文章/获赞/粉丝/关注挨个写在一行，last:true
  // 的最后一项右边不再留间距
  Widget _buildColumnsTab(AppLocalizations l10n, bool isSelfView) {
    if (_columns.isEmpty && !isSelfView) {
      return Center(
        key: const PageStorageKey('profile-tab-columns-empty'),
        child: Text(
          l10n.noColumnsCreatedYetPrompt,
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final placeholderColor = isDark ? Colors.white54 : const Color(0xFFC7C7CC);
    return ListView.builder(
      key: const PageStorageKey('profile-tab-columns'),
      padding: const EdgeInsets.all(12),
      itemCount: _columns.length + (isSelfView ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (isSelfView && i == _columns.length) {
          return GestureDetector(
            onTap: _showCreateColumnSheet,
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? Colors.white24 : const Color(0xFFD1D1D6),
                  width: 1.5,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.add_circle_outline,
                    color: placeholderColor,
                    size: 28,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.createColumnAction,
                    style: TextStyle(fontSize: 13, color: placeholderColor),
                  ),
                ],
              ),
            ),
          );
        }
        final col = _columns[i];
        return _ColumnCard(
          column: col,
          onTap: () => context.push('/columns/${col.id}'),
        );
      },
    );
  }

  void _showCreateColumnSheet() {
    final l10n = AppLocalizations.of(context)!;
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    l10n.createColumnAction,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      if (nameCtrl.text.trim().isEmpty) return;
                      final res = await ref
                          .read(apiClientProvider)
                          .post(
                            '/auth/columns',
                            data: {
                              'name': nameCtrl.text.trim(),
                              'description': descCtrl.text.trim(),
                            },
                          );
                      if (!ctx.mounted) return;
                      if (res.success) {
                        Navigator.pop(ctx);
                        final userId =
                            _profile?.id ?? ref.read(currentUserProvider)?.id;
                        if (userId != null) await _loadColumns(userId);
                      } else if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              l10n.actionFailedWithReason('${res.message}'),
                            ),
                          ),
                        );
                      }
                    },
                    child: Text(
                      l10n.createColumnAction,
                      style: const TextStyle(
                        color: _primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l10n.columnNameLabel,
                  hintText: l10n.columnNameHint,
                  filled: true,
                  fillColor: Colors.grey[50],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _primary),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: l10n.columnDescOptionalLabel,
                  filled: true,
                  fillColor: Colors.grey[50],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _primary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 头图信息行的小图标+文字组合——性别/地区/职业公用同一个样式
  Widget _infoChip(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 12, color: Colors.white70),
      const SizedBox(width: 3),
      Text(text, style: const TextStyle(fontSize: 11, color: Colors.white70)),
    ],
  );

  // VIP 徽章——会员是暖金色渐变字（有质感），非会员是暗淡的灰白字，
  // 两种状态都真实反映 membership，不是随手编一个"看起来高级"的常亮效果。
  // 自己查看自己主页点了跳会员管理页；查看别人主页时纯展示，不接一个
  // "点了打开我自己订阅页"这种文不对题的跳转
  Widget _buildVipBadge({required bool isSelfView}) {
    final membership = isSelfView
        ? (ref.watch(storageUsageProvider).valueOrNull?['membership']
                  as String? ??
              'free')
        : _profile?.membership ?? 'free';
    final isMember = membership == 'pro' || membership == 'pro_max';
    const style = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w800,
      fontStyle: FontStyle.italic,
      letterSpacing: 2,
      shadows: [Shadow(color: Colors.black45, blurRadius: 6)],
    );
    return GestureDetector(
      onTap: isSelfView ? () => context.push('/settings/subscription') : null,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: isMember
            ? ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Color(0xFFFFE9A8), Color(0xFFE8A33D)],
                ).createShader(bounds),
                child: Text('VIP', style: style.copyWith(color: Colors.white)),
              )
            : Text('VIP', style: style.copyWith(color: Colors.white38)),
      ),
    );
  }

  // 头图区里叠在背景上的圆形按钮（返回/汉堡）——半透明白底保证无论背景
  // 是浅色渐变占位还是用户传的任意亮度照片，深色图标都能看清
  // filled:false 给不需要白底圆圈衬托的场景用（比如链接图标）——直接裸
  // 2026-07-06 去掉了原来 BackdropFilter 毛玻璃圆角底——裸图标压在头图上，
  // 靠一圈黑色投影保证不管封面照片亮暗都还能看清，不再靠白色半透明底衬托
  Widget _heroIconButton(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.all(6),
      child: Icon(
        icon,
        color: Colors.white,
        size: 22,
        shadows: const [Shadow(color: Colors.black45, blurRadius: 6)],
      ),
    ),
  );

  // 头图右上角链接图标点开——列出全部个人链接的底部弹窗，替代原来直接
  // 跳GitHub/第一条链接的快捷方式
  void _showLinksSheet(AppLocalizations l10n) {
    final links = _allLinks();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.personalLinksLabel,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Theme.of(ctx).textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 16),
            ...links.map(
              (link) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _linkRow(
                  link.replaceAll('https://', '').replaceAll('http://', ''),
                  link,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 点一下头图那个太阳/月亮图标直接在浅色/深色之间切换，不再弹出"浅色/
  // 深色/跟随系统"三选一的底部弹窗——图标当前显示的就是
  // Theme.of(context).brightness 算出来的实际明暗态，点一下切到相反的那个
  // 就行，"跟随系统"目前没有别的入口能选，但这不是大多数用户会用到的选项
  void _toggleTheme() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ref
        .read(themeProvider.notifier)
        .setTheme(isDark ? ThemePreference.light : ThemePreference.dark);
  }

  String _formatCount(int n) {
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }
}

// 没设置背景图时的默认渐变，也是加载失败时的兜底——特意选了跟页面米白底
// 很接近的浅紫色，让头图"嵌合"进背景里，而不是像旧版那样一块很跳的深紫
// 色块。不写死高度：这层背景铺在 Stack 里的 Positioned.fill 下面，会跟着
// 前景内容（头像/用户名/简介/统计卡）自然撑开的高度一起拉伸
// 没有真实封面图时的默认底——头像/用户名这一圈无论 App 是浅色还是深色
// 主题都固定叠白字白描边（见本文件里关于崩溃修复/暗色适配的说明，这块
// 区域本来就设计成"独立于 App 主题、始终够暗"），之前是一块很平的两色
// 斜向渐变，看起来更像"占位色块"而不是产品自己的视觉。改成呼应品牌
// 愿景文案本身那句"极地——无尽的白与深邃的星空"：深靛紫到品牌
// 靛蓝（#6366F1）过渡的极光渐变，叠一层稀疏的星点，靠固定随机种子生成、
// 每次 build 位置都一样，不会一重绘就"星星在跳"
// 深色模式保留极地星空（呼应品牌文案"无尽的白与深邃的星空"）；浅色模式
// 换成晴天/海边基调——深邃的星空放在浅色页面上会显得脏，晴空蓝到暖白
// 光晕再到海面蓝的渐变配一个柔和的"日光"光晕，跟深色版的星点是同一个
// 设计语言（渐变+一个 CustomPaint 点缀层），只是主题不同
class _CoverGradient extends StatelessWidget {
  const _CoverGradient();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? const [
                      Color(0xFF120C24),
                      Color(0xFF362D6B),
                      Color(0xFF0D2436),
                    ]
                  : const [
                      Color(0xFF7EC8E3),
                      Color(0xFFFFF3D6),
                      Color(0xFF3D8FB0),
                    ],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
        ),
        if (isDark)
          const CustomPaint(painter: _StarFieldPainter())
        else
          const CustomPaint(painter: _SunGlowPainter()),
      ],
    );
  }
}

class _StarFieldPainter extends CustomPainter {
  const _StarFieldPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(7);
    final paint = Paint();
    for (var i = 0; i < 60; i++) {
      final dx = rnd.nextDouble() * size.width;
      final dy = rnd.nextDouble() * size.height;
      final radius = 0.4 + rnd.nextDouble() * 1.0;
      paint.color = Colors.white.withValues(
        alpha: 0.12 + rnd.nextDouble() * 0.3,
      );
      canvas.drawCircle(Offset(dx, dy), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StarFieldPainter oldDelegate) => false;
}

// 浅色模式的"日光"光晕——右上角一圈柔和白光，叠在晴空蓝渐变上，
// 营造晴天/海边的暖意，固定位置，不需要随机
class _SunGlowPainter extends CustomPainter {
  const _SunGlowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.78, size.height * 0.22);
    final radius = size.width * 0.32;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.55),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _SunGlowPainter oldDelegate) => false;
}

// Notebook tab 列表项：文件名 + 语言 badge + cells 数量 + 时间
class _NotebookListItem extends StatelessWidget {
  final Map<String, dynamic> notebook;
  final VoidCallback onTap;

  const _NotebookListItem({required this.notebook, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final lang = notebook['lang'] as String? ?? 'python';
    final badgeLabel =
        const {'python': 'PY', 'latex': 'TEX', 'mixed': 'MD'}[lang] ?? 'PY';
    final badgeColor =
        const {
          'python': _primary,
          'latex': Color(0xFFC026D3),
          'mixed': Color(0xFF16A34A),
        }[lang] ??
        _primary;
    final name = notebook['name'] as String? ?? '';
    final cellCount = notebook['cellCount'] as int? ?? 0;
    final updatedAt = (notebook['updatedAt'] as num?)?.toInt() ?? 0;
    final dt = DateTime.fromMillisecondsSinceEpoch(updatedAt * 1000);
    final dateStr =
        '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.description_outlined,
                size: 18,
                color: badgeColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : _ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: badgeColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          badgeLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$cellCount cells',
                        style: const TextStyle(fontSize: 12, color: _muted),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        dateStr,
                        style: const TextStyle(fontSize: 12, color: _muted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: _muted),
          ],
        ),
      ),
    );
  }
}

class _ColumnCard extends StatelessWidget {
  final ColumnModel column;
  final VoidCallback onTap;

  const _ColumnCard({required this.column, required this.onTap});

  static const _gradients = [
    [Color(0xFF4F46E5), Color(0xFF818CF8)],
    [Color(0xFF059669), Color(0xFF34D399)],
    [Color(0xFFD97706), Color(0xFFFBBF24)],
    [Color(0xFFDC2626), Color(0xFFF87171)],
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ci = column.name.isNotEmpty
        ? column.name.codeUnitAt(0) % _gradients.length
        : 0;
    final gradient = _gradients[ci];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? Colors.white24 : const Color(0xFFE5E5EA),
            width: 0.5,
          ),
        ),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(13),
                topRight: Radius.circular(13),
              ),
              child: SizedBox(
                height: 110,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 缩略图纯装饰，专栏名/篇数在下面 Positioned 里另有文字
                    // 承载，排除出语义树——跟头图/头像同一个坑
                    ExcludeSemantics(
                      child:
                          column.coverImage != null &&
                              column.coverImage!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: column.coverImage!,
                              fit: BoxFit.cover,
                              errorWidget: (context, url, error) =>
                                  _gradBg(gradient),
                            )
                          : _gradBg(gradient),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black54],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          l10n.columnContentCountLabel(column.articleCount),
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 10,
                      left: 12,
                      right: 12,
                      child: Text(
                        column.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  if (column.description?.isNotEmpty == true)
                    Text(
                      column.description!,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Colors.white54
                            : const Color(0xFF8E8E93),
                        height: 1.5,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _stat(
                        isDark,
                        Icons.remove_red_eye_outlined,
                        '${column.viewCount}',
                      ),
                      const SizedBox(width: 12),
                      _stat(
                        isDark,
                        Icons.favorite_outline,
                        '${column.likeCount}',
                      ),
                      const SizedBox(width: 12),
                      _stat(
                        isDark,
                        Icons.bookmark_outline,
                        '${column.saveCount}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gradBg(List<Color> colors) => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      ),
    ),
  );

  Widget _stat(bool isDark, IconData icon, String val) {
    final color = isDark ? Colors.white60 : Colors.grey;
    return Row(
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(val, style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }
}

// TabBar 包成 SliverPersistentHeader 需要的 delegate，背景色跟着
// isDark 走——minExtent/maxExtent 再收紧到 34（42→38→34），让整组 tab
// 尽量贴近上面圆角沿，不用随内容变化
class _ProfileTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final bool isDark;
  const _ProfileTabBarDelegate({required this.tabBar, required this.isDark});

  @override
  double get minExtent => 34;
  @override
  double get maxExtent => 34;

  // 圆角"卡片沿"是头图区自己 Stack 里的一个装饰层（_buildProfileHeader
  // 末尾那个 Positioned），不是这里——这层 pinned header 只负责紧接着
  // 圆角沿之后原样铺开一块同色平面，两者颜色一致、紧贴着，看起来才是
  // 一整块从头图上"浮"出来的圆角卡片。之前想在这里单独裁一次圆角，
  // 指望能透出上一个 sliver（头图）的颜色——NestedScrollView 的普通
  // sliver 之间没有这种重叠机制，圆角背后只会露出页面主背景色，跟这里
  // 的白/深色几乎撞色，圆角形同虚设，所以挪到头图自己的 Stack 里做
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(color: isDark ? _profileDarkBg : _heroBg),
      child: tabBar,
    );
  }

  // tabBar 每次父级 build() 都会 new 一个新实例，按引用比较 (!=) 永远为
  // true——之前这行等于白写，父级任何一次 setState 都会连带把这个 pinned
  // header 重新 build 一遍。只有 isDark 会真的影响这里画出来的东西
  @override
  bool shouldRebuild(covariant _ProfileTabBarDelegate oldDelegate) =>
      oldDelegate.isDark != isDark;
}
