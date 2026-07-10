import 'package:flutter/material.dart';

// 这个 App 里"列表型卡片"的标准做法——整块圆角大卡片，内容用 Divider
// 分隔每一行，不是每一行单独套一层圆角（消息主页 _PreviewCard、通知页
// _notificationGroupCard、群组列表卡片都是同一套配方）。私信/好友这两个
// 列表之前各自手写了一份（好友甚至整个没做，是贴边的纯 ListTile 平铺），
// 抽成共享组件，往后这类列表都从这一个地方改，不会散成好几份不一致的写法
class RoundedListCard extends StatelessWidget {
  final List<Widget> children;
  final double dividerIndent;
  final EdgeInsetsGeometry margin;

  const RoundedListCard({
    super.key,
    required this.children,
    this.dividerIndent = 68,
    this.margin = const EdgeInsets.symmetric(horizontal: 16),
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(
          Divider(
            height: 0.5,
            indent: dividerIndent,
            color: Theme.of(context).dividerColor,
          ),
        );
      }
      rows.add(children[i]);
    }
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Column(children: rows),
      ),
    );
  }
}
