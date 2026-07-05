import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/models/tutorial_model.dart';
import '../../../shared/models/user_model.dart';
import '../../auth/auth_service.dart';

class SearchScreen extends ConsumerStatefulWidget {
  final String? initialQuery;
  const SearchScreen({super.key, this.initialQuery});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen>
    with SingleTickerProviderStateMixin {
  static const _primary = Color(0xFF6366F1);
  static const _ink = Color(0xFF1A1A1A);
  static const _bg = Color(0xFFFAFAF8);
  static const _border = Color(0xFFF0F0F0);
  static const _muted = Color(0xFF999999);

  late final TextEditingController _ctrl;
  late final FocusNode _focusNode;
  late final TabController _tabCtrl;

  Timer? _debounce;
  bool _loading = false;
  bool _showSuggestions = false;

  List<dynamic> _suggestions = [];
  List<TutorialModel> _tutorials = [];
  List<UserModel> _users = [];
  List<dynamic> _tags = [];
  List<dynamic> _hotTags = [];
  List<String> _history = [];

  String _currentQuery = '';

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialQuery ?? '');
    _focusNode = FocusNode();
    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(() {
      if (_tabCtrl.indexIsChanging) return;
      setState(() {});
    });

    _loadHistory();

    if (widget.initialQuery?.isNotEmpty == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _search(widget.initialQuery!);
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
        _loadHotTags();
      });
    }
  }

  String? get _userId => ref.read(currentUserProvider)?.id;

  Future<void> _loadHistory() async {
    final userId = _userId;
    if (userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(AppConstants.keySearchHistory(userId));
    if (saved != null && mounted) setState(() => _history = saved);
  }

  Future<void> _saveHistory() async {
    final userId = _userId;
    if (userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(AppConstants.keySearchHistory(userId), _history);
  }

  Future<void> _loadHotTags() async {
    try {
      final res = await ref
          .read(apiClientProvider)
          .get('/auth/search', queryParameters: {'q': ''});
      if (res.success && mounted) {
        setState(() {
          _hotTags = (res.data as Map?)?['hotTags'] as List? ?? [];
        });
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

    if (!_history.contains(query)) {
      setState(() {
        _history.insert(0, query);
        if (_history.length > AppConstants.maxSearchHistory) {
          _history = _history.sublist(0, AppConstants.maxSearchHistory);
        }
      });
      unawaited(_saveHistory());
    }

    try {
      final res = await ref
          .read(apiClientProvider)
          .get('/auth/search', queryParameters: {'q': query});
      if (res.success && mounted) {
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
          _loading = false;
        });
      } else if (mounted) {
        setState(() => _loading = false);
      }
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
                  Expanded(child: _buildEmptyState())
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
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _border, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: TextField(
                controller: _ctrl,
                focusNode: _focusNode,
                decoration: InputDecoration(
                  hintText: l10n.searchHint,
                  hintStyle: const TextStyle(fontSize: 14, color: _muted),
                  prefixIcon: const Icon(Icons.search, size: 20, color: _muted),
                  suffixIcon: _ctrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.close,
                            size: 18,
                            color: _muted,
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
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                style: const TextStyle(fontSize: 14, color: _ink),
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

  Widget _buildEmptyState() {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_history.isNotEmpty) ...[
          _sectionHeader(
            l10n.searchHistory,
            action: GestureDetector(
              onTap: () {
                setState(() => _history = []);
                unawaited(_saveHistory());
              },
              child: Text(
                l10n.searchClear,
                style: const TextStyle(fontSize: 12, color: _muted),
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
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: _border, width: 0.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.history, size: 13, color: _muted),
                      const SizedBox(width: 4),
                      Text(
                        h,
                        style: const TextStyle(fontSize: 13, color: _ink),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
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
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: _border, width: 0.5),
                  ),
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
                      Text(
                        tag,
                        style: const TextStyle(fontSize: 13, color: _ink),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$count',
                        style: const TextStyle(fontSize: 11, color: _muted),
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

  Widget _buildTabBar() {
    final l10n = AppLocalizations.of(context)!;
    final counts = [_tutorials.length, _users.length, _tags.length];
    final labels = [l10n.searchTutorials, l10n.searchUsers, l10n.searchTags];

    return Container(
      color: Colors.white,
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
        tabs: List.generate(3, (i) {
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
      separatorBuilder: (_, __) => const Divider(
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
    if (_users.isEmpty) return _buildNoResult(l10n.searchUsers);
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _users.length,
      separatorBuilder: (_, __) => const Divider(
        height: 0.5,
        thickness: 0.5,
        indent: 72,
        endIndent: 16,
        color: _border,
      ),
      itemBuilder: (ctx, i) {
        final u = _users[i];
        final hasAvatar = (u.avatar ?? '').isNotEmpty;
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
          title: Text(
            u.username,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: _ink,
            ),
          ),
          subtitle: u.handle != null
              ? Text(
                  '@${u.handle}',
                  style: const TextStyle(fontSize: 12, color: _primary),
                )
              : null,
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${u.followerCount}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _ink,
                ),
              ),
              const Text('粉丝', style: TextStyle(fontSize: 11, color: _muted)),
            ],
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
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: _border, width: 0.5)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF0FF),
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
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: _ink,
                        ),
                      ),
                      Text(
                        '$count 篇教程',
                        style: const TextStyle(fontSize: 12, color: _muted),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: _muted, size: 18),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSuggestionsOverlay() {
    return Container(
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(height: 0.5, color: _border),
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
                        style: const TextStyle(fontSize: 14, color: _ink),
                      ),
                    ),
                    const Icon(Icons.north_west, size: 14, color: _muted),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildNoResult(String type) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off_outlined,
            size: 48,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.searchNoResult(type),
            style: const TextStyle(fontSize: 14, color: _muted),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.searchTryOther,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, {Widget? action}) => Row(
    children: [
      Text(
        title,
        style: const TextStyle(
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        color: Colors.white,
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
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A1A),
                      height: 1.4,
                    ),
                    highlightStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6366F1),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if ((tutorial.summary ?? '').isNotEmpty)
                    Text(
                      tutorial.summary!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF999999),
                        height: 1.5,
                      ),
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
                            color: const Color(0xFFEEF0FF),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '#$t',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF6366F1),
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
                        backgroundColor: const Color(0xFF6366F1),
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
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF999999),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(
                        Icons.favorite_outline,
                        size: 12,
                        color: Color(0xFF999999),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${tutorial.likes}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF999999),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.remove_red_eye_outlined,
                        size: 12,
                        color: Color(0xFF999999),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${tutorial.views}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF999999),
                        ),
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
