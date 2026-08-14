import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'package:go_router/go_router.dart';

import '../services/tutorial_export_service.dart';

const _primary = AppColors.primary;

void showTutorialExportSheet(
  BuildContext context, {
  required Map<String, dynamic> tutorial,
  required List<dynamic> blocks,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _ExportSheet(tutorial: tutorial, blocks: blocks),
  );
}

class _ExportSheet extends StatefulWidget {
  final Map<String, dynamic> tutorial;
  final List<dynamic> blocks;
  const _ExportSheet({required this.tutorial, required this.blocks});

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  String _format = 'pdf';
  String _style = 'clean';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 32),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 3,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '导出文章',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '选择格式和样式',
            style: TextStyle(fontSize: 12, color: Colors.grey[400]),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _FormatOpt(
                icon: Icons.picture_as_pdf,
                iconColor: const Color(0xFFEF4444),
                bgColor: const Color(0xFFFEE2E2),
                name: 'PDF',
                desc: '可打印分享',
                selected: _format == 'pdf',
                isDark: isDark,
                onTap: () => setState(() => _format = 'pdf'),
              ),
              const SizedBox(width: 8),
              _FormatOpt(
                icon: Icons.code,
                iconColor: _primary,
                bgColor: AppColors.primaryLight,
                name: 'Markdown',
                desc: '纯文本格式',
                selected: _format == 'md',
                isDark: isDark,
                onTap: () => setState(() => _format = 'md'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_format == 'pdf') ...[
            Text(
              '版面样式',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _StyleOpt(
                  name: '简洁',
                  color: const Color(0xFFFAFAFA),
                  selected: _style == 'clean',
                  onTap: () => setState(() => _style = 'clean'),
                ),
                const SizedBox(width: 8),
                _StyleOpt(
                  name: '深色',
                  color: const Color(0xFF1A1A2E),
                  selected: _style == 'dark',
                  onTap: () => setState(() => _style = 'dark'),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () {
                // 弹窗关掉之后原来的 context 还留着用来跳路由/弹错误提示，
                // 但 ScaffoldMessenger 得在 pop 之前先取出来——pop 之后这个
                // sheet 自己的 context 很快会被销毁，再用它找 messenger 不安全
                final messenger = ScaffoldMessenger.of(context);
                final router = GoRouter.of(context);
                Navigator.pop(context);
                if (_format == 'pdf') {
                  router.push(
                    '/tutorial/export/progress',
                    extra: {
                      'tutorial': widget.tutorial,
                      'blocks': widget.blocks,
                      'style': _style,
                    },
                  );
                } else {
                  shareTutorialAsMarkdown(widget.tutorial, widget.blocks).catchError((
                    e,
                  ) {
                    messenger.showSnackBar(SnackBar(content: Text('导出失败：$e')));
                  });
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                '开始导出',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FormatOpt extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final String name;
  final String desc;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  const _FormatOpt({
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.name,
    required this.desc,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? (isDark ? _primary.withValues(alpha: 0.15) : AppColors.primaryLight)
                : (isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8F8FF)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? _primary
                  : (isDark ? Colors.white12 : const Color(0xFFEBEBEB)),
              width: selected ? 1.5 : 0.5,
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(height: 6),
              Text(
                name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              Text(
                desc,
                style: TextStyle(fontSize: 10, color: Colors.grey[400]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StyleOpt extends StatelessWidget {
  final String name;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _StyleOpt({
    required this.name,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? _primary : const Color(0xFFEBEBEB),
              width: selected ? 1.5 : 0.5,
            ),
          ),
          child: Column(
            children: [
              Text(
                name,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                height: 32,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: const Color(0xFFE0E0E0),
                    width: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
