import 'dart:convert';
import 'dart:ui';

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
import '../../../core/theme_provider.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/models/tutorial_model.dart';
import '../../../shared/utils/avatar_upload.dart';
import '../../../shared/widgets/zodiac_icon.dart';
import '../../auth/auth_service.dart';
import '../../column/models/column_model.dart';
import '../../messages/models/conversation_model.dart';
import '../../messages/providers/messages_provider.dart';
import '../../notebook/services/notebook_service.dart';
import '../../../shared/utils/topic_badge.dart';
import '../models/user_profile_model.dart';

const _primary = Color(0xFF6366F1);
// 网易云风格视觉语言（2026-07-05 重设计）：米白底 + 近黑正文 + 紫蓝只做
// 点缀，卡片用 0.5px 细线不用阴影。深色模式下这几个不跟着主题走的固定色
// 只在浅色场景使用，深色场景仍然读 Theme.of(context) 已有的那一套
const _ink = Color(0xFF1A1A1A);
const _muted = Color(0xFF999999);
const _hairline = Color(0xFFF0F0F0);
const _heroBg = Color(0xFFFAFAF8);

String _initial(String? name) {
  if (name == null || name.isEmpty) return '?';
  return name.substring(0, 1).toUpperCase();
}

const _coverPalette = [
  (bg: Color(0xFFEEF2FF), icon: Icons.bar_chart, fg: Color(0xFF6366F1)),
  (bg: Color(0xFFECFDF5), icon: Icons.functions, fg: Color(0xFF16A34A)),
  (bg: Color(0xFFFFF7ED), icon: Icons.psychology, fg: Color(0xFFD97706)),
  (bg: Color(0xFFFDF2F8), icon: Icons.code, fg: Color(0xFFDB2777)),
  (bg: Color(0xFFEFF6FF), icon: Icons.table_chart, fg: Color(0xFF2563EB)),
];

// 兴趣领域 badge 配色规则，跟 CONTEXT.md 里的规则表一一对应（现在跟首页
// Feed 卡片的话题角标共用同一份定义，见 shared/utils/topic_badge.dart，
// 不再各自维护一份）。后端 User 目前没有专门的"兴趣领域"字段，这里从
// 用户自己发布过的教程 tags 里统计出现频率最高的 3 个当作兴趣领域——
// 是真实数据的再加工，不是编出来的
(Color bg, Color fg) _badgeStyleFor(String tag) => topicBadgeStyleFor(tag);

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

  // 按出现频率取前 3 个 tag 当"兴趣领域"，同频的按 tag 本身排序，保证
  // 结果稳定（不会因为 Map 遍历顺序不确定而每次刷新显示不同的 3 个）
  List<String> _interestTags() {
    final freq = <String, int>{};
    for (final t in _tutorials) {
      for (final tag in t.tags) {
        freq[tag] = (freq[tag] ?? 0) + 1;
      }
    }
    final sorted = freq.keys.toList()
      ..sort((a, b) {
        final byFreq = freq[b]!.compareTo(freq[a]!);
        return byFreq != 0 ? byFreq : a.compareTo(b);
      });
    return sorted.take(3).toList();
  }

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
    // 文章/专栏/Notebook/收藏/点赞这行本身现在就是tab切换器（不再有单独的
    // TabBar），swipe切页也要让它跟着更新高亮态，不能只在点击时刷新
    _tabCtrl.addListener(() {
      if (mounted) setState(() {});
    });
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
      builder: (ctx) => Material(
        color: Theme.of(ctx).cardColor,
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
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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

  Future<void> _logout() async {
    await ref.read(authServiceProvider).logout();
    if (mounted) context.go('/login');
  }

  // ctx 是抽屉那个 showGeneralDialog 路由自己的 context——确认框先弹在
  // 抽屉上面，用户点"取消"的话抽屉还在，不受影响；点了"退出"才真的
  // 收起抽屉去登出，不是一点"退出登录"就直接登出
  Future<void> _confirmLogout(BuildContext ctx, AppLocalizations l10n) async {
    final confirm = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: Text(l10n.logout),
        content: Text(l10n.confirmLogoutMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(
              l10n.cancel,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(
              l10n.exit,
              style: const TextStyle(color: Color(0xFFDC2626)),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !ctx.mounted) return;
    Navigator.pop(ctx);
    await _logout();
  }

  // 对方主页设置了"不公开"：只展示头像/用户名/id 这几项基础信息（像
  // 网易云那样），发布的内容/收藏这些直接不显示——不复用下面那套带
  // Positioned 精确定位的头图布局，那套是为了让操作按钮/用户名跟正常
  // 资料页的九宫格对齐设计的，这里没有九宫格，简单摆一个居中布局即可
  Widget _buildBlockedProfile(AppLocalizations l10n, double topPad, bool isMe) {
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            const _CoverGradient(),
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

  Widget _buildAvatar({double radius = 40}) {
    final p = _profile;
    if (p?.avatar != null && p!.avatar!.isNotEmpty) {
      if (p.avatar!.startsWith('data:image')) {
        final base64Data = p.avatar!.split(',').last;
        try {
          return CircleAvatar(
            radius: radius,
            backgroundImage: MemoryImage(base64Decode(base64Data)),
          );
        } catch (_) {
          // 解码失败落到下面的首字母占位
        }
      } else {
        return CircleAvatar(
          radius: radius,
          backgroundImage: CachedNetworkImageProvider(p.avatar!),
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
            : NestedScrollView(
                headerSliverBuilder: (ctx, _) => [
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        // 头图区——封面/头像/用户名/星座/兴趣领域 badge/简介
                        // 全部糊在同一块背景上（小红书/网易云那种"内容嵌合
                        // 进背景图"效果）。文字统一用白色，不再跟着猜背景
                        // 图片的明暗去挑深色文字——真机验证过，用户自传的
                        // 照片亮度完全不可控，"猜文字颜色"这条路走不通；
                        // 改成网易云/小红书的正解：整块头图区铺一层由浅到
                        // 深的黑色蒙层，白色文字在蒙层之上永远有稳定对比度。
                        // 固定高度（屏幕50% - Tab栏42 - 底部导航83）而不是
                        // 让内容撑开——顶部按钮/底部信息都用 Positioned 绝对
                        // 定位叠在封面上，不管内容多高，封面区域比例保持稳定
                        SizedBox(
                          height:
                              (MediaQuery.sizeOf(context).height * 0.5 -
                                      42 -
                                      83)
                                  .clamp(280.0, 520.0),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned.fill(
                                child: GestureDetector(
                                  onTap: isSelfView && !_uploadingCover
                                      ? _pickAndUploadCover
                                      : null,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      _coverImageUrl != null
                                          ? CachedNetworkImage(
                                              imageUrl: _coverImageUrl!,
                                              fit: BoxFit.cover,
                                              errorWidget:
                                                  (context, url, error) =>
                                                      const _CoverGradient(),
                                            )
                                          : const _CoverGradient(),
                                      const DecoratedBox(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Color(0x00000000),
                                              Color(0x40000000),
                                              Color(0xB3000000),
                                            ],
                                            stops: [0.0, 0.32, 0.62],
                                          ),
                                        ),
                                      ),
                                      if (_uploadingCover)
                                        Container(
                                          color: Colors.black38,
                                          child: const Center(
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              // 顶部毛玻璃按钮行——绝对定位浮在封面上，不挤占
                              // 下面用户信息区的空间
                              Positioned(
                                top: topPad + 8,
                                left: 16,
                                right: 16,
                                child: Row(
                                  children: [
                                    if (widget.showBackButton)
                                      _heroIconButton(
                                        Icons.arrow_back_ios_new,
                                        () => context.pop(),
                                      )
                                    else if (isSelfView)
                                      _heroIconButton(
                                        Icons.menu,
                                        () => _openProfileDrawer(l10n),
                                      ),
                                    const Spacer(),
                                    // 自己主页时链接按钮挪到下面操作栏跟"分享"
                                    // 合并成"个人链接"了，这里只在看别人主页时
                                    // 才需要——查看对方的个人链接
                                    if (_allLinks().isNotEmpty && !isSelfView)
                                      _heroIconButton(
                                        Icons.link_rounded,
                                        () => _showLinksSheet(l10n),
                                      ),
                                  ],
                                ),
                              ),
                              // 用户信息区——绝对定位压在封面底部，不管上面头像/
                              // 简介/badge 具体多高，都贴着封面下沿对齐，跟顶部
                              // 按钮行留出的空间无关（这两块是各自独立定位的，
                              // 不是同一条 Column 从上往下自然排）
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 14,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // 头像 + 用户名/handle/星座
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Stack(
                                            clipBehavior: Clip.none,
                                            alignment: Alignment.center,
                                            children: [
                                              Container(
                                                decoration: const BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  border: Border.fromBorderSide(
                                                    BorderSide(
                                                      color: Colors.white,
                                                      width: 3,
                                                    ),
                                                  ),
                                                ),
                                                child: _buildAvatar(radius: 32),
                                              ),
                                              if (_uploadingAvatar)
                                                const CircleAvatar(
                                                  radius: 32,
                                                  backgroundColor:
                                                      Colors.black45,
                                                  child:
                                                      CircularProgressIndicator(
                                                        color: Colors.white,
                                                      ),
                                                ),
                                              if (isSelfView)
                                                Positioned(
                                                  // 视觉上的圆角标是 22x22，可点
                                                  // 区域放大到 36x36（居中对齐同一
                                                  // 个圆心），头像变小之后更要注意
                                                  // 别让触控热区跟着一起缩水
                                                  right: -6,
                                                  bottom: -6,
                                                  child: GestureDetector(
                                                    behavior:
                                                        HitTestBehavior.opaque,
                                                    onTap: _showAvatarOptions,
                                                    child: Container(
                                                      width: 36,
                                                      height: 36,
                                                      alignment:
                                                          Alignment.center,
                                                      child: Container(
                                                        width: 22,
                                                        height: 22,
                                                        decoration:
                                                            BoxDecoration(
                                                              color: _primary,
                                                              shape: BoxShape
                                                                  .circle,
                                                              border: Border.all(
                                                                color: Colors
                                                                    .white,
                                                                width: 2,
                                                              ),
                                                            ),
                                                        child: const Icon(
                                                          Icons.camera_alt,
                                                          color: Colors.white,
                                                          size: 11,
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
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  displayUsername,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.w800,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                const SizedBox(height: 3),
                                                if (_profile!.handle != null)
                                                  Text(
                                                    '@${_profile!.handle}',
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.white70,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // 兴趣领域 badge——从自己发布过的教程 tags 里
                                    // 统计出现频率最高的 3 个，不是编出来的字段
                                    if (interestTags.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          16,
                                          10,
                                          16,
                                          0,
                                        ),
                                        child: Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: interestTags.map((tag) {
                                            // 深色玻璃头图区不适合原来那套"浅底+
                                            // 饱和字"配色（专给白色卡片背景设计
                                            // 的）——同一份领域色，改成半透明彩色
                                            // 背景+浅色版文字+同色细描边，跟封面
                                            // 自然融合
                                            final domainColor = _badgeStyleFor(
                                              tag,
                                            ).$2;
                                            final lightColor =
                                                Color.lerp(
                                                  domainColor,
                                                  Colors.white,
                                                  0.4,
                                                ) ??
                                                domainColor;
                                            return Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 9,
                                                    vertical: 3,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: domainColor.withValues(
                                                  alpha: 0.3,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(99),
                                                border: Border.all(
                                                  color: domainColor.withValues(
                                                    alpha: 0.45,
                                                  ),
                                                  width: 0.5,
                                                ),
                                              ),
                                              child: Text(
                                                tag,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w500,
                                                  color: lightColor,
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                    const SizedBox(height: 16),
                                    // 简介区：bio + 性别/所在地/星座 + IP属地 +
                                    // 个人链接——星座从上面用户名那一行挪到这里，
                                    // 跟性别/所在地放一起；统一用白色文字，不再
                                    // 跟着猜背景图片的明暗去挑深色，靠上面那层
                                    // 黑色蒙层保证对比度
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        0,
                                        16,
                                        0,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (displayBio?.isNotEmpty == true)
                                            Text(
                                              displayBio!,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.white,
                                                height: 1.4,
                                              ),
                                            ),
                                          // 空间经济化——位置+星座+网站压成一行，
                                          // 单独占一行的性别图标、以及自成一行的
                                          // IP属地都拿掉了：跟这一行比起来是次要
                                          // 信息，不值得再多占一整行的垂直空间
                                          if ((displayLocation?.isNotEmpty ??
                                                  false) ||
                                              displayZodiacSign != null ||
                                              _allLinks().isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 4,
                                              ),
                                              child: Row(
                                                children: [
                                                  if (displayLocation
                                                          ?.isNotEmpty ??
                                                      false) ...[
                                                    const Icon(
                                                      Icons
                                                          .location_on_outlined,
                                                      size: 12,
                                                      color: Colors.white70,
                                                    ),
                                                    const SizedBox(width: 3),
                                                    Text(
                                                      displayLocation!,
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                        color: Colors.white70,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 10),
                                                  ],
                                                  if (displayZodiacSign !=
                                                      null) ...[
                                                    ZodiacIcon(
                                                      sign: displayZodiacSign,
                                                      size: 12,
                                                    ),
                                                    const SizedBox(width: 3),
                                                    Text(
                                                      zodiacDisplayName(
                                                        l10n,
                                                        displayZodiacSign,
                                                      ),
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                        color: Colors.white70,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 10),
                                                  ],
                                                  if (_allLinks()
                                                      .isNotEmpty) ...[
                                                    const Icon(
                                                      Icons.language,
                                                      size: 12,
                                                      color: Colors.white70,
                                                    ),
                                                    const SizedBox(width: 3),
                                                    Flexible(
                                                      child: GestureDetector(
                                                        onTap: () => _openLink(
                                                          _allLinks().first,
                                                        ),
                                                        child: Text(
                                                          _allLinks().first
                                                              .replaceAll(
                                                                'https://',
                                                                '',
                                                              )
                                                              .replaceAll(
                                                                'http://',
                                                                '',
                                                              ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 11,
                                                                color: Colors
                                                                    .white70,
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    // 统计+按钮一行——统计数字改成内联文字排列
                                    // （之前那版把统计做成卡片、还兼当tab切换器，
                                    // 这次拆开：切换tab交给下面单独的白底TabBar，
                                    // 这里只做静态展示，社交数据也换回原本的
                                    // 文章/获赞/粉丝/关注，不再是内容分类计数）
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: SingleChildScrollView(
                                              scrollDirection: Axis.horizontal,
                                              child: Row(
                                                children: [
                                                  _inlineStat(
                                                    '${_profile!.tutorialCount}',
                                                    l10n.articlesCountLabel,
                                                  ),
                                                  _inlineStat(
                                                    _formatCount(_totalLikes),
                                                    l10n.likesCountLabel,
                                                  ),
                                                  _inlineStat(
                                                    _formatCount(
                                                      _profile!.followerCount,
                                                    ),
                                                    l10n.followersCountLabel,
                                                    onTap: () => context.push(
                                                      '/users/${_profile!.id}/followers',
                                                    ),
                                                  ),
                                                  _inlineStat(
                                                    _formatCount(
                                                      _profile!.followingCount,
                                                    ),
                                                    l10n.followingCountLabel,
                                                    onTap: () => context.push(
                                                      '/users/${_profile!.id}/following',
                                                    ),
                                                    last: true,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          if (isMe) ...[
                                            SizedBox(
                                              height: 32,
                                              child: ElevatedButton(
                                                onPressed: () async {
                                                  await context.push(
                                                    '/edit-profile',
                                                  );
                                                  if (mounted) _loadProfile();
                                                },
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.white,
                                                  foregroundColor: _ink,
                                                  elevation: 0,
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 14,
                                                      ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                  ),
                                                ),
                                                child: Text(
                                                  l10n.editProfile,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            _heroIconButton(
                                              Icons.link_rounded,
                                              () => _showLinksSheet(l10n),
                                            ),
                                          ] else ...[
                                            SizedBox(
                                              height: 32,
                                              child: OutlinedButton.icon(
                                                onPressed: _startingChat
                                                    ? null
                                                    : _startChat,
                                                icon: _startingChat
                                                    ? const SizedBox(
                                                        width: 12,
                                                        height: 12,
                                                        child:
                                                            CircularProgressIndicator(
                                                              strokeWidth: 2,
                                                              color:
                                                                  Colors.white,
                                                            ),
                                                      )
                                                    : const Icon(
                                                        Icons.message_outlined,
                                                        size: 14,
                                                      ),
                                                label: Text(
                                                  l10n.sendMessageAction,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor: Colors.white,
                                                  side: const BorderSide(
                                                    color: Colors.white70,
                                                  ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                      ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            SizedBox(
                                              height: 32,
                                              child: ElevatedButton(
                                                onPressed: _toggleFollow,
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      _profile!.isFollowing
                                                      ? Colors.white
                                                      : _primary,
                                                  foregroundColor:
                                                      _profile!.isFollowing
                                                      ? _ink
                                                      : Colors.white,
                                                  elevation: 0,
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                      ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                  ),
                                                ),
                                                child: Text(
                                                  _profile!.isFollowing
                                                      ? l10n.followingAction
                                                      : l10n.followAction,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Tab 栏——42px 白底，跟头图区分开，选中态黑字+黑色下划线；
                  // 加了 SliverPersistentHeader(pinned:true) 让它在往下滚动
                  // 内容时贴在头图底下不消失，教程九宫格/Notebook列表比头图
                  // 长很多时，切 tab 不用先滚回顶部
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _ProfileTabBarDelegate(
                      TabBar(
                        controller: _tabCtrl,
                        labelColor: _ink,
                        unselectedLabelColor: const Color(0xFFBBBBBB),
                        // 5个tab（含Notebook这个英文单词）挤在一行，字号
                        // 跟padding都要比4个tab时更紧凑，不然"Notebook"
                        // 这种比中文标签长的单词会被裁掉显示不全
                        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                        labelStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                        unselectedLabelStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                        indicatorColor: _ink,
                        indicatorSize: TabBarIndicatorSize.label,
                        indicatorWeight: 2,
                        dividerColor: Colors.transparent,
                        tabs: [
                          Tab(text: l10n.articlesCountLabel),
                          Tab(text: l10n.tabColumnsLabel),
                          if (_showNotebookTab) const Tab(text: 'Notebook'),
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
                    // 发布的教程九宫格
                    // GridView 在没显式传 padding 时，会自动用
                    // MediaQuery.of(context).padding（状态栏/刘海/底部安全区）
                    // 当作自己的 SliverPadding——这是 Flutter 专门给"作为整个
                    // 页面根滚动视图"的 ListView/GridView 设计的默认行为，
                    // 用来避免内容被状态栏挡住。但这里的 GridView 只是嵌套在
                    // NestedScrollView+TabBarView 里的一个子滚动视图，
                    // 顶部已经有头图+Tab栏挡着，不需要再避让一次安全区，
                    // 这个"自动"padding 才是 Tab 栏和九宫格之间那截空白的
                    // 真正来源——显式传 EdgeInsets.zero 关掉这个默认行为。
                    // （给每个 tab 一个独立 PageStorageKey 是上一版修复时顺手
                    // 加的，用来避免几个结构相同的 tab 之间滚动位置互相串，
                    // 跟这次的空白无关，但仍然值得保留）
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
                        : GridView.builder(
                            key: const PageStorageKey('profile-tab-tutorials'),
                            padding: EdgeInsets.zero,
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 2,
                                  mainAxisSpacing: 2,
                                  childAspectRatio: 1.0,
                                ),
                            itemCount: _tutorials.length,
                            itemBuilder: (ctx, i) {
                              final t = _tutorials[i];
                              return _TutorialGridItem(
                                tutorial: t,
                                onTap: () => context.push('/tutorial/${t.id}'),
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
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1, color: _hairline),
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
    );
  }

  // 统计数字内联文字排列——文章/获赞/粉丝/关注挨个写在一行，last:true
  // 的最后一项右边不再留间距
  Widget _inlineStat(
    String value,
    String label, {
    VoidCallback? onTap,
    bool last = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.only(right: last ? 0 : 14),
        child: RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              TextSpan(
                text: ' $label',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white.withValues(alpha: 0.45),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
                border: Border.all(color: const Color(0xFFD1D1D6), width: 1.5),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.add_circle_outline,
                    color: Color(0xFFC7C7CC),
                    size: 28,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.createColumnAction,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFFC7C7CC),
                    ),
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

  // 头图区里叠在背景上的圆形按钮（返回/汉堡）——半透明白底保证无论背景
  // 是浅色渐变占位还是用户传的任意亮度照片，深色图标都能看清
  // filled:false 给不需要白底圆圈衬托的场景用（比如链接图标）——直接裸
  // 图标压在头图蒙层上，跟返回/汉堡按钮的白底圆圈是两种不同的视觉分量
  // 毛玻璃圆角按钮——iOS 原生 BackdropFilter 效果，压在头图上不管背景
  // 亮暗都有稳定的可读性，不用像之前那样靠纯白底色硬保证对比度
  Widget _heroIconButton(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
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

  // 网易云音乐"我的"页那套——从左侧滑入的抽屉，不是铺在主页面里的常驻
  // 列表。头部复用主页面已经算好的这几个数字，不在这里重新读一遍 provider
  // Scaffold.drawer 只能盖住它自己那个 Scaffold 的范围——UserProfileScreen
  // 这个 Scaffold 是嵌在 MainShell 的 body 里的，MainShell 自己另有一个
  // Scaffold 管着底部导航栏，drawer 天然盖不到底部导航栏那块，也逃不出
  // 顶部状态栏那圈 SafeArea。改用 showGeneralDialog 强制推到根 Navigator
  // 上（默认 useRootNavigator: true），叠在包括底部导航栏在内的整个 App
  // 上面，才能做到真正贴边全高
  void _openProfileDrawer(AppLocalizations l10n) {
    showGeneralDialog(
      context: context,
      barrierLabel: '',
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (ctx, _, __) => Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 290,
          height: double.infinity,
          child: _buildProfileDrawer(ctx, l10n),
        ),
      ),
      transitionBuilder: (ctx, animation, _, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(-1, 0), end: Offset.zero)
            .animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
        child: child,
      ),
    );
  }

  Widget _buildProfileDrawer(BuildContext ctx, AppLocalizations l10n) {
    // 头部用户信息按要求直接读 currentUserProvider（/auth/me 的实时数据），
    // 不是从主页面已经算好的 displayUsername 传下来的——这样别处改了头像/
    // 资料后，抽屉这边不用等 _profile 重新加载就能跟着更新
    final currentUser = ref.watch(currentUserProvider);
    final username = currentUser?.username ?? '';
    final safePadding = MediaQuery.of(ctx).padding;

    return Material(
      color: Theme.of(ctx).scaffoldBackgroundColor,
      child: Column(
        children: [
          // 头像+用户名精简成网易云那样的单行，教程/获赞/粉丝/关注这些
          // 主页面本来就有，不用在这再摆一遍占空间——腾出来的高度让功能
          // 列表少滚动几下。点这一行直接收起抽屉，回去看下面那份主页面。
          // 渐变换成跟主页头图区同一套深色玻璃拟态配色（#2A1F3D→
          // #1A2A3D），不再是原来那个偏亮的靛紫——两处都是这个app的
          // "头部视觉"，颜色不统一会像是两个不同页面拼起来的
          GestureDetector(
            onTap: () => Navigator.pop(ctx),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(20, safePadding.top + 16, 16, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF2A1F3D), Color(0xFF1A2A3D)],
                ),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // 右上角一小团柔光——纯用渐变+模糊做的装饰，不需要额外
                  // 素材，呼应参考图里那颗发光星球，但克制成一个抽象光斑
                  Positioned(
                    right: -20,
                    top: -30,
                    child: Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            _primary.withValues(alpha: 0.35),
                            _primary.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      _buildAvatar(radius: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        color: Colors.white70,
                        size: 20,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // 会员卡——升级跳去已经真实存在的订阅页（/settings/subscription），
          // 不是纯装饰；极梦 Pro 这个具体权益文案目前只是占位说法，后端
          // 还没有真正的会员等级/权益体系
          GestureDetector(
            onTap: () {
              Navigator.pop(ctx);
              context.push('/settings/subscription');
            },
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF18122B),
                borderRadius: BorderRadius.circular(12),
                // 细描边加一点紫色光晕，跟上面头部/主页头图区那套深色
                // 玻璃拟态呼应一下，不然纯深色块跟上面的渐变头部脱节
                border: Border.all(
                  color: _primary.withValues(alpha: 0.25),
                  width: 0.5,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD97706),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.workspace_premium,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.proMembershipMenuLabel,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD97706),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      l10n.upgradeAction,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // 我的消息/我的Notebook/深色模式是真数据/真入口；
                // 我的收藏/浏览历史/草稿箱后端和专门页面都还没有，先用
                // 统一的"即将上线"占位，不编造数字
                _profileMenuItem(
                  icon: Icons.mail_outline,
                  label: l10n.myMessages,
                  badgeCount: ref.watch(unreadCountProvider),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.go('/messages');
                  },
                ),
                _profileMenuItem(
                  icon: Icons.bookmark_outline,
                  label: l10n.myFavorites,
                  onTap: () {
                    Navigator.pop(ctx);
                    _todo(l10n.comingSoonStayTuned);
                  },
                ),
                _profileMenuItem(
                  icon: Icons.history,
                  label: l10n.browsingHistory,
                  onTap: () {
                    Navigator.pop(ctx);
                    _todo(l10n.comingSoonStayTuned);
                  },
                ),
                _profileMenuItem(
                  icon: Icons.menu_book_outlined,
                  label: l10n.myNotebookMenuLabel,
                  trailingText: _notebooks.isNotEmpty
                      ? '${_notebooks.length}'
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    context.push('/notebook');
                  },
                ),
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: 52,
                  color: Theme.of(ctx).dividerColor,
                ),
                _profileMenuItem(
                  icon: Icons.article_outlined,
                  label: l10n.creatorCenter,
                  trailingText: _totalViews > 0
                      ? l10n.readCountWithValue(_formatCount(_totalViews))
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    _todo(l10n.creatorCenterComingSoon);
                  },
                ),
                _profileMenuItem(
                  icon: Icons.drafts_outlined,
                  label: l10n.draftBox,
                  onTap: () {
                    Navigator.pop(ctx);
                    _todo(l10n.comingSoonStayTuned);
                  },
                ),
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: 52,
                  color: Theme.of(ctx).dividerColor,
                ),
                _profileMenuItem(
                  icon: Icons.dark_mode_outlined,
                  label: l10n.darkModeMenuLabel,
                  trailingText: _themeLabel(l10n, ref.watch(themeProvider)),
                  // 直接在侧栏里选，不用跳全部设置——全部设置里原来那个
                  // "主题"入口已经拿掉了，深色模式现在只在这一个地方改
                  onTap: () => _showThemePicker(ctx, l10n),
                ),
              ],
            ),
          ),
          Container(
            color: Theme.of(ctx).cardColor,
            padding: EdgeInsets.fromLTRB(0, 14, 0, 14 + safePadding.bottom),
            child: Row(
              children: [
                _bottomActionButton(
                  icon: Icons.settings_outlined,
                  label: l10n.allSettings,
                  onTap: () {
                    Navigator.pop(ctx);
                    context.push('/settings');
                  },
                ),
                _bottomActionButton(
                  icon: Icons.swap_horizontal_circle_outlined,
                  label: l10n.switchAccount,
                  onTap: () {
                    Navigator.pop(ctx);
                    context.push('/switch-account');
                  },
                ),
                _bottomActionButton(
                  icon: Icons.logout,
                  label: l10n.logout,
                  color: const Color(0xFFDC2626),
                  onTap: () => _confirmLogout(ctx, l10n),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileMenuItem({
    required IconData icon,
    required String label,
    String? trailingText,
    int badgeCount = 0,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: Theme.of(context).cardColor,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
            ),
            if (badgeCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  badgeCount > 99 ? '99+' : '$badgeCount',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else if (trailingText != null) ...[
              Text(
                trailingText,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
              const SizedBox(width: 4),
            ],
            const SizedBox(width: 2),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomActionButton({
    required IconData icon,
    required String label,
    Color? color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: 44,
          child: Center(
            child: Tooltip(
              message: label,
              child: Icon(
                icon,
                size: 22,
                color: color ?? Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _themeLabel(AppLocalizations l10n, ThemePreference pref) =>
      switch (pref) {
        ThemePreference.system => l10n.themeSystem,
        ThemePreference.light => l10n.themeLight,
        ThemePreference.dark => l10n.themeDark,
      };

  // 深色模式直接在侧栏里选——不再跳全部设置那边（那边的"主题"入口已经
  // 拿掉了）。ctx 是抽屉那个 showGeneralDialog 路由自己的 context，这里
  // 弹出的底部弹层挂在同一个根 Navigator 上，跟抽屉叠在一起
  void _showThemePicker(BuildContext ctx, AppLocalizations l10n) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(sheetCtx).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
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
            Text(
              l10n.theme,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Theme.of(sheetCtx).textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 16),
            Consumer(
              builder: (consumerCtx, ref, _) {
                final current = ref.watch(themeProvider);
                return Column(
                  children: ThemePreference.values
                      .map(
                        (pref) => ListTile(
                          title: Text(_themeLabel(l10n, pref)),
                          trailing: current == pref
                              ? const Icon(Icons.check, color: _primary)
                              : null,
                          onTap: () {
                            ref.read(themeProvider.notifier).setTheme(pref);
                            Navigator.pop(sheetCtx);
                          },
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
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
class _CoverGradient extends StatelessWidget {
  const _CoverGradient();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A1F3D), Color(0xFF1A2A3D)],
        ),
      ),
    );
  }
}

// 教程九宫格 item
class _TutorialGridItem extends StatelessWidget {
  final TutorialModel tutorial;
  final VoidCallback onTap;

  const _TutorialGridItem({required this.tutorial, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final entry =
        _coverPalette[tutorial.title.isNotEmpty
            ? tutorial.title.codeUnitAt(0) % _coverPalette.length
            : 0];

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          tutorial.coverImage?.isNotEmpty == true
              ? CachedNetworkImage(
                  imageUrl: tutorial.coverImage!,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(color: entry.bg),
                  errorWidget: (context, url, error) => Container(
                    color: entry.bg,
                    child: Icon(entry.icon, size: 32, color: entry.fg),
                  ),
                )
              : Container(
                  color: entry.bg,
                  child: Icon(entry.icon, size: 32, color: entry.fg),
                ),

          // 底部渐变信息
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tutorial.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(
                        Icons.favorite,
                        size: 10,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${tutorial.likes}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.visibility,
                        size: 10,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${tutorial.views}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
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
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _ink,
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
    final ci = column.name.isNotEmpty
        ? column.name.codeUnitAt(0) % _gradients.length
        : 0;
    final gradient = _gradients[ci];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E5EA), width: 0.5),
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
                    column.coverImage != null && column.coverImage!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: column.coverImage!,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) =>
                                _gradBg(gradient),
                          )
                        : _gradBg(gradient),
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
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF8E8E93),
                        height: 1.5,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _stat(
                        Icons.remove_red_eye_outlined,
                        '${column.viewCount}',
                      ),
                      const SizedBox(width: 12),
                      _stat(Icons.favorite_outline, '${column.likeCount}'),
                      const SizedBox(width: 12),
                      _stat(Icons.bookmark_outline, '${column.saveCount}'),
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

  Widget _stat(IconData icon, String val) => Row(
    children: [
      Icon(icon, size: 13, color: Colors.grey),
      const SizedBox(width: 3),
      Text(val, style: const TextStyle(fontSize: 11, color: Colors.grey)),
    ],
  );
}

// 42px 白底 TabBar 包成 SliverPersistentHeader 需要的 delegate——
// minExtent/maxExtent 都固定成 42，不用随内容变化
class _ProfileTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  const _ProfileTabBarDelegate(this.tabBar);

  @override
  double get minExtent => 42;
  @override
  double get maxExtent => 42;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: Colors.white, child: tabBar);
  }

  @override
  bool shouldRebuild(covariant _ProfileTabBarDelegate oldDelegate) =>
      oldDelegate.tabBar != tabBar;
}
