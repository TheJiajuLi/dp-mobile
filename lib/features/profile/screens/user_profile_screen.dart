import 'dart:async';
import 'dart:convert';

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
import '../../../core/profile_refresh_signal.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme_provider.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/models/tutorial_model.dart';
import '../../../shared/utils/pro_access.dart';
import '../../../shared/utils/avatar_upload.dart';
import '../../../shared/widgets/zodiac_icon.dart';
import '../../auth/auth_service.dart';
import '../../column/models/column_model.dart';
import '../../messages/models/conversation_model.dart';
import '../../notebook/services/notebook_service.dart';
import '../models/user_profile_model.dart';
import '../widgets/profile_avatar_sheets.dart';
import '../widgets/profile_blocked_widget.dart';
import '../widgets/profile_header_widget.dart';
import '../widgets/profile_painters.dart';
import '../widgets/profile_tabs_widget.dart';
import '../../../shared/widgets/article_flow_item.dart';

const _primary = Color(0xFF6366F1);
// 网易云风格视觉语言（2026-07-05 重设计）：米白底 + 近黑正文 + 紫蓝只做
// 点缀，卡片用 0.5px 细线不用阴影。深色模式下这几个不跟着主题走的固定色
// 只在浅色场景使用，深色场景仍然读 Theme.of(context) 已有的那一套
const _ink = Color(0xFF1A1A1A);
// 浅色背景统一成首页那种偏米白的 #FAFAF8——首页实际用的就是 #FAFAF8，
// 之前误以为是 AppColors.bg(#F7F7FB) 冷灰白，跟首页并不一致，看着偏冷。
// 改回 #FAFAF8 跟首页真正对齐，更舒服
const _heroBg = Color(0xFFFAFAF8);

String _initial(String? name) {
  if (name == null || name.isEmpty) return '?';
  return name.substring(0, 1).toUpperCase();
}

// 个人主页下半部（tab内容区）深色主题下的背景色——直接复用 app_theme.dart
// 深色 ThemeData 的 scaffoldBackgroundColor（AppColors.darkBg，#0A0A0F），跟
// 全局深色背景一致，不然这个页面看着像另外拼上去的、不像同一个 app。之前
// 硬编码成 #1C1C1E，比真正的 scaffold 背景浅一截，整块发灰、跟底部栏/其它
// 页面不统一
const _profileDarkBg = AppColors.darkBg;

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
  // Tab 数量提示（"N 篇文章"）不再常驻——点击/切换 Tab 时闪现一下再收起，
  // 不长期占位
  bool _showTabCount = false;
  int _lastTabIndex = 0;
  Timer? _countTimer;
  UserProfile? _profile;
  List<TutorialModel> _tutorials = [];
  List<Map<String, dynamic>> _notebooks = [];
  List<ColumnModel> _columns = [];
  List<TutorialModel> _saves = [];
  // 对方把收藏设置成不公开——GET /auth/users/:userId/saves 会 403，跟
  // _profileBlocked 那套主页整体 403 是两回事：这里主页其它信息都拿得到，
  // 只是收藏这一项单独被挡
  bool _savesPrivate = false;
  List<TutorialModel> _likes = [];
  // 收藏/点赞两个 tab 各自独立分页——后端 querySaves/getUserLiked 每页
  // 20 条，翻到最后一页返回条数 < 20 就当没有更多了，不依赖一个专门的
  // "总页数"字段（接口只给 total 总条数）
  int _savesPage = 1;
  bool _savesHasMore = true;
  bool _savesLoadingMore = false;
  final _savesScrollCtrl = ScrollController();
  int _likesPage = 1;
  bool _likesHasMore = true;
  bool _likesLoadingMore = false;
  final _likesScrollCtrl = ScrollController();
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
    _tabCtrl.addListener(_onTabChanged);
    // 进入页面时先把当前 Tab 的数量闪一下
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _flashTabCount();
    });
    _loadProfile();
    if (_showNotebookTab) _loadNotebooks();
    _savesScrollCtrl.addListener(() {
      if (_savesScrollCtrl.position.pixels >=
              _savesScrollCtrl.position.maxScrollExtent - 200 &&
          _savesHasMore &&
          !_savesLoadingMore) {
        _loadMoreSaves();
      }
    });
    _likesScrollCtrl.addListener(() {
      if (_likesScrollCtrl.position.pixels >=
              _likesScrollCtrl.position.maxScrollExtent - 200 &&
          _likesHasMore &&
          !_likesLoadingMore) {
        _loadMoreLikes();
      }
    });
  }

  void _onTabChanged() {
    if (_tabCtrl.index != _lastTabIndex) {
      _lastTabIndex = _tabCtrl.index;
      _flashTabCount();
    }
  }

  // 数量提示闪现约 1.6 秒后自动收起
  void _flashTabCount() {
    _countTimer?.cancel();
    if (!_showTabCount) setState(() => _showTabCount = true);
    _countTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _showTabCount = false);
    });
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

  // 自己走 /auth/me/saves，别人走 /auth/users/:userId/saves——后者受对方
  // 隐私设置控制，403 不当错误处理，是"对方收藏是私密的"这个正常状态。
  // 记住 userId/isSelf，翻页时 _loadMoreSaves 要用同一套参数继续请求
  String? _savesUserId;
  bool _savesIsSelf = false;

  Future<void> _loadSaves(String userId, bool isSelf) async {
    _savesUserId = userId;
    _savesIsSelf = isSelf;
    final api = ref.read(apiClientProvider);
    final res = await api.get(
      isSelf ? '/auth/me/saves' : '/auth/users/$userId/saves',
      queryParameters: {'page': 1},
    );
    if (!mounted) return;
    if (res.success && res.data != null) {
      final list = ((res.data as Map)['saves'] as List?) ?? [];
      setState(() {
        _saves = list
            .map(
              (j) =>
                  TutorialModel.fromJson(Map<String, dynamic>.from(j as Map)),
            )
            .toList();
        _savesPrivate = false;
        _savesPage = 1;
        // 后端每页固定 20 条，不够一页说明已经是最后一页——接口没给
        // "总页数"，只给了总条数，用这个当没有更多的判断依据
        _savesHasMore = list.length >= 20;
      });
    } else if (res.statusCode == 403) {
      setState(() {
        _saves = [];
        _savesPrivate = true;
        _savesHasMore = false;
      });
    }
  }

  Future<void> _loadMoreSaves() async {
    if (_savesUserId == null || _savesPrivate) return;
    setState(() => _savesLoadingMore = true);
    final nextPage = _savesPage + 1;
    final res = await ref
        .read(apiClientProvider)
        .get(
          _savesIsSelf ? '/auth/me/saves' : '/auth/users/$_savesUserId/saves',
          queryParameters: {'page': nextPage},
        );
    if (!mounted) return;
    if (res.success && res.data != null) {
      final list = ((res.data as Map)['saves'] as List?) ?? [];
      setState(() {
        _saves.addAll(
          list.map(
            (j) => TutorialModel.fromJson(Map<String, dynamic>.from(j as Map)),
          ),
        );
        _savesPage = nextPage;
        _savesHasMore = list.length >= 20;
        _savesLoadingMore = false;
      });
    } else {
      setState(() => _savesLoadingMore = false);
    }
  }

  // 点赞列表没有隐私开关，自己/别人都是同一个接口
  String? _likesUserId;

  Future<void> _loadLikes(String userId) async {
    _likesUserId = userId;
    final res = await ref
        .read(apiClientProvider)
        .get('/auth/users/$userId/liked', queryParameters: {'page': 1});
    if (!mounted) return;
    if (res.success && res.data != null) {
      final list = ((res.data as Map)['tutorials'] as List?) ?? [];
      setState(() {
        _likes = list
            .map(
              (j) =>
                  TutorialModel.fromJson(Map<String, dynamic>.from(j as Map)),
            )
            .toList();
        _likesPage = 1;
        _likesHasMore = list.length >= 20;
      });
    }
  }

  Future<void> _loadMoreLikes() async {
    if (_likesUserId == null) return;
    setState(() => _likesLoadingMore = true);
    final nextPage = _likesPage + 1;
    final res = await ref
        .read(apiClientProvider)
        .get(
          '/auth/users/$_likesUserId/liked',
          queryParameters: {'page': nextPage},
        );
    if (!mounted) return;
    if (res.success && res.data != null) {
      final list = ((res.data as Map)['tutorials'] as List?) ?? [];
      setState(() {
        _likes.addAll(
          list.map(
            (j) => TutorialModel.fromJson(Map<String, dynamic>.from(j as Map)),
          ),
        );
        _likesPage = nextPage;
        _likesHasMore = list.length >= 20;
        _likesLoadingMore = false;
      });
    } else {
      setState(() => _likesLoadingMore = false);
    }
  }

  Future<void> _deleteColumn(String columnId) async {
    final res = await ref
        .read(apiClientProvider)
        .delete('/auth/columns/$columnId');
    if (!mounted) return;
    if (res.success) {
      setState(() {
        _columns.removeWhere((c) => c.id == columnId);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('专栏已删除')));
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(res.message ?? '删除失败')));
    }
  }

  // 下拉刷新统一入口——_loadProfile 内部已经会连带重新拉教程/专栏/收藏/
  // 点赞（见下面 isOwnProfile/别人主页两条分支末尾），这里不用再重复调用
  Future<void> _onRefresh() async {
    await Future.wait([_loadProfile(), if (_showNotebookTab) _loadNotebooks()]);
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
        coverImage: currentUser.coverImage,
        gender: currentUser.gender,
        location: currentUser.location,
        zodiac: currentUser.zodiac,
        followerCount: currentUser.followerCount,
        followingCount: currentUser.followingCount,
        tutorialCount: 0,
        createdAt: (currentUser.createdAt ?? 0) * 1000,
        ipLocation: currentUser.ipLocation,
        tags: currentUser.tags,
        isFoundingCreator: currentUser.isFoundingCreator,
        isAuroraCreator: currentUser.isAuroraCreator,
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
      await _loadSaves(currentUser.id, true);
      await _loadLikes(currentUser.id);
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
    await _loadSaves(profile.id, false);
    await _loadLikes(profile.id);
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

  // 封面图 2026-07-13 起落到服务端（users.cover_image）。这里优先用
  // profile.coverImage，兼容旧数据回退到本地 legacy key；如果服务端还没有、
  // 本地却有（老用户之前只存了本地），且是自己的主页，就顺手迁移上去一次。
  //
  // 个人链接仍只存本地（后端没有对应字段）。星座优先用后端 profile.zodiac。
  Future<void> _loadLocalPrefs(UserProfile profile) async {
    final userId = profile.id;
    final prefs = await SharedPreferences.getInstance();
    final zodiac = profile.zodiac ?? prefs.getString('${userId}_zodiac');
    final linksJson = prefs.getString('${userId}_links') ?? '[]';
    final localCover = prefs.getString('${userId}_cover_image');
    final coverImageUrl = profile.coverImage ?? localCover;
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

    // 迁移：服务端还没存、本地有旧封面、且是自己 → 补传一次到服务端
    final currentUser = ref.read(currentUserProvider);
    final isSelf = currentUser != null && currentUser.id == userId;
    if (isSelf &&
        (profile.coverImage == null || profile.coverImage!.isEmpty) &&
        localCover != null &&
        localCover.isNotEmpty) {
      await _persistCover(localCover);
    }
  }

  // 把封面URL落到服务端 PATCH /auth/me/cover——后端会顺带清掉被替换的旧
  // COS文件。失败静默（本地已有值，不打断用户）
  Future<void> _persistCover(String url) async {
    final res = await ref
        .read(apiClientProvider)
        .patch('/auth/me/cover', data: {'cover_image': url});
    if (res.success) {
      // 同步更新 currentUserProvider 里的 coverImage，避免下次进主页又触发迁移
      final cu = ref.read(currentUserProvider);
      if (cu != null) {
        ref.read(currentUserProvider.notifier).state = cu.copyWith(
          coverImage: url,
        );
      }
    }
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
        // 落到服务端（PATCH /auth/me/cover），后端会顺带清掉被替换的旧COS文件
        await _persistCover(url);
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
      // 深色模式下别用突兀的实心紫，跟着主题走：深色用深表面色+浅紫图标，
      // 浅色仍保留品牌紫底白字
      final isDark = Theme.of(context).brightness == Brightness.dark;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                Icons.info_outline,
                color: isDark ? _primary : Colors.white,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.followedWaitingForFollowBack(_profile!.username),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 3),
          backgroundColor: isDark ? const Color(0xFF1C1C1E) : _primary,
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

  Future<void> _aiGenerateAvatar(String description) async {
    // dialog 是否还在显示——避免网络异常提前抛出、或用户手动划走弹窗后，
    // 结果回来时再 pop 一次把个人主页本身也顶掉
    var dialogShowing = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AiGeneratingAvatarDialog(),
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
        showSingleAvatarConfirm(
          context,
          urls.first,
          onRegenerate: () => _aiGenerateAvatar(''),
          onUse: _setAvatarFromUrl,
        );
      } else {
        showAvatarPickerSheet(context, urls, onSelect: _setAvatarFromUrl);
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currentUser = ref.watch(currentUserProvider);
    // 发布教程/新建专栏后个人主页要跟着更新（"我的" tab 是常驻实例，
    // 见下面注释，不会自己重新加载）——发布页/专栏管理页操作成功时
    // 会 bump 这个信号，这里监听到变化就重新拉一次
    ref.listen<int>(profileRefreshSignalProvider, (prev, next) {
      if (!widget.showBackButton && prev != next && !_loading) {
        _onRefresh();
      }
    });
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
    // IP属地——系统判定、不可编辑，跟上面用户自己填的所在地是两码事。
    // 2026-07-06起本来从这一行拿掉过（为了省空间），现在放回来，位置在
    // 所在地和职业之间：所在地是用户自己说的，IP属地是系统判定的，职业
    // 紧接着星座——都跟同一份 GET /auth/me 数据源同款"后端没上线就是
    // null，UI 已经按不显示处理"的套路
    final displayIpLocation = isSelfView ? currentUser?.ipLocation : null;
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
            ? ProfileBlockedWidget(
                profile: _profile!,
                l10n: l10n,
                topPad: topPad,
                isMe: isMe,
                showBackButton: widget.showBackButton,
                startingChat: _startingChat,
                avatar: _buildAvatar(radius: 40),
                onBack: () => context.pop(),
                onStartChat: _startChat,
                onToggleFollow: _toggleFollow,
              )
            // 下半部（Tab栏+内容区）背景跟着主题走：深色主题用
            // _profileDarkBg，浅色主题保持原来的米白——之前改成不跟随
            // ThemePreference 的固定深色，浅色主题下背景变黑但文字/
            // Tab栏都还是按浅色配的颜色，反而看不清，这里改回去
            : Container(
                color: isDarkMode ? _profileDarkBg : _heroBg,
                child: NestedScrollView(
                  headerSliverBuilder: (ctx, _) => [
                    SliverToBoxAdapter(
                      child: ProfileHeaderWidget(
                        l10n: l10n,
                        isSelfView: isSelfView,
                        isMe: isMe,
                        displayUsername: displayUsername,
                        displayBio: displayBio,
                        displayLocation: displayLocation,
                        displayIpLocation: displayIpLocation,
                        displayOccupation: displayOccupation,
                        displayGender: displayGender,
                        displayZodiacSign: displayZodiacSign,
                        interestTags: interestTags,
                        topPad: topPad,
                        profile: _profile!,
                        showBackButton: widget.showBackButton,
                        uploadingCover: _uploadingCover,
                        uploadingAvatar: _uploadingAvatar,
                        coverImageUrl: _coverImageUrl,
                        totalLikes: _totalLikes,
                        totalViews: _totalViews,
                        savesCount: _saves.length,
                        savesPrivate: _savesPrivate,
                        formatCount: _formatCount,
                        links: _allLinks(),
                        avatar: _buildAvatar(radius: 34),
                        vipBadge: _buildVipBadge(isSelfView: isSelfView),
                        startingChat: _startingChat,
                        onBack: () => context.pop(),
                        onToggleTheme: _toggleTheme,
                        onAvatarTap: () => showAvatarOptions(
                          context,
                          onPickGallery: () =>
                              _pickAndUploadAvatar(ImageSource.gallery),
                          onPickCamera: () =>
                              _pickAndUploadAvatar(ImageSource.camera),
                          onAiAvatar: () {
                            // AI 生成头像是 Pro 权益——非 Pro 弹会员 Sheet
                            if (!requirePro(context, ref, feature: 'AI 生成头像')) {
                              return;
                            }
                            showAiAvatarSheet(
                              context,
                              onGenerate: _aiGenerateAvatar,
                            );
                          },
                        ),
                        onCoverTap: _pickAndUploadCover,
                        onLinksTap: () => _showLinksSheet(l10n),
                        onNotebookTap: () => context.push('/notebook'),
                        onEditProfile: () async {
                          await context.push('/edit-profile');
                          if (mounted) _loadProfile();
                        },
                        onToggleFollow: _toggleFollow,
                        onStartChat: _startChat,
                        onOpenLink: _openLink,
                      ),
                    ),
                    // Tab 栏——42px 白底，跟头图区分开，选中态黑字+黑色下划线；
                    // 加了 SliverPersistentHeader(pinned:true) 让它在往下滚动
                    // 内容时贴在头图底下不消失，教程九宫格/Notebook列表比头图
                    // 长很多时，切 tab 不用先滚回顶部
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: ProfileTabBarDelegate(
                        isDark: isDarkMode,
                        tabBar: TabBar(
                          controller: _tabCtrl,
                          labelColor: isDarkMode ? Colors.white : _ink,
                          unselectedLabelColor: isDarkMode
                              ? Colors.white.withValues(alpha: 0.35)
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
                      RefreshIndicator(
                        color: _primary,
                        onRefresh: _onRefresh,
                        child: Column(
                          children: [
                            _tabCountHeader(
                              l10n.articlesCountHeader(_tutorials.length),
                            ),
                            Expanded(
                              child: _tutorials.isEmpty
                                  ? _refreshableCenter(
                                      key: const PageStorageKey(
                                        'profile-tab-tutorials-empty',
                                      ),
                                      child: Text(
                                        l10n.noTutorialsPublished,
                                        style: const TextStyle(
                                          color: Colors.grey,
                                        ),
                                      ),
                                    )
                                  : ListView.builder(
                                      key: const PageStorageKey(
                                        'profile-tab-tutorials',
                                      ),
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      padding: EdgeInsets.zero,
                                      itemCount: _tutorials.length,
                                      itemBuilder: (ctx, i) {
                                        final t = _tutorials[i];
                                        return ArticleFlowItem(
                                          tutorial: t,
                                          onTap: () =>
                                              context.push('/tutorial/${t.id}'),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                      ColumnsTabView(
                        l10n: l10n,
                        isSelfView: isSelfView,
                        columns: _columns,
                        showCount: _showTabCount,
                        onRefresh: _onRefresh,
                        onColumnTap: (col) async {
                          final result = await context.push(
                            '/columns/${col.id}',
                          );
                          // 详情页「···」删除专栏后返回——把卡片从列表移除（淡出）
                          if (!mounted) return;
                          if (result is Map && result['deleted'] == true) {
                            setState(() {
                              _columns = _columns
                                  .where((c) => c.id != result['columnId'])
                                  .toList();
                            });
                          }
                        },
                        // 长按卡片删除（本页内直接处理）
                        onDeleteColumn: (col) => _deleteColumn(col.id),
                      ),
                      if (_showNotebookTab)
                        RefreshIndicator(
                          color: _primary,
                          onRefresh: _onRefresh,
                          child: Column(
                            children: [
                              _tabCountHeader(
                                l10n.filesCountLabel(_notebooks.length),
                              ),
                              Expanded(
                                child: _notebooks.isEmpty
                                    ? _refreshableCenter(
                                        key: const PageStorageKey(
                                          'profile-tab-notebooks-empty',
                                        ),
                                        child: Text(
                                          l10n.noNotebooksYet,
                                          style: const TextStyle(
                                            color: Colors.grey,
                                          ),
                                        ),
                                      )
                                    // Notebook 这个 tab 按规范是列表式（文件名+语言badge+
                                    // cells数量+时间），不是跟文章/收藏/点赞一样的九宫格
                                    : ListView.separated(
                                        key: const PageStorageKey(
                                          'profile-tab-notebooks',
                                        ),
                                        physics:
                                            const AlwaysScrollableScrollPhysics(),
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
                                          return NotebookListItem(
                                            notebook: nb,
                                            onTap: () => context.push(
                                              '/notebook/${nb['id']}',
                                            ),
                                          );
                                        },
                                      ),
                              ),
                            ],
                          ),
                        ),
                      RefreshIndicator(
                        color: _primary,
                        onRefresh: _onRefresh,
                        child: _savesPrivate
                            ? _refreshableCenter(
                                key: const PageStorageKey(
                                  'profile-tab-saves-private',
                                ),
                                child: _privateMessage(
                                  l10n.savesPrivateMessage,
                                ),
                              )
                            : Column(
                                children: [
                                  _tabCountHeader(
                                    l10n.savesCountHeader(_saves.length),
                                  ),
                                  Expanded(
                                    child: _saves.isEmpty
                                        ? _refreshableCenter(
                                            key: const PageStorageKey(
                                              'profile-tab-saves-empty',
                                            ),
                                            child: Text(
                                              l10n.noSavesYet,
                                              style: const TextStyle(
                                                color: Colors.grey,
                                              ),
                                            ),
                                          )
                                        : CustomScrollView(
                                            key: const PageStorageKey(
                                              'profile-tab-saves',
                                            ),
                                            controller: _savesScrollCtrl,
                                            physics:
                                                const AlwaysScrollableScrollPhysics(),
                                            slivers: [
                                              SliverList(
                                                delegate:
                                                    SliverChildBuilderDelegate((
                                                      ctx,
                                                      i,
                                                    ) {
                                                      final t = _saves[i];
                                                      return ArticleFlowItem(
                                                        tutorial: t,
                                                        onTap: () => context.push(
                                                          '/tutorial/${t.id}',
                                                        ),
                                                      );
                                                    }, childCount: _saves.length),
                                              ),
                                              if (_savesLoadingMore)
                                                const SliverToBoxAdapter(
                                                  child: Padding(
                                                    padding:
                                                        EdgeInsets.symmetric(
                                                          vertical: 16,
                                                        ),
                                                    child: Center(
                                                      child:
                                                          CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                  ),
                                ],
                              ),
                      ),
                      RefreshIndicator(
                        color: _primary,
                        onRefresh: _onRefresh,
                        child: Column(
                          children: [
                            _tabCountHeader(
                              l10n.likesCountHeader(_likes.length),
                            ),
                            Expanded(
                              child: _likes.isEmpty
                                  ? _refreshableCenter(
                                      key: const PageStorageKey(
                                        'profile-tab-likes-empty',
                                      ),
                                      child: Text(
                                        l10n.noLikesYet,
                                        style: const TextStyle(
                                          color: Colors.grey,
                                        ),
                                      ),
                                    )
                                  : CustomScrollView(
                                      key: const PageStorageKey(
                                        'profile-tab-likes',
                                      ),
                                      controller: _likesScrollCtrl,
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      slivers: [
                                        SliverList(
                                          delegate: SliverChildBuilderDelegate((
                                            ctx,
                                            i,
                                          ) {
                                            final t = _likes[i];
                                            return ArticleFlowItem(
                                              tutorial: t,
                                              onTap: () => context.push(
                                                '/tutorial/${t.id}',
                                              ),
                                            );
                                          }, childCount: _likes.length),
                                        ),
                                        if (_likesLoadingMore)
                                          const SliverToBoxAdapter(
                                            child: Padding(
                                              padding: EdgeInsets.symmetric(
                                                vertical: 16,
                                              ),
                                              child: Center(
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              ),
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
              ),
      ),
    );
  }

  // 收藏/点赞等占位 Tab 也要能下拉刷新——RefreshIndicator 得包一个真正
  // 可滚动的 Scrollable 才能识别下拉手势，光一个 Center 不够，所以套一层
  // 带 AlwaysScrollableScrollPhysics 的 ListView
  Widget _refreshableCenter({required Key key, required Widget child}) {
    return ListView(
      key: key,
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 80),
          child: Center(child: child),
        ),
      ],
    );
  }

  Widget _privateMessage(String text) {
    return Container(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 36, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(text, style: TextStyle(fontSize: 14, color: Colors.grey[400])),
        ],
      ),
    );
  }

  // 文章/专栏/文件这几个数量之前挤在头图区那一整排统计里，跟"效仿知乎"
  // 的要求一样改成不带 pill 底色的纯文字，内嵌在各自 Tab 内容最上面——
  // 自己/别人主页都会显示（这几个数字本来就是公开信息，隐私设置目前
  // 还没有覆盖到"是否隐藏内容数量"这一项）
  Widget _tabCountHeader(String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 只在 _showTabCount 期间展开显示，其余时间 AnimatedSize 把高度收成 0，
    // 不长期占位
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: !_showTabCount
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 2),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white38 : Colors.grey[500],
                ),
              ),
            ),
    );
  }

  // Pro/极光徽章——免费账号不再显示任何角标（之前免费用户也会露出一个
  // 灰色"VIP"占位角标，容易让人以为那是某种默认身份）。极光创作者优先于
  // 单纯的 Pro 会员展示（更稀有的身份），两者都没有就不渲染。自己查看
  // 自己主页点了跳会员管理页；查看别人主页时纯展示，不接一个"点了打开
  // 我自己订阅页"这种文不对题的跳转
  Widget _buildVipBadge({required bool isSelfView}) {
    final membership = isSelfView
        ? ref.watch(currentUserProvider)?.membership
        : _profile?.membership;
    final isAurora = isSelfView
        ? ref.watch(currentUserProvider)?.isAuroraCreator ?? false
        : _profile?.isAuroraCreator ?? false;
    final isMember = membership == 'pro' || membership == 'pro_max';
    if (!isAurora && !isMember) {
      // 免费用户——看自己主页时头像角标换成小皇冠，点了跳订阅页当升级
      // 入口；看别人主页不显示（升级入口只对本人有意义，且看别人主页
      // 拿不到对方真实membership，不该在这猜）
      if (!isSelfView) return const SizedBox.shrink();
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return GestureDetector(
        onTap: () => context.push('/settings/subscription'),
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A1A24) : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: isDark ? const Color(0xFF2A2A34) : const Color(0xFFF0F0F0),
              width: 1.5,
            ),
          ),
          child: const Icon(
            Icons.workspace_premium_outlined,
            size: 12,
            color: Color(0xFFD97706),
          ),
        ),
      );
    }

    final label = isAurora ? '极光' : 'Pro';
    return GestureDetector(
      onTap: isSelfView ? () => context.push('/settings/subscription') : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
          ),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: Colors.white, width: 1.2),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

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
    _countTimer?.cancel();
    _tabCtrl.removeListener(_onTabChanged);
    _tabCtrl.dispose();
    _savesScrollCtrl.dispose();
    _likesScrollCtrl.dispose();
    super.dispose();
  }
}
