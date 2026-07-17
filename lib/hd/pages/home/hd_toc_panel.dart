import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/community/providers/article_provider.dart';
import '../../../features/community/widgets/article_body_view.dart';

const _primary = Color(0xFF6366F1);

// 目录 heading 列表——右侧 180 面板 + 中窄屏「目录」浮层复用同一份。watch
// articleProvider(id).toc 渲染层级目录，ValueListenableBuilder 跟 scroll-spy
// 的 activeHeadingIndex 实时高亮当前章节，点击 controller.jumpToHeading 跳转
class HdTocList extends ConsumerWidget {
  final String tutorialId;
  final ArticleBodyController controller;
  final VoidCallback? onItemTap; // 浮层里点完关闭；侧面板不传
  const HdTocList({
    super.key,
    required this.tutorialId,
    required this.controller,
    this.onItemTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? const Color(0xFFE6E6E6) : const Color(0xFF1A1A1A);
    final muted = isDark ? const Color(0xFF888C9E) : const Color(0xFF999999);
    final toc = ref.watch(articleProvider(tutorialId).select((s) => s.toc));

    if (toc.isEmpty) {
      return Center(
        child: Text('暂无目录', style: TextStyle(fontSize: 12, color: muted)),
      );
    }
    return ValueListenableBuilder<int>(
      valueListenable: controller.activeHeadingIndex,
      builder: (context, active, _) {
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: toc.length,
          itemBuilder: (context, i) {
            final item = toc[i];
            final level = (item['level'] as int?) ?? 2;
            final text = item['text'] as String? ?? '';
            final isActive = i == active;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                controller.jumpToHeading(i);
                onItemTap?.call();
              },
              child: Container(
                decoration: BoxDecoration(
                  color: isActive
                      ? _primary.withValues(alpha: isDark ? 0.16 : 0.08)
                      : Colors.transparent,
                  border: Border(
                    left: BorderSide(
                      color: isActive ? _primary : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                padding: EdgeInsets.fromLTRB(10.0 + (level - 1) * 12, 7, 8, 7),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          fontWeight: isActive
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: isActive ? _primary : ink,
                        ),
                      ),
                    ),
                    if (level > 1) ...[
                      const SizedBox(width: 4),
                      Text(
                        'H$level',
                        style: TextStyle(fontSize: 9, color: muted),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// 右侧 180px 目录面板：目录标题 + 目录列表 + 参考文献（P3 占位）
class HdTocPanel extends StatelessWidget {
  final String tutorialId;
  final ArticleBodyController controller;
  const HdTocPanel({
    super.key,
    required this.tutorialId,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panelBg = isDark
        ? Theme.of(context).scaffoldBackgroundColor
        : const Color(0xFFF5F5F7);
    final ink = isDark ? const Color(0xFFE6E6E6) : const Color(0xFF1A1A1A);
    final muted = isDark ? const Color(0xFF888C9E) : const Color(0xFF999999);
    final divider = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFE5E5EA);

    return Container(
      width: 180,
      color: panelBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
            child: Text(
              '目录',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
          ),
          Expanded(
            child: HdTocList(tutorialId: tutorialId, controller: controller),
          ),
          Divider(height: 0.5, thickness: 0.5, color: divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Text(
              '参考文献',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
          ),
          // 参考文献——后端暂无 references 字段，P3 再接（阶段1 已确认）
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
            child: Text('暂无', style: TextStyle(fontSize: 12, color: muted)),
          ),
        ],
      ),
    );
  }
}
