import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/membership_utils.dart';
import '../../../features/auth/auth_service.dart';
import '../../../features/creator/screens/creator_stats_screen.dart';
import '../../../features/notebook/screens/notebook_home_screen.dart';
import '../../../features/settings/screens/settings_screen.dart';
import '../../../shared/models/tutorial_model.dart';
import '../../../shared/models/user_model.dart';

const _accent = AppColors.primary;

enum _Section { articles, notebook, collections, stats, settings }

// HD「我的」——宽屏双栏创作者主页。左栏(280) = 头像/徽章/简介/统计/协议 + 菜单；
// 右栏(flex) 随菜单切换：文章卡片列表 / Notebook / 收藏 / 数据详情 / 创作设置。
// 数据全部走真实 provider/接口：currentUserProvider（头像徽章）、GET /auth/tutorials
// （客户端按作者过滤，跟手机 UserProfileScreen 同一套）、GET /auth/me/saves（收藏）、
// GET /auth/agreement/status（原创协议）。不再复用整块手机页，也不留假数据。
class HdProfilePage extends ConsumerStatefulWidget {
  const HdProfilePage({super.key});

  @override
  ConsumerState<HdProfilePage> createState() => _HdProfilePageState();
}

class _HdProfilePageState extends ConsumerState<HdProfilePage> {
  _Section _section = _Section.articles;

  List<TutorialModel> _tutorials = [];
  bool _loadingArticles = true;

  List<TutorialModel> _saves = [];
  bool _loadingSaves = false;
  bool _savesLoaded = false;

  bool _agreementSigned = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadArticles();
      _loadAgreement();
    });
  }

  // 文章：GET /auth/tutorials?author=xxx 后端过滤目前不生效，跟手机端一样
  // 客户端按 userId 兜底过滤，避免串读到别人的教程
  Future<void> _loadArticles() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final res = await ref
        .read(apiClientProvider)
        .get(
          '/auth/tutorials',
          queryParameters: {'author': user.username, 'status': 'published'},
        );
    if (!mounted) return;
    setState(() {
      _loadingArticles = false;
      if (res.success && res.data != null) {
        final list = ((res.data as Map)['tutorials'] as List?) ?? const [];
        _tutorials = list
            .map((j) => TutorialModel.fromJson(Map<String, dynamic>.from(j as Map)))
            .where((t) => t.userId == user.id)
            .toList();
      }
    });
  }

  Future<void> _loadSaves() async {
    if (_savesLoaded) return;
    setState(() => _loadingSaves = true);
    final res = await ref
        .read(apiClientProvider)
        .get('/auth/me/saves', queryParameters: {'page': 1});
    if (!mounted) return;
    setState(() {
      _loadingSaves = false;
      _savesLoaded = true;
      if (res.success && res.data != null) {
        final list = ((res.data as Map)['saves'] as List?) ?? const [];
        _saves = list
            .map((j) => TutorialModel.fromJson(Map<String, dynamic>.from(j as Map)))
            .toList();
      }
    });
  }

  Future<void> _loadAgreement() async {
    final res = await ref
        .read(apiClientProvider)
        .get('/auth/agreement/status');
    if (!mounted) return;
    if (res.success && res.data is Map) {
      setState(() => _agreementSigned = (res.data as Map)['signed'] == true);
    }
  }

  void _select(_Section s) {
    setState(() => _section = s);
    if (s == _Section.collections) _loadSaves();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final divider = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFECECEC);

    return Row(
      children: [
        SizedBox(width: 280, child: _leftPanel(user, isDark, divider)),
        VerticalDivider(width: 0.5, thickness: 0.5, color: divider),
        Expanded(child: _rightPanel(isDark, divider)),
      ],
    );
  }

  // ── 左栏 ──────────────────────────────────────────────
  Widget _leftPanel(UserModel user, bool isDark, Color divider) {
    final ink = Theme.of(context).textTheme.bodyLarge?.color;
    final muted = isDark ? const Color(0xFF8A8F9E) : const Color(0xFF9AA0A6);
    final isProMax = MembershipUtils.isProMax(user.membership);
    final isPro = MembershipUtils.isPro(user.membership);
    final initial =
        user.username.isNotEmpty ? user.username.characters.first : '?';

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // 头部：头像 + 名字 + handle + 徽章 + 简介
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _avatar(user, initial, isDark),
              const SizedBox(height: 12),
              Text(
                user.username,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: ink,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '@${user.handle ?? user.username}'
                '${(user.occupation != null && user.occupation!.isNotEmpty) ? ' · ${user.occupation}' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: muted),
              ),
              if (user.isFoundingCreator == true || isPro) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    if (user.isFoundingCreator == true)
                      _badge('元老创作者', const Color(0xFF9A6B00),
                          const Color(0xFFFDF0D5)),
                    if (isProMax)
                      _badge('Pro Max', const Color(0xFF6D28D9),
                          const Color(0xFFEDE7FB))
                    else if (isPro)
                      _badge('Pro', const Color(0xFF6D28D9),
                          const Color(0xFFEDE7FB)),
                  ],
                ),
              ],
              if (user.bio != null && user.bio!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  user.bio!,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.6,
                    color: isDark ? const Color(0xFFB8BCC8) : const Color(0xFF555B66),
                  ),
                ),
              ],
            ],
          ),
        ),
        Divider(height: 0.5, thickness: 0.5, color: divider),
        // 统计三列
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              _stat('${_tutorials.length}', '文章', ink, muted),
              _stat('${_tutorials.fold<int>(0, (s, t) => s + t.likes)}', '获赞',
                  ink, muted),
              _stat('${user.followerCount}', '粉丝', ink, muted),
            ],
          ),
        ),
        Divider(height: 0.5, thickness: 0.5, color: divider),
        // 原创协议徽章
        if (_agreementSigned)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF14351F)
                    : const Color(0xFFE7F6EC),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_user_outlined,
                      size: 14, color: Color(0xFF16A34A)),
                  const SizedBox(width: 6),
                  Text(
                    '已签署原创声明协议',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? const Color(0xFF6EE7A0)
                          : const Color(0xFF15803D),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        // 菜单
        _menuLabel('内容', muted),
        _menuItem(Icons.article_outlined, '文章', _Section.articles),
        _menuItem(Icons.menu_book_outlined, 'Notebook', _Section.notebook),
        _menuItem(Icons.bookmark_border, '收藏', _Section.collections),
        _menuLabel('创作', muted),
        _menuItem(Icons.bar_chart, '数据详情', _Section.stats),
        _menuItem(Icons.settings_outlined, '创作设置', _Section.settings),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _avatar(UserModel user, String initial, bool isDark) {
    final url = user.avatar;
    final hasUrl = url != null && url.startsWith('http');
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDark ? const Color(0xFF2A2E3C) : const Color(0xFFDCE3FF),
        image: hasUrl
            ? DecorationImage(image: NetworkImage(url), fit: BoxFit.cover)
            : null,
      ),
      alignment: Alignment.center,
      child: hasUrl
          ? null
          : Text(
              initial,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w500,
                color: _accent,
              ),
            ),
    );
  }

  Widget _badge(String text, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: fg),
      ),
    );
  }

  Widget _stat(String value, String label, Color? ink, Color muted) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: ink)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 10, color: muted)),
        ],
      ),
    );
  }

  Widget _menuLabel(String text, Color muted) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
      child: Text(
        text,
        style: TextStyle(
            fontSize: 10, color: muted, letterSpacing: 0.5),
      ),
    );
  }

  Widget _menuItem(IconData icon, String label, _Section section) {
    final active = _section == section;
    final ink = Theme.of(context).textTheme.bodyLarge?.color;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => _select(section),
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: active
            ? (isDark
                ? _accent.withValues(alpha: 0.15)
                : const Color(0xFFEEF0FF))
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: active ? _accent : ink),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: active ? _accent : ink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 右栏 ──────────────────────────────────────────────
  Widget _rightPanel(bool isDark, Color divider) {
    switch (_section) {
      case _Section.notebook:
        return const NotebookHomeScreen();
      case _Section.stats:
        return const CreatorStatsScreen(showBackButton: false);
      case _Section.settings:
        return const SettingsScreen(showBackButton: false);
      case _Section.collections:
        return _listPane(
          title: '收藏',
          loading: _loadingSaves,
          items: _saves,
          empty: '还没有收藏任何文章',
          isDark: isDark,
          divider: divider,
          showWrite: false,
        );
      case _Section.articles:
        return _listPane(
          title: '文章',
          loading: _loadingArticles,
          items: _tutorials,
          empty: '还没有发布文章',
          isDark: isDark,
          divider: divider,
          showWrite: true,
        );
    }
  }

  Widget _listPane({
    required String title,
    required bool loading,
    required List<TutorialModel> items,
    required String empty,
    required bool isDark,
    required Color divider,
    required bool showWrite,
  }) {
    final ink = Theme.of(context).textTheme.bodyLarge?.color;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 顶栏：标题 + 写文章
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: divider, width: 0.5)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600, color: ink),
                ),
              ),
              if (showWrite)
                GestureDetector(
                  onTap: () => context.push('/publish'),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: isDark
                          ? _accent.withValues(alpha: 0.18)
                          : const Color(0xFFEEF0FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 14, color: _accent),
                        SizedBox(width: 4),
                        Text('写文章',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _accent)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
                  ? Center(
                      child: Text(empty,
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey[400])))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                      itemCount: items.length,
                      itemBuilder: (_, i) => _articleCard(items[i], isDark),
                    ),
        ),
      ],
    );
  }

  Widget _articleCard(TutorialModel t, bool isDark) {
    final ink = Theme.of(context).textTheme.bodyLarge?.color;
    final muted = isDark ? const Color(0xFF8A8F9E) : const Color(0xFF9AA0A6);
    final cardBg = isDark ? const Color(0xFF1C1F2A) : Colors.white;
    final border = isDark ? const Color(0xFF2A2E3C) : const Color(0xFFEDEDED);
    return GestureDetector(
      onTap: () => context.push('/tutorial/${t.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                  color: ink),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                if (t.tags.isNotEmpty) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF262A38)
                          : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(t.tags.first,
                        style: TextStyle(fontSize: 10, color: muted)),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(_dateLabel(t.createdAt),
                    style: TextStyle(fontSize: 11, color: muted)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _cardStat(Icons.visibility_outlined, t.views, muted),
                const SizedBox(width: 12),
                _cardStat(Icons.thumb_up_outlined, t.likes, muted),
                const SizedBox(width: 12),
                _cardStat(Icons.bookmark_border, t.saveCount, muted),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardStat(IconData icon, int n, Color muted) {
    return Row(
      children: [
        Icon(icon, size: 11, color: muted),
        const SizedBox(width: 3),
        Text('$n', style: TextStyle(fontSize: 10, color: muted)),
      ],
    );
  }

  String _dateLabel(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}
