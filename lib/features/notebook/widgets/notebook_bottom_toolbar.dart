import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';

// 底部浮动工具栏：文字/代码/公式/图片/SQL/更多。从
// notebook_editor_screen.dart 抽出来——纯展示+回调，具体每个 type 点了
// 该做什么（新建 cell / 打开相册 / 打开更多语言 sheet）由父级决定
const _toolbarItems = [
  (Icons.title, '文字', 'markdown'),
  (Icons.code, '代码', 'python'),
  (Icons.functions, '公式', 'latex'),
  (Icons.image_outlined, '图片', 'image'),
  (Icons.bar_chart_outlined, '可视化', 'visualization'),
  (Icons.storage_outlined, 'SQL', 'sql'),
  (Icons.more_horiz, '更多', 'more'),
];

class NotebookBottomToolbar extends StatelessWidget {
  final bool isDark;
  // 当前选中 cell 对应的工具类型（markdown/latex/sql/image/python/null）——
  // 由父级根据 _activeIndex 算好传进来，这个 widget 不持有 cell 列表状态
  final String? activeType;
  final void Function(String type) onTap;
  // 右侧「导入数据」紫色按钮——选 CSV/Excel/JSON/TXT 文件，解析后 base64
  // 注入内核并自动生成数据集 cell（见 notebook_editor_screen._openFileImport）
  final VoidCallback? onImport;

  const NotebookBottomToolbar({
    super.key,
    required this.isDark,
    required this.activeType,
    required this.onTap,
    this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      // 底部外边距收窄（12→4）：工具栏本就浮在外层 SafeArea 的 home 指示条
      // 安全区之上，再叠 12px 显得下方留白过多。收到 4，把腾出的高度让给
      // 上方的 Cell 画布，同时保留 SafeArea 对 home 指示条的避让
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF17171F) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFEBEBEB),
          width: 0.5,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          ..._toolbarItems.map((item) {
            final isActive = activeType == item.$3;
            final fg = isActive
                ? (isDark ? const Color(0xFFE0E2F0) : const Color(0xFF1A1A1A))
                : (isDark ? const Color(0xFF444444) : const Color(0xFFCCCCCC));
            return Expanded(
              child: GestureDetector(
                onTap: () => onTap(item.$3),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: isActive
                        ? (isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : const Color(0xFFF5F5F5))
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(item.$1, size: 19, color: fg),
                      const SizedBox(height: 2),
                      Text(item.$2, style: TextStyle(fontSize: 9, color: fg)),
                    ],
                  ),
                ),
              ),
            );
          }),
          if (onImport != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onImport,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.upload_file_outlined,
                      size: 14,
                      color: Colors.white,
                    ),
                    SizedBox(width: 4),
                    Text(
                      '导入数据',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// "更多"点开的语言选择sheet——JavaScript/R/Julia/HTML + 文件导入入口
void showMoreLanguagesSheet(
  BuildContext context, {
  required void Function(String type) onPick,
  required VoidCallback onImport,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      decoration: BoxDecoration(
        color: Theme.of(ctx).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final t in const [
              ('javascript', 'JavaScript', Icons.javascript),
              ('r', 'R', Icons.bar_chart),
              ('julia', 'Julia', Icons.change_history),
              ('html', 'HTML', Icons.html),
            ])
              ListTile(
                tileColor: Colors.transparent,
                leading: Icon(t.$3, size: 20),
                title: Text(t.$2),
                onTap: () {
                  Navigator.pop(ctx);
                  onPick(t.$1);
                },
              ),
            ListTile(
              tileColor: Colors.transparent,
              leading: const Icon(Icons.upload_file, size: 20),
              title: Text(AppLocalizations.of(ctx)!.import),
              onTap: () {
                Navigator.pop(ctx);
                onImport();
              },
            ),
          ],
        ),
      ),
    ),
  );
}
