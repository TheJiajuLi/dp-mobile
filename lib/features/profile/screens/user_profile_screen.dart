import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/models/tutorial_model.dart';
import '../../../shared/utils/avatar_upload.dart';
import '../../../shared/utils/gender_label.dart';
import '../../../shared/widgets/zodiac_icon.dart';
import '../../auth/auth_service.dart';
import '../../messages/models/conversation_model.dart';
import '../../notebook/services/notebook_service.dart';
import '../models/user_profile_model.dart';

const _primary = Color(0xFF6366F1);

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
  String? _zodiac;
  List<String> _links = [];
  bool _loading = true;
  // 对方设置了"主页不公开"——GET /auth/users/profile/:id 会整体 403
  // 拒绝，不带任何资料数据。这种情况下退化成只显示头像/用户名/id 这几项
  // 基础信息，发布的内容/收藏这些直接隐藏，而不是一直转圈
  bool _profileBlocked = false;
  bool _startingChat = false;
  bool _uploadingAvatar = false;
  String? _coverImageUrl;
  bool _uploadingCover = false;

  int get _totalLikes => _tutorials.fold(0, (sum, t) => sum + t.likes);
  int get _totalViews => _tutorials.fold(0, (sum, t) => sum + t.views);

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _showNotebookTab ? 4 : 3, vsync: this);
    _loadProfile();
    if (_showNotebookTab) _loadNotebooks();
  }

  Future<void> _loadProfile() async {
    final api = ref.read(apiClientProvider);
    final currentUser = ref.read(currentUserProvider);
    final isOwnProfile = currentUser != null &&
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
      );
      await _loadLocalPrefs(profile);
      if (!widget.showBackButton) {
        ref.read(myFollowingCountProvider.notifier).state = profile.followingCount;
      }
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _profileBlocked = false;
        _loading = false;
      });
      await _loadTutorials(currentUser.id, currentUser.username);
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
        final profile = UserProfile.fromJson(basicRes.data as Map<String, dynamic>);
        // 关注状态接口不受隐私开关影响（实测私密资料照样 200），能拿就拿，
        // 让受限视图里的关注按钮显示真实状态
        final currentUserId = currentUser?.id;
        if (currentUserId != null && currentUserId != profile.id) {
          final followRes = await api.get('/auth/users/${profile.id}/follow-status');
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
        final reason = res.message ?? (mounted ? AppLocalizations.of(context)!.requestFailed : 'request failed');
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
          SnackBar(content: Text(l10n.uploadFailedWithReason(
            e.toString().replaceAll('Exception: ', ''),
          ))),
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        AppLocalizations.of(context)!.actionFailedWithReason('${res.message}'),
      )));
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          l10n.sendFailedWithReason('${msgRes.message}'),
        )));
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
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).cardColor,
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
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUploadAvatar(ImageSource source) async {
    setState(() => _uploadingAvatar = true);
    try {
      final newAvatar = await pickAndUploadAvatar(ref, source);
      if (newAvatar != null && _profile != null) {
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
          SnackBar(content: Text(l10n.uploadFailedWithReason(
            e.toString().replaceAll('Exception: ', ''),
          ))),
        );
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

  void _showSettingsSheet() {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.settings_outlined, color: Colors.grey),
              title: Text(l10n.allSettings),
              subtitle: Text(
                l10n.allSettingsSubtitle,
                style: const TextStyle(fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/settings');
              },
            ),
            ListTile(
              leading: const Icon(Icons.switch_account_outlined, color: Colors.grey),
              title: Text(l10n.switchAccount),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/switch-account');
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: Text(l10n.logout, style: const TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(ctx);
                await ref.read(authServiceProvider).logout();
                if (mounted) context.go('/login');
              },
            ),
          ],
        ),
      ),
    );
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
                  _profile!.isFollowing ? l10n.followingAction : l10n.followAction,
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
                  Icon(Icons.lock_outline, size: 40, color: Colors.grey.shade400),
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
                  const SizedBox(height: 4),
                  Text(
                    l10n.profileIsPrivateSubtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).textTheme.bodySmall?.color,
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
    final isMe = currentUser != null && currentUser.id == _profile?.id;
    final isSelfView = !widget.showBackButton;
    final sharedFollowingCount = ref.watch(myFollowingCountProvider);

    // 自己的主页：优先用 currentUserProvider（/auth/me 出的数据，编辑资料
    // 保存成功后会立刻更新，不用等这个页面重新拉一次接口）。
    // /auth/users/profile/:identifier 这个接口目前还没跟上 gender/
    // location/zodiac 这几个新字段（实测2026-07-04不返回），所以自己的
    // 主页不能靠它展示这几项，只能靠 currentUserProvider；查看别人主页时
    // 没有别的数据源，还是老老实实用 _profile
    final displayUsername = isSelfView
        ? (currentUser?.username ?? _profile?.username ?? '')
        : (_profile?.username ?? '');
    final displayBio = isSelfView ? (currentUser?.bio ?? _profile?.bio) : _profile?.bio;
    final displayGender = isSelfView ? (currentUser?.gender ?? _profile?.gender) : _profile?.gender;
    final displayLocation = isSelfView ? (currentUser?.location ?? _profile?.location) : _profile?.location;
    final displayZodiacName = isSelfView ? (currentUser?.zodiac ?? _zodiac) : _zodiac;
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

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                      // 封面+头像
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          GestureDetector(
                            onTap: isSelfView && !_uploadingCover
                                ? _pickAndUploadCover
                                : null,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                _coverImageUrl != null
                                    ? CachedNetworkImage(
                                        imageUrl: _coverImageUrl!,
                                        width: double.infinity,
                                        height: 160,
                                        fit: BoxFit.cover,
                                        errorWidget: (context, url, error) =>
                                            const _CoverGradient(),
                                      )
                                    : const _CoverGradient(),
                                if (_uploadingCover)
                                  Container(
                                    width: double.infinity,
                                    height: 160,
                                    color: Colors.black45,
                                    child: const CircularProgressIndicator(
                                      color: Colors.white,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (widget.showBackButton)
                            Positioned(
                              top: topPad + 8,
                              left: 8,
                              child: IconButton(
                                icon: const Icon(
                                  Icons.arrow_back_ios,
                                  color: Colors.white,
                                ),
                                onPressed: () => context.pop(),
                              ),
                            ),
                          if (isSelfView)
                            Positioned(
                              top: topPad + 12,
                              right: 12,
                              child: GestureDetector(
                                onTap: _showSettingsSheet,
                                child: Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(
                                      alpha: 0.3,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.menu,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            top: 120,
                            left: 16,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.fromBorderSide(
                                      BorderSide(color: Colors.white, width: 3),
                                    ),
                                  ),
                                  child: _buildAvatar(radius: 40),
                                ),
                                if (_uploadingAvatar)
                                  const CircleAvatar(
                                    radius: 40,
                                    backgroundColor: Colors.black45,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                    ),
                                  ),
                                if (isSelfView)
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: GestureDetector(
                                      onTap: _showAvatarOptions,
                                      child: Container(
                                        width: 24,
                                        height: 24,
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
                                          size: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          // 用户名紧跟在头像右侧，卡在头像露出白底那一半的
                          // 高度上——不要再让它单独飘在下面一段
                          Positioned(
                            top: 168,
                            left: 112,
                            right: 16,
                            child: Text(
                              displayUsername,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      // 头像/用户名已经在上面 Stack 里用 Positioned 精确摆好了，
                      // 这里只需要留够"操作按钮行"的高度别压到头像下沿就行——
                      // 按钮行本身是靠右对齐（Spacer 顶开），左边是空的，不会
                      // 跟左侧的头像/用户名打架，不需要留一大截空白
                      const SizedBox(height: 8),

                      // 操作按钮行
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            const Spacer(),
                            if (!isMe) ...[
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
                                    : const Icon(
                                        Icons.message_outlined,
                                        size: 16,
                                      ),
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
                                  _profile!.isFollowing ? l10n.followingAction : l10n.followAction,
                                ),
                              ),
                            ] else
                              OutlinedButton.icon(
                                onPressed: () async {
                                  await context.push('/edit-profile');
                                  if (mounted) _loadProfile();
                                },
                                icon: const Icon(Icons.edit, size: 16),
                                label: Text(l10n.editProfile),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Theme.of(context).textTheme.bodyLarge?.color,
                                  side: BorderSide(color: Colors.grey.shade300),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),

                      // 用户信息（用户名已经显示在头像右侧了，这里只放
                      // handle/星座/简介/链接）
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (_profile!.handle != null)
                                  Text(
                                    '@${_profile!.handle}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey,
                                    ),
                                  ),
                                if (displayZodiacSign != null) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEEF0FF),
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ZodiacIcon(sign: displayZodiacSign, size: 14),
                                        const SizedBox(width: 4),
                                        Text(
                                          zodiacDisplayName(l10n, displayZodiacSign),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF4F46E5),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (displayBio?.isNotEmpty == true) ...[
                              const SizedBox(height: 4),
                              Text(
                                displayBio!,
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.3,
                                ),
                              ),
                            ],
                            if ((displayGender?.isNotEmpty ?? false) ||
                                (displayLocation?.isNotEmpty ?? false)) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  if (displayGender?.isNotEmpty ?? false) ...[
                                    Icon(
                                      displayGender == '男'
                                          ? Icons.male
                                          : displayGender == '女'
                                          ? Icons.female
                                          : Icons.person_outline,
                                      size: 14,
                                      color: Theme.of(
                                        context,
                                      ).textTheme.bodySmall?.color,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      genderDisplayLabel(l10n, displayGender!),
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Theme.of(
                                          context,
                                        ).textTheme.bodySmall?.color,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                  ],
                                  if (displayLocation?.isNotEmpty ??
                                      false) ...[
                                    Icon(
                                      Icons.location_on_outlined,
                                      size: 14,
                                      color: Theme.of(
                                        context,
                                      ).textTheme.bodySmall?.color,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      displayLocation!,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Theme.of(
                                          context,
                                        ).textTheme.bodySmall?.color,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                            if (_links.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              ..._links.map(
                                (link) => Padding(
                                  padding: const EdgeInsets.only(top: 1),
                                  child: _linkRow(link, link),
                                ),
                              ),
                            ] else if (_profile!.website?.isNotEmpty ==
                                true) ...[
                              const SizedBox(height: 4),
                              _linkRow(
                                _profile!.website!
                                    .replaceAll('https://', '')
                                    .replaceAll('http://', ''),
                                _profile!.website!,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),

                      // 统计数据
                      Container(
                        color: Theme.of(context).cardColor,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            _statItem('${_profile!.tutorialCount}', l10n.tutorial),
                            _divider(),
                            _statItem(_formatCount(_totalLikes), l10n.likesCountLabel),
                            _divider(),
                            _statItem(
                              _formatCount(_profile!.followerCount),
                              l10n.followersCountLabel,
                              onTap: () => context.push(
                                '/users/${_profile!.id}/followers',
                              ),
                            ),
                            _divider(),
                            _statItem(
                              _formatCount(
                                isSelfView
                                    ? (sharedFollowingCount ??
                                        _profile!.followingCount)
                                    : _profile!.followingCount,
                              ),
                              l10n.followingCountLabel,
                              onTap: () => context.push(
                                '/users/${_profile!.id}/following',
                              ),
                            ),
                          ],
                        ),
                      ),

                      // 创作者中心（仅自己主页可见——目前只是入口占位，还
                      // 没有专门的数据统计页面，先在这展示能拿到的真实数据，
                      // 后端没有的指标（收藏/评论）就老实显示占位符，不编数字）
                      if (isSelfView) ...[
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: Theme.of(context).dividerColor,
                        ),
                        GestureDetector(
                          onTap: () =>
                              _todo(l10n.creatorCenterComingSoon),
                          child: Container(
                            color: Theme.of(context).cardColor,
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      l10n.creatorCenter,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(
                                          context,
                                        ).textTheme.bodyLarge?.color,
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    Icon(
                                      Icons.chevron_right,
                                      size: 18,
                                      color: Theme.of(
                                        context,
                                      ).textTheme.bodySmall?.color,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    _creatorStatItem(
                                      _formatCount(_totalViews),
                                      l10n.readCountLabel,
                                    ),
                                    _creatorStatItem('-', l10n.bookmarksCountLabel),
                                    _creatorStatItem('-', l10n.commentsCountLabel),
                                    Container(
                                      width: 36,
                                      height: 36,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: Theme.of(
                                          context,
                                        ).inputDecorationTheme.fillColor,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.notifications_none,
                                        size: 18,
                                        color: Theme.of(
                                          context,
                                        ).textTheme.bodySmall?.color,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],

                      // Tabs
                      // Material 的 TabBar 就算只放 icon 不放文字，也会按
                      // 默认单行高度（46）留白，图标只占 20，上下各空出一大截，
                      // 紧接着下面的九宫格就显得中间空了一条——用固定高度的
                      // SizedBox 把它按下去
                      Container(
                        color: Theme.of(context).cardColor,
                        child: SizedBox(
                          height: 32,
                          child: TabBar(
                            controller: _tabCtrl,
                            labelColor: _primary,
                            unselectedLabelColor: Colors.grey,
                            indicatorColor: _primary,
                            indicatorWeight: 2,
                            labelPadding: EdgeInsets.zero,
                            tabs: [
                              const Tab(icon: Icon(Icons.grid_view, size: 20)),
                              if (_showNotebookTab)
                                const Tab(
                                  icon: Icon(Icons.menu_book_outlined, size: 20),
                                ),
                              const Tab(
                                icon: Icon(Icons.bookmark_outline, size: 20),
                              ),
                              const Tab(
                                icon: Icon(Icons.favorite_outline, size: 20),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
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
                          key: const PageStorageKey('profile-tab-tutorials-empty'),
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
                  if (_showNotebookTab)
                    _notebooks.isEmpty
                        ? Center(
                            key: const PageStorageKey('profile-tab-notebooks-empty'),
                            child: Text(
                              l10n.noNotebooksYet,
                              style: const TextStyle(color: Colors.grey),
                            ),
                          )
                        : GridView.builder(
                            key: const PageStorageKey('profile-tab-notebooks'),
                            padding: EdgeInsets.zero,
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 2,
                                  mainAxisSpacing: 2,
                                  childAspectRatio: 1.0,
                                ),
                            itemCount: _notebooks.length,
                            itemBuilder: (ctx, i) {
                              final nb = _notebooks[i];
                              return _NotebookGridItem(
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
    );
  }

  Widget _statItem(String value, String label, {VoidCallback? onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider() =>
      Container(width: 0.5, height: 32, color: Colors.grey.shade200);

  Widget _creatorStatItem(String value, String label) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
        ],
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

// 没设置背景图时的默认渐变，也是加载失败时的兜底
class _CoverGradient extends StatelessWidget {
  const _CoverGradient();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF818CF8), Color(0xFF6366F1)],
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

// Notebook 九宫格 item
class _NotebookGridItem extends StatelessWidget {
  final Map<String, dynamic> notebook;
  final VoidCallback onTap;

  const _NotebookGridItem({required this.notebook, required this.onTap});

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

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            color: Colors.grey[100],
            child: const Center(
              child: Icon(
                Icons.description_outlined,
                size: 32,
                color: Colors.grey,
              ),
            ),
          ),
          Positioned(
            top: 6,
            left: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
          ),
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
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '$cellCount cells',
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
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
