import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/home/providers/home_feed_provider.dart';
import 'hd_article_card.dart';

const _primary = AppColors.primary;

// HD 左侧内容列表面板：搜索框 + 推荐/关注/最新 Tab + 文章卡片。复用现成
// homeFeedProvider（GET /auth/tutorials?status=published）。推荐=后端默认序
// （created_at DESC）；最新=同列表客户端按时间再排；关注=手机端是 fan-out 拉
// 关注作者作品合成（深绑 State，抽取是后续任务），先占位。点卡片 → 写
// selectedProvider（由 HdReaderWorkspace 传入，首页/发现各一个），中间/右侧
// 面板随之更新。宽度由外层工作区控制（多栏 280 / 窄屏全宽），这里不写死
class HdArticleListPanel extends ConsumerStatefulWidget {
  final StateProvider<String?> selectedProvider;
  const HdArticleListPanel({super.key, required this.selectedProvider});

  @override
  ConsumerState<HdArticleListPanel> createState() => _HdArticleListPanelState();
}

class _HdArticleListPanelState extends ConsumerState<HdArticleListPanel> {
  // 0 推荐 / 1 最新。关注流（fan-out 合成，深绑 State）还没做好，先不显示
  // 这个 tab，等做好再加回来——不占一个「即将上线」的空位
  int _tab = 0;
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
    final selectedId = ref.watch(widget.selectedProvider);

    return Container(
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
      child: Row(children: [tab(0, '推荐'), tab(1, '最新')]),
    );
  }

  Widget _list(HomeFeedState feed, String? selectedId, bool isDark) {
    final muted = isDark ? const Color(0xFF888C9E) : const Color(0xFF999999);

    if (feed.isLoading && feed.filtered.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    var items = feed.filtered;
    if (_tab == 1) {
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
      itemBuilder: (context, i) => HdArticleCard(
        t: items[i],
        selected: items[i].id == selectedId,
        onTap: () =>
            ref.read(widget.selectedProvider.notifier).state = items[i].id,
      ),
    );
  }
}
