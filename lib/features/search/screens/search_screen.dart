import 'dart:async';
import '../../../core/theme/app_colors.dart';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_client.dart';
import '../../../core/widgets/aurora_badge.dart';
import '../../../core/widgets/founding_badge.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/models/tutorial_model.dart';
import '../../../shared/models/user_model.dart';
import '../../../shared/utils/topic_badge.dart';
import '../../auth/auth_service.dart';
import '../../community/community_provider.dart';
import '../../groups/models/group_model.dart';

// 首页顶部原来的"推荐关注/为你推荐"两段搬过来了——本质是"你可能感兴趣
// 的内容/人"，跟搜索页"还没输入关键词时给点探索性内容"的空状态场景比
// 首页信息流场景更贴。"热门话题"没有一起单独搬——search_screen.dart
// 自己已经有一份用真实聚合数据（GET /auth/search 的 hotTags）驱动的
// 同名板块，比首页那份写死的固定标签表更准，直接算作已经"移过来"了，
// 不用再多一份重复的静态标签榜

class SearchScreen extends ConsumerStatefulWidget {
  final String? initialQuery;
  const SearchScreen({super.key, this.initialQuery});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen>
    with TickerProviderStateMixin {
  static const _primary = AppColors.primary;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _ink => _isDark ? Colors.white : const Color(0xFF1A1A1A);
  Color get _bg => _isDark
      ? Theme.of(context).scaffoldBackgroundColor
      : const Color(0xFFFAFAF8);
  Color get _cardBg => Theme.of(context).cardColor;
  Color get _border => Theme.of(context).dividerColor;
  Color get _muted => _isDark ? Colors.white54 : const Color(0xFF999999);
  Color get _tagBg =>
      _isDark ? _primary.withValues(alpha: 0.15) : AppColors.primaryLight;

  late final TextEditingController _ctrl;
  late final FocusNode _focusNode;
  late final TabController _tabCtrl;

  // 空状态四区块统一淡入——共用一个 controller，数据就绪后 forward() 一次，
  // 四块同时淡入，不再各自到齐就闪出来。就绪前显示骨架屏
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnim;
  bool _emptyReady = false;

  // 热门话题本地缓存 key（SharedPreferences，1 小时内直接用缓存，秒出不闪）
  static const _hotTagsCacheKey = 'search_hottags_cache_v1';
  static const _hotTagsCacheTtl = Duration(hours: 1);

  Timer? _debounce;
  bool _loading = false;
  bool _showSuggestions = false;

  List<dynamic> _suggestions = [];
  List<TutorialModel> _tutorials = [];
  List<UserModel> _users = [];
  List<dynamic> _tags = [];
  // 后端 GET /auth/search 目前只有 tutorials/users/tags 三种 type，没有
  // groups 分支——这里先把UI搭好，真调用真实（暂时会失败的）接口，
  // 失败/空结果就走下面 _buildNoResult 的空状态，不编一份假数据撑场面。
  // 后端把 type=groups 加上之后，这里不需要再改一行代码
  List<GroupModel> _groups = [];
  // 群组搜索结果的"加入"按钮要知道当前用户是不是已经在群里——搜索接口
  // 本身不带这个信息，用已有的真实接口 GET /auth/groups（我加入的群组）
  // 交叉比对，不是编一个假的会员状态
  Set<String> _myGroupIds = {};
  final Set<String> _joiningGroupIds = {};
  // 推荐关注按钮的乐观本地状态——跟原来首页那份是同一套逻辑
  final Set<String> _followingIds = {};
  List<dynamic> _hotTags = [];
  List<String> _history = [];

  String _currentQuery = '';

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialQuery ?? '');
    _focusNode = FocusNode();
    _tabCtrl = TabController(length: 4, vsync: this);
    _tabCtrl.addListener(() {
      if (_tabCtrl.indexIsChanging) return;
      setState(() {});
    });

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);

    _loadMyGroups();
    // 预加载：进页面立刻并行拉空状态要用的数据（历史 + 热门话题），不等用户
    // 看到页面才请求；就绪后统一触发淡入
    _loadDefaultData();

    if (widget.initialQuery?.isNotEmpty == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _search(widget.initialQuery!);
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
      });
    }
  }

  // 空状态数据的统一加载：先吃热门话题本地缓存（1h 内秒出），再并行拉最新的
  // 历史 + 热门话题，全部就绪后一次性淡入
  Future<void> _loadDefaultData() async {
    await _loadCachedHotTags();
    await Future.wait([_loadHistory(), _loadHotTags()]);
    if (!mounted) return;
    setState(() => _emptyReady = true);
    _fadeController.forward();
  }

  // 读热门话题缓存——1 小时内直接用，先让区块有内容（后面 _loadHotTags 拉到
  // 新数据会再刷新一次，但用户先看到的是缓存、不是空白）
  Future<void> _loadCachedHotTags() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_hotTagsCacheKey);
      if (raw == null) return;
      final cached = jsonDecode(raw) as Map<String, dynamic>;
      final ts = (cached['ts'] as num?)?.toInt() ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - ts >
          _hotTagsCacheTtl.inMilliseconds) {
        return;
      }
      final tags = cached['tags'] as List? ?? [];
      if (tags.isNotEmpty && mounted) {
        setState(() => _hotTags = tags);
      }
    } catch (_) {
      // 缓存损坏就当没有，走正常网络加载
    }
  }

  Future<void> _cacheHotTags(List<dynamic> tags) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _hotTagsCacheKey,
        jsonEncode({'ts': DateTime.now().millisecondsSinceEpoch, 'tags': tags}),
      );
    } catch (_) {}
  }

  String? get _userId => ref.read(currentUserProvider)?.id;

  // 搜索历史改由后端存（GET/POST/DELETE /auth/search/history），换设备也在，
  // 每用户最多 20 条。未登录用户没有历史，跳过所有历史相关请求
  static const _historyLimit = 20;

  Future<void> _loadHistory() async {
    if (_userId == null) return;
    final res = await ref.read(apiClientProvider).get('/auth/search/history');
    if (!mounted || !res.success) return;
    final list = (res.data as Map?)?['history'] as List? ?? [];
    setState(() {
      _history = list
          .map((e) => e is Map ? (e['keyword'] ?? '').toString() : e.toString())
          .where((s) => s.isNotEmpty)
          .toList();
    });
  }

  // 保存一条搜索记录——后端会去重置顶并裁到 20 条，这里只管发一条
  Future<void> _saveSearchKeyword(String keyword) async {
    if (_userId == null) return;
    await ref
        .read(apiClientProvider)
        .post('/auth/search/history', data: {'keyword': keyword});
  }

  Future<void> _clearHistory() async {
    if (_userId == null) return;
    final res = await ref
        .read(apiClientProvider)
        .delete('/auth/search/history');
    if (!mounted) return;
    if (res.success) {
      setState(() => _history = []);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(res.message ?? '清空失败，请稍后重试')));
    }
  }

  Future<void> _loadMyGroups() async {
    final res = await ref.read(apiClientProvider).get('/auth/groups');
    if (!mounted || !res.success || res.data == null) return;
    final groups = ((res.data['groups'] as List?) ?? []).map(
      (g) => Map<String, dynamic>.from(g as Map),
    );
    setState(() {
      _myGroupIds = groups.map((g) => g['id'].toString()).toSet();
    });
  }

  // 后端 group.routes.ts 目前只有 invite/leave/disband，没有"自己申请
  // 加入"这个接口——真调用真实（暂时会 404）的 POST /:id/join，失败给
  // 明确的错误提示，不假装加入成功。接口上线后这里不用再改
  Future<void> _joinGroup(GroupModel g) async {
    if (_joiningGroupIds.contains(g.id)) return;
    setState(() => _joiningGroupIds.add(g.id));
    final res = await ref
        .read(apiClientProvider)
        .post('/auth/groups/${g.id}/join');
    if (!mounted) return;
    setState(() {
      _joiningGroupIds.remove(g.id);
      if (res.success) _myGroupIds = {..._myGroupIds, g.id};
    });
    if (!res.success) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(res.message ?? '加入失败，请稍后重试')));
    }
  }

  Future<void> _toggleFollow(String? userId) async {
    if (userId == null || userId.isEmpty) return;
    final api = ref.read(apiClientProvider);
    final following = _followingIds.contains(userId);
    final res = following
        ? await api.delete('/auth/users/$userId/follow')
        : await api.post('/auth/users/$userId/follow');
    if (!mounted) return;
    if (res.success) {
      setState(() {
        following ? _followingIds.remove(userId) : _followingIds.add(userId);
      });
    } else {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.actionFailedWithReason('${res.message}'))),
      );
    }
  }

  Future<void> _loadHotTags() async {
    try {
      final res = await ref
          .read(apiClientProvider)
          .get('/auth/search', queryParameters: {'q': ''});
      if (res.success && mounted) {
        final tags = (res.data as Map?)?['hotTags'] as List? ?? [];
        setState(() => _hotTags = tags);
        if (tags.isNotEmpty) unawaited(_cacheHotTags(tags));
      }
    } catch (e) {
      // 热门话题只是空状态下的引导内容，加载失败不影响主搜索流程，静默即可
    }
  }

  void _onQueryChanged(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() {
        _showSuggestions = false;
        _suggestions = [];
      });
      return;
    }
    // 输入以 @ 开头时默认就是在找人，提前切到"用户"Tab——真正的结果还是
    // 等提交搜索（_search）才会拉，这里只是先把用户想看的位置摆对
    if (q.trim().startsWith('@') && _tabCtrl.index != 1) {
      _tabCtrl.animateTo(1);
    }
    setState(() => _showSuggestions = true);
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _fetchSuggestions(q.trim());
    });
  }

  Future<void> _fetchSuggestions(String q) async {
    try {
      final res = await ref
          .read(apiClientProvider)
          .get('/auth/search/suggest', queryParameters: {'q': q});
      if (res.success && mounted) {
        setState(() {
          _suggestions = (res.data as Map?)?['suggestions'] as List? ?? [];
        });
      }
    } catch (e) {
      // 联想词是搜索框下面的辅助浮层，请求失败就不显示，不打断输入
    }
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) return;
    final query = q.trim();
    _focusNode.unfocus();
    setState(() {
      _loading = true;
      _showSuggestions = false;
      _currentQuery = query;
      _ctrl.text = query;
    });

    // 只有登录用户才有搜索历史。乐观更新：本地去重置顶（跟后端
    // saveSearchHistory 行为一致），再异步 POST 落库
    if (_userId != null) {
      setState(() {
        _history.remove(query);
        _history.insert(0, query);
        if (_history.length > _historyLimit) {
          _history = _history.sublist(0, _historyLimit);
        }
      });
      unawaited(_saveSearchKeyword(query));
    }

    // 后端 users LIKE 匹配的是 username/handle 本身，不含 @ 前缀——
    // 展示/历史记录保留用户敲的原文，实际发给接口的关键词去掉这个前缀
    final apiQuery = query.startsWith('@') ? query.substring(1) : query;

    try {
      final results = await Future.wait([
        ref
            .read(apiClientProvider)
            .get('/auth/search', queryParameters: {'q': apiQuery}),
        ref
            .read(apiClientProvider)
            .get(
              '/auth/search',
              queryParameters: {'q': apiQuery, 'type': 'groups'},
            ),
      ]);
      final res = results[0];
      final groupsRes = results[1];
      if (!mounted) return;
      if (res.success) {
        final data = res.data as Map?;
        setState(() {
          _tutorials = ((data?['tutorials'] as List?) ?? [])
              .map(
                (t) =>
                    TutorialModel.fromJson(Map<String, dynamic>.from(t as Map)),
              )
              .toList();
          _users = ((data?['users'] as List?) ?? [])
              .map(
                (u) => UserModel.fromJson(Map<String, dynamic>.from(u as Map)),
              )
              .toList();
          _tags = data?['tags'] as List? ?? [];
        });
      }
      // type=groups 接口后端还没有，failure 时 _groups 保持空列表，走
      // _buildNoResult 空状态——不是拿假数据填一个"看起来有结果"的假象
      if (groupsRes.success) {
        final groupsData = groupsRes.data as Map?;
        setState(() {
          _groups = ((groupsData?['groups'] as List?) ?? [])
              .map(
                (g) => GroupModel.fromJson(Map<String, dynamic>.from(g as Map)),
              )
              .toList();
        });
      } else {
        setState(() => _groups = []);
      }
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildSearchBar(),
                if (_currentQuery.isEmpty)
                  // 点最近搜索/热门话题区的空白处收起键盘——ListView 默认
                  // 不 unfocus，opaque 让整块空状态（含条目间空隙）都接住
                  // tap；话题/历史 chip 是各自的 GestureDetector，子级优先命中
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _focusNode.unfocus(),
                      // 数据就绪前显示骨架屏，就绪后四区块统一淡入——不再逐块
                      // 闪出来
                      child: _emptyReady
                          ? FadeTransition(
                              opacity: _fadeAnim,
                              child: _buildEmptyState(),
                            )
                          : _buildEmptySkeleton(),
                    ),
                  )
                else if (_loading)
                  const Expanded(
                    child: Center(
                      child: CircularProgressIndicator(color: _primary),
                    ),
                  )
                else
                  Expanded(
                    child: Column(
                      children: [
                        _buildTabBar(),
                        Expanded(
                          child: TabBarView(
                            controller: _tabCtrl,
                            children: [
                              _buildTutorialResults(),
                              _buildUserResults(),
                              _buildTagResults(),
                              _buildGroupResults(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            // 联想词浮层——绝对定位盖在搜索框正下方，不是 Column 里的一员，
            // 不然结果区/空状态会被它往下挤
            if (_showSuggestions && _suggestions.isNotEmpty)
              Positioned(
                top: 64,
                left: 0,
                right: 0,
                child: _buildSuggestionsOverlay(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      color: _bg,
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                // 浅色输入胶囊改白底（原来是灰 #E8E8ED）；深色用主题卡片色。
                // 白底衬在 #FAFAF8 页面上对比很淡，补一条 0.5px 细边界定轮廓
                color: _isDark ? _cardBg : Colors.white,
                borderRadius: BorderRadius.circular(19),
                border: Border.all(color: _border, width: 0.5),
              ),
              child: TextField(
                controller: _ctrl,
                focusNode: _focusNode,
                decoration: InputDecoration(
                  hintText: l10n.searchHint,
                  hintStyle: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  prefixIcon: Icon(
                    Icons.search,
                    size: 20,
                    color: Colors.grey[600],
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 20,
                  ),
                  suffixIcon: _ctrl.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.close,
                            size: 18,
                            color: Colors.grey[600],
                          ),
                          onPressed: () {
                            _ctrl.clear();
                            setState(() {
                              _currentQuery = '';
                              _showSuggestions = false;
                              _suggestions = [];
                            });
                            _focusNode.requestFocus();
                          },
                        )
                      : null,
                  filled: false,
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 9),
                ),
                style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A1A)),
                onChanged: _onQueryChanged,
                onSubmitted: _search,
                textInputAction: TextInputAction.search,
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => context.pop(),
            child: Text(
              l10n.searchCancel,
              style: const TextStyle(fontSize: 14, color: _primary),
            ),
          ),
        ],
      ),
    );
  }

  // 空状态骨架屏——大致比着真实布局摆占位灰块（区块标题条 + 横滑卡片 +
  // 列表行 + 话题 chip），数据没到位时先撑住结构，不留白也不逐块弹
  Color get _skelColor =>
      _isDark ? const Color(0xFF2A2A3A) : const Color(0xFFEEEEEE);

  Widget _skelBox(double w, double h, {double r = 7}) => Container(
    width: w,
    height: h,
    decoration: BoxDecoration(
      color: _skelColor,
      borderRadius: BorderRadius.circular(r),
    ),
  );

  Widget _skelSection({required Widget body}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _skelBox(96, 16),
      const SizedBox(height: 12),
      body,
      const SizedBox(height: 24),
    ],
  );

  Widget _buildEmptySkeleton() {
    return ListView(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        // 最近搜索：一排 chip
        _skelSection(
          body: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              72.0,
              96.0,
              60.0,
              84.0,
            ].map((w) => _skelBox(w, 24, r: 12)).toList(),
          ),
        ),
        // 推荐关注：横滑卡片
        _skelSection(
          body: SizedBox(
            height: 156,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 3,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, __) => _skelBox(130, 156, r: 16),
            ),
          ),
        ),
        // 为你推荐：列表行
        _skelSection(
          body: Column(
            children: List.generate(
              3,
              (_) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _skelBox(double.infinity, 52, r: 12),
              ),
            ),
          ),
        ),
        // 热门话题：一排 chip
        _skelSection(
          body: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              80.0,
              64.0,
              100.0,
              72.0,
              56.0,
            ].map((w) => _skelBox(w, 24, r: 12)).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final l10n = AppLocalizations.of(context)!;
    final discoverState = ref.watch(communityProvider);
    final rankList = ([
      ...discoverState.filtered,
    ]..sort((a, b) => b.views.compareTo(a.views))).take(5).toList();
    final seenAuthors = <String>{};
    final suggestedAuthors = <TutorialModel>[];
    for (final t in discoverState.tutorials) {
      if (t.username.isEmpty || !seenAuthors.add(t.username)) continue;
      suggestedAuthors.add(t);
      if (suggestedAuthors.length >= 8) break;
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_history.isNotEmpty) ...[
          _sectionHeader(
            l10n.searchHistory,
            action: GestureDetector(
              onTap: _clearHistory,
              child: Text(
                l10n.searchClear,
                style: TextStyle(fontSize: 12, color: _muted),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _history.map((h) {
              return GestureDetector(
                onTap: () => _search(h),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  // 去掉白色 pill 背景，chip 直接坐在页面底色上
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history, size: 13, color: _muted),
                      const SizedBox(width: 4),
                      Text(h, style: TextStyle(fontSize: 13, color: _ink)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
        ],
        if (suggestedAuthors.isNotEmpty) ...[
          _sectionHeader('推荐关注'),
          const SizedBox(height: 8),
          _suggestedFollowSection(suggestedAuthors),
          const SizedBox(height: 20),
        ],
        if (rankList.isNotEmpty) ...[
          _sectionHeader('为你推荐'),
          const SizedBox(height: 8),
          _newsRankingSection(rankList),
          const SizedBox(height: 20),
        ],
        if (_hotTags.isNotEmpty) ...[
          _sectionHeader(l10n.searchHotTopics),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _hotTags.map((t) {
              final tag = (t as Map)['tag'] as String? ?? '';
              final count = t['count'] ?? 0;
              return GestureDetector(
                onTap: () => _search(tag),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  // 去掉白色 pill 背景，chip 直接坐在页面底色上
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '#',
                        style: TextStyle(
                          fontSize: 13,
                          color: _primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Text(tag, style: TextStyle(fontSize: 13, color: _ink)),
                      const SizedBox(width: 4),
                      Text(
                        '$count',
                        style: TextStyle(fontSize: 11, color: _muted),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _suggestedFollowSection(List<TutorialModel> authors) {
    return SizedBox(
      height: 156,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: authors.length,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final t = authors[index];
          final following = _followingIds.contains(t.userId);
          final category = topicCategoryLabelFor(t.tags);
          return Container(
            width: 130,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border, width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: t.username.isEmpty
                      ? null
                      : () => context.push('/users/${t.username}'),
                  child: _searchAuthorAvatar(
                    avatar: t.avatar,
                    username: t.username,
                    isFoundingCreator: t.isFoundingCreator,
                    radius: 20,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  t.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                if (category != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: _muted),
                  ),
                ],
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 27,
                  child: OutlinedButton(
                    onPressed: () => _toggleFollow(t.userId),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      backgroundColor: following ? null : _primary,
                      side: BorderSide(color: following ? _border : _primary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    child: Text(
                      following ? '已关注' : '关注',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: following ? _muted : Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _newsRankingSection(List<TutorialModel> rankList) {
    const rankColors = [
      Color(0xFFF43F5E),
      Color(0xFFF59E0B),
      Color(0xFF10B981),
    ];
    // 去掉白色卡片背景，排行列表直接坐在页面底色上，跟区块标题左对齐
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(rankList.length, (index) {
        final t = rankList[index];
        return GestureDetector(
          onTap: () => context.push('/tutorial/${t.id}'),
          child: Padding(
            padding: EdgeInsets.only(top: index == 0 ? 0 : 7, bottom: 7),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: index < 3 ? rankColors[index] : _muted,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: _ink),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${t.views}',
                  style: TextStyle(fontSize: 11.5, color: _muted),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _searchAuthorAvatar({
    required String? avatar,
    required String username,
    required double radius,
    bool isFoundingCreator = false,
  }) {
    final hasAvatar = (avatar ?? '').isNotEmpty;
    return FoundingAvatarRing(
      isFoundingCreator: isFoundingCreator,
      size: radius * 2,
      child: CircleAvatar(
        radius: radius,
        backgroundColor: _primary.withValues(alpha: 0.15),
        backgroundImage: hasAvatar ? CachedNetworkImageProvider(avatar!) : null,
        child: !hasAvatar
            ? Text(
                username.isNotEmpty ? username.substring(0, 1) : '?',
                style: TextStyle(
                  fontSize: radius,
                  fontWeight: FontWeight.w700,
                  color: _primary,
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildTabBar() {
    final l10n = AppLocalizations.of(context)!;
    // "群组"暂时没有对应的 l10n key（后端 type=groups 分支还没有，先
    // 硬编码文案，等后端接上再按需要补 arb 词条）
    final counts = [
      _tutorials.length,
      _users.length,
      _tags.length,
      _groups.length,
    ];
    final labels = [
      l10n.searchTutorials,
      l10n.searchUsers,
      l10n.searchTags,
      '群组',
    ];

    return Container(
      color: _cardBg,
      child: TabBar(
        controller: _tabCtrl,
        labelColor: _primary,
        unselectedLabelColor: _muted,
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        indicatorColor: _primary,
        indicatorWeight: 2,
        tabs: List.generate(4, (i) {
          return Tab(
            text: counts[i] > 0 ? '${labels[i]} ${counts[i]}' : labels[i],
          );
        }),
      ),
    );
  }

  Widget _buildTutorialResults() {
    final l10n = AppLocalizations.of(context)!;
    if (_tutorials.isEmpty) return _buildNoResult(l10n.searchTutorials);
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _tutorials.length,
      separatorBuilder: (_, __) => Divider(
        height: 0.5,
        thickness: 0.5,
        indent: 16,
        endIndent: 16,
        color: _border,
      ),
      itemBuilder: (ctx, i) {
        final t = _tutorials[i];
        return _TutorialResultItem(
          tutorial: t,
          query: _currentQuery,
          onTap: () => context.push('/tutorial/${t.id}'),
        );
      },
    );
  }

  Widget _buildUserResults() {
    final l10n = AppLocalizations.of(context)!;
    if (_users.isEmpty) {
      return _buildNoResult(
        l10n.searchUsers,
        title: '没有找到该用户',
        subtitle: '试试搜索 @用户名',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _users.length,
      separatorBuilder: (_, __) => Divider(
        height: 0.5,
        thickness: 0.5,
        indent: 72,
        endIndent: 16,
        color: _border,
      ),
      itemBuilder: (ctx, i) {
        final u = _users[i];
        final hasAvatar = (u.avatar ?? '').isNotEmpty;
        final following = _followingIds.contains(u.id);
        return ListTile(
          onTap: () => context.push('/users/${u.handle ?? u.username}'),
          leading: CircleAvatar(
            radius: 22,
            backgroundColor: _primary,
            backgroundImage: hasAvatar
                ? CachedNetworkImageProvider(u.avatar!)
                : null,
            child: !hasAvatar
                ? Text(
                    u.username.isNotEmpty ? u.username[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : null,
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  u.username,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _ink,
                  ),
                ),
              ),
              if (u.isAuroraCreator) const AuroraBadgeSmall(),
            ],
          ),
          subtitle: u.handle != null
              ? Text(
                  '@${u.handle}',
                  style: const TextStyle(fontSize: 12, color: _primary),
                )
              : null,
          trailing: SizedBox(
            width: 68,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${u.followerCount} 粉丝',
                  style: TextStyle(fontSize: 10.5, color: _muted),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 26,
                  child: OutlinedButton(
                    onPressed: () => _toggleFollow(u.id),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      backgroundColor: following ? null : _primary,
                      side: BorderSide(color: following ? _border : _primary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    child: Text(
                      following ? '已关注' : '关注',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: following ? _muted : Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildGroupResults() {
    if (_groups.isEmpty) {
      return _buildNoResult('群组', title: '没有找到相关群组', subtitle: '试试搜索群组名称或ID');
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _groups.length,
      separatorBuilder: (_, _) => Divider(
        height: 0.5,
        thickness: 0.5,
        indent: 72,
        endIndent: 16,
        color: _border,
      ),
      itemBuilder: (ctx, i) {
        final g = _groups[i];
        final joined = _myGroupIds.contains(g.id);
        final joining = _joiningGroupIds.contains(g.id);
        return ListTile(
          onTap: () => context.push(
            '/group/${g.id}',
            extra: {'name': g.name, 'memberCount': g.memberCount},
          ),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primaryLight, Color(0xFFDDD6FE)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                g.name.isNotEmpty ? g.name.substring(0, 1) : '群',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _primary,
                ),
              ),
            ),
          ),
          title: Text(
            g.name,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: _ink,
            ),
          ),
          subtitle: Text(
            '${g.memberCount} 成员 · ${g.isPublic ? "公开" : "私密"}',
            style: TextStyle(fontSize: 12, color: _muted),
          ),
          trailing: SizedBox(
            width: 76,
            height: 28,
            child: OutlinedButton(
              onPressed: joining
                  ? null
                  : joined
                  ? () => context.push(
                      '/group/${g.id}',
                      extra: {'name': g.name, 'memberCount': g.memberCount},
                    )
                  : () => _joinGroup(g),
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                backgroundColor: joined ? null : _primary,
                side: BorderSide(color: joined ? _border : _primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              child: joining
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: joined ? _muted : Colors.white,
                      ),
                    )
                  : Text(
                      joined ? '进入群聊' : '加入',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: joined ? _muted : Colors.white,
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTagResults() {
    final l10n = AppLocalizations.of(context)!;
    if (_tags.isEmpty) return _buildNoResult(l10n.searchTags);
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _tags.length,
      itemBuilder: (ctx, i) {
        final tag = (_tags[i] as Map)['tag'] as String? ?? '';
        final count = _tags[i]['count'] ?? 0;
        return GestureDetector(
          onTap: () {
            _search(tag);
            _tabCtrl.animateTo(0);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: _cardBg,
              border: Border(bottom: BorderSide(color: _border, width: 0.5)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _tagBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Text(
                      '#',
                      style: TextStyle(
                        fontSize: 16,
                        color: _primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tag,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: _ink,
                        ),
                      ),
                      Text(
                        '$count 篇教程',
                        style: TextStyle(fontSize: 12, color: _muted),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: _muted, size: 18),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSuggestionsOverlay() {
    return Container(
      color: _cardBg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(height: 0.5, color: _border),
          ..._suggestions.take(8).map((s) {
            final map = s as Map;
            final text = map['text'] as String? ?? '';
            final type = map['type'] as String? ?? '';
            IconData icon;
            Color iconColor;
            if (type == 'user') {
              icon = Icons.person_outline;
              iconColor = _muted;
            } else if (type == 'tag') {
              icon = Icons.tag;
              iconColor = _primary;
            } else {
              icon = Icons.search;
              iconColor = _muted;
            }
            return GestureDetector(
              onTap: () => _search(text),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 16, color: iconColor),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        text,
                        style: TextStyle(fontSize: 14, color: _ink),
                      ),
                    ),
                    Icon(Icons.north_west, size: 14, color: _muted),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // 用户/群组两个Tab的空状态文案换成更具体的引导（怎么搜更容易搜到），
  // 不是套用"没有找到 XX 的结果，换个关键词试试"这句所有Tab通用的话
  Widget _buildNoResult(String type, {String? title, String? subtitle}) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off_outlined,
            size: 48,
            color: _isDark ? Colors.white24 : Colors.grey.shade300,
          ),
          const SizedBox(height: 12),
          Text(
            title ?? l10n.searchNoResult(type),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: _muted),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle ?? l10n.searchTryOther,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: _isDark ? Colors.white30 : Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, {Widget? action}) => Row(
    children: [
      Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: _ink,
        ),
      ),
      const Spacer(),
      if (action != null) action,
    ],
  );

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    _tabCtrl.dispose();
    _fadeController.dispose();
    _debounce?.cancel();
    super.dispose();
  }
}

// 教程搜索结果 item（标题按关键词高亮）
class _TutorialResultItem extends StatelessWidget {
  final TutorialModel tutorial;
  final String query;
  final VoidCallback onTap;

  const _TutorialResultItem({
    required this.tutorial,
    required this.query,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final muted = isDark ? Colors.white54 : const Color(0xFF999999);
    final tagBg = isDark
        ? AppColors.primary.withValues(alpha: 0.15)
        : AppColors.primaryLight;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        color: Theme.of(context).cardColor,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HighlightText(
                    text: tutorial.title,
                    query: query,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: ink,
                      height: 1.4,
                    ),
                    highlightStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if ((tutorial.summary ?? '').isNotEmpty)
                    Text(
                      tutorial.summary!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: muted, height: 1.5),
                    ),
                  const SizedBox(height: 6),
                  if (tutorial.tags.isNotEmpty)
                    Wrap(
                      spacing: 4,
                      children: tutorial.tags.take(3).map((t) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: tagBg,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '#$t',
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.primary,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 10,
                        backgroundColor: AppColors.primary,
                        backgroundImage: (tutorial.avatar ?? '').isNotEmpty
                            ? CachedNetworkImageProvider(tutorial.avatar!)
                            : null,
                        child: (tutorial.avatar ?? '').isEmpty
                            ? Text(
                                tutorial.username.isNotEmpty
                                    ? tutorial.username[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        tutorial.username,
                        style: TextStyle(fontSize: 11, color: muted),
                      ),
                      const SizedBox(width: 10),
                      Icon(Icons.favorite_outline, size: 12, color: muted),
                      const SizedBox(width: 2),
                      Text(
                        '${tutorial.likes}',
                        style: TextStyle(fontSize: 11, color: muted),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.remove_red_eye_outlined,
                        size: 12,
                        color: muted,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${tutorial.views}',
                        style: TextStyle(fontSize: 11, color: muted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if ((tutorial.coverImage ?? '').isNotEmpty) ...[
              const SizedBox(width: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  tutorial.coverImage!,
                  width: 72,
                  height: 60,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// 关键词高亮组件——只处理单个不区分大小写的子串匹配，不支持分词/多关键词
// 高亮，跟后端搜索本身是简单的LIKE匹配还是分词全文检索保持同一档次，没有
// 反而比后端匹配能力更强
class _HighlightText extends StatelessWidget {
  final String text;
  final String query;
  final TextStyle style;
  final TextStyle highlightStyle;

  const _HighlightText({
    required this.text,
    required this.query,
    required this.style,
    required this.highlightStyle,
  });

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) return Text(text, style: style);

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;

    while (true) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index == -1) {
        spans.add(TextSpan(text: text.substring(start), style: style));
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index), style: style));
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + query.length),
          style: highlightStyle,
        ),
      );
      start = index + query.length;
    }

    return RichText(
      text: TextSpan(children: spans),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
