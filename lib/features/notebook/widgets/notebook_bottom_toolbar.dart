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
  (Icons.storage_outlined, 'SQL', 'sql'),
  (Icons.more_horiz, '更多', 'more'),
];

class NotebookBottomToolbar extends StatelessWidget {
  final bool isDark;
  // 当前选中 cell 对应的工具类型（markdown/latex/sql/image/python/null）——
  // 由父级根据 _activeIndex 算好传进来，这个 widget 不持有 cell 列表状态
  final String? activeType;
  final void Function(String type) onTap;

  const NotebookBottomToolbar({
    super.key,
    required this.isDark,
    required this.activeType,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
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
        children: _toolbarItems.map((item) {
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
        }).toList(),
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
    builder: (ctx) => SafeArea(
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
              leading: Icon(t.$3, size: 20),
              title: Text(t.$2),
              onTap: () {
                Navigator.pop(ctx);
                onPick(t.$1);
              },
            ),
          ListTile(
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
  );
}
