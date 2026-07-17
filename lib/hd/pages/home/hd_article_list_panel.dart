import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/home/providers/home_feed_provider.dart';
import '../../../shared/models/tutorial_model.dart';
import '../../state/hd_home_state.dart';

const _primary = Color(0xFF6366F1);

// HD 左侧 280px 内容列表面板：搜索框 + 推荐/关注/最新 Tab + 文章卡片。
// 复用现成 homeFeedProvider（GET /auth/tutorials?status=published）。
// 推荐=后端默认序（created_at DESC）；最新=同列表客户端按时间再排；关注=手机端
// 是 fan-out 拉关注作者作品合成（深绑 State，抽取是后续任务），阶段2 先占位。
// 点卡片 → homeSelectedArticleProvider=id，中间/右侧面板随之更新
class HdArticleListPanel extends ConsumerStatefulWidget {
  const HdArticleListPanel({super.key});

  @override
  ConsumerState<HdArticleListPanel> createState() => _HdArticleListPanelState();
}

class _HdArticleListPanelState extends ConsumerState<HdArticleListPanel> {
  int _tab = 0; // 0 推荐 / 1 关注 / 2 最新
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panelBg = isDark
        ? Theme.of(context).cardColor
        : const Color(0xFFFAFAF8);
    final divider = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFE5E5EA);

    final feed = ref.watch(homeFeedProvider);
    final selectedId = ref.watch(homeSelectedArticleProvider);

    return Container(
      width: 280,
      color: panelBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          _searchBox(isDark),
          _tabBar(isDark),
          Divider(height: 0.5, thickness: 0.5, color: divider),
          Expanded(child: _list(feed, selectedId, isDark)),
        ],
      ),
    );
  }

  Widget _searchBox(bool isDark) {
    final fill = isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white;
    final border = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFE5E5EA);
    final ink = isDark ? const Color(0xFFE6E6E6) : const Color(0xFF1A1A1A);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: SizedBox(
        height: 36,
        child: TextField(
          style: TextStyle(fontSize: 13, color: ink),
          onChanged: (v) => setState(() => _search = v.trim()),
          decoration: InputDecoration(
            hintText: '搜索文章、问题…',
            hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF999999)),
            prefixIcon: const Icon(
              Icons.search,
              size: 16,
              color: Color(0xFF999999),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 34),
            filled: true,
            fillColor: fill,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: border, width: 0.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: border, width: 0.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _primary, width: 1),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabBar(bool isDark) {
    final ink = isDark ? const Color(0xFFF0F2F8) : const Color(0xFF1A1A1A);
    final muted = isDark ? const Color(0xFF888C9E) : const Color(0xFF999999);
    Widget tab(int i, String label) {
      final active = _tab == i;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _tab = i),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: active ? FontWeight.w700 : FontWeight.w400,
              color: active ? ink : muted,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(children: [tab(0, '推荐'), tab(1, '关注'), tab(2, '最新')]),
    );
  }

  Widget _list(HomeFeedState feed, String? selectedId, bool isDark) {
    final muted = isDark ? const Color(0xFF888C9E) : const Color(0xFF999999);

    // 关注 tab——手机端 fan-out 合成流深绑 State，阶段2 先占位
    if (_tab == 1) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '关注流即将上线',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: muted),
          ),
        ),
      );
    }

    if (feed.isLoading && feed.filtered.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    var items = feed.filtered;
    if (_tab == 2) {
      // 最新：同一份真实数据客户端按 createdAt 再排一遍
      items = [...items]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      items = items.where((t) => t.title.toLowerCase().contains(q)).toList();
    }

    if (items.isEmpty) {
      return Center(
        child: Text(
          _search.isNotEmpty ? '没有匹配的文章' : '暂无内容',
          style: TextStyle(fontSize: 13, color: muted),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: items.length,
      itemBuilder: (context, i) =>
          _card(items[i], items[i].id == selectedId, isDark),
    );
  }

  Widget _card(TutorialModel t, bool selected, bool isDark) {
    final ink = isDark ? const Color(0xFFE6E6E6) : const Color(0xFF1A1A1A);
    final muted = isDark ? const Color(0xFF888C9E) : const Color(0xFF999999);
    final divider = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : const Color(0xFFEDEDED);
    final tag = t.tags.isNotEmpty ? t.tags.first : null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => ref.read(homeSelectedArticleProvider.notifier).state = t.id,
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? _primary.withValues(alpha: isDark ? 0.14 : 0.06)
              : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: selected ? _primary : Colors.transparent,
              width: 3,
            ),
            bottom: BorderSide(color: divider, width: 0.5),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(13, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.35,
                color: ink,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (tag != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? _primary.withValues(alpha: 0.16)
                          : const Color(0xFFEEF0FF),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      tag,
                      style: const TextStyle(fontSize: 10, color: _primary),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    t.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.remove_red_eye_outlined, size: 12, color: muted),
                const SizedBox(width: 3),
                Text(
                  _fmt(t.views),
                  style: TextStyle(fontSize: 11, color: muted),
                ),
                const SizedBox(width: 10),
                Icon(Icons.favorite_border, size: 12, color: muted),
                const SizedBox(width: 3),
                Text(
                  _fmt(t.likes),
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';
}
