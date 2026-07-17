import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/community/community_provider.dart';
import '../home/hd_article_card.dart';

const _primary = Color(0xFF6366F1);

// 发现列表面板的标签——跟手机社区页同一组固定分类（community_screen._tags）
const _discoverTags = [
  '全部',
  'Python',
  '数据分析',
  '机器学习',
  '可视化',
  'LaTeX',
  '统计学',
  '数学建模',
];

// HD 发现列表面板：搜索框 + 标签筛选 chip + 文章卡片。复用 communityProvider
// （GET /auth/tutorials，按 tag 过滤）。点标签 → setTag；点卡片 → 写
// selectedProvider（发现工作区自己的选中态）。宽度由外层工作区控制
class HdDiscoverListPanel extends ConsumerStatefulWidget {
  final StateProvider<String?> selectedProvider;
  const HdDiscoverListPanel({super.key, required this.selectedProvider});

  @override
  ConsumerState<HdDiscoverListPanel> createState() =>
      _HdDiscoverListPanelState();
}

class _HdDiscoverListPanelState extends ConsumerState<HdDiscoverListPanel> {
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

    final community = ref.watch(communityProvider);
    final selectedId = ref.watch(widget.selectedProvider);

    return Container(
      color: panelBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          _searchBox(isDark),
          _tagChips(community.selectedTag, isDark),
          Divider(height: 0.5, thickness: 0.5, color: divider),
          Expanded(child: _list(community, selectedId, isDark)),
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

  Widget _tagChips(String selectedTag, bool isDark) {
    final muted = isDark ? const Color(0xFFB8BCCB) : const Color(0xFF666666);
    return SizedBox(
      height: 34,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: _discoverTags.length,
        itemBuilder: (context, i) {
          final tag = _discoverTags[i];
          final active = selectedTag == tag;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => ref.read(communityProvider.notifier).setTag(tag),
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: active
                      ? _primary.withValues(alpha: isDark ? 0.20 : 0.10)
                      : (isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.white),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color: active
                        ? _primary.withValues(alpha: 0.4)
                        : (isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : const Color(0xFFE5E5EA)),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  tag,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    color: active ? _primary : muted,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _list(CommunityState community, String? selectedId, bool isDark) {
    final muted = isDark ? const Color(0xFF888C9E) : const Color(0xFF999999);

    if (community.isLoading && community.filtered.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    var items = community.filtered; // 已按 selectedTag 过滤
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
