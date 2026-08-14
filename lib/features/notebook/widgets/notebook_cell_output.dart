import 'dart:convert';
import '../../../core/theme/app_colors.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/widgets/ai_content_renderer.dart';

// 输出区：文字=绿左线浅绿底 / 图片=浅紫底 / 错误=红左线。从
// notebook_editor_screen.dart 抽出来，纯展示，不持有状态
Widget buildNotebookCellOutput(
  String output,
  String? type,
  bool isDark, {
  VoidCallback? onSaveChart,
  // 小梦 AI 回复区「应用」到编辑器的回调（非空才显示复制/应用按钮）
  VoidCallback? onApplyAi,
}) {
  if (type == 'image') {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF13131F) : AppColors.primaryLight,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 限高 280、宽度自适应：按比例缩放（contain）看全貌，不撑高整个 Cell
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxHeight: 280,
              maxWidth: double.infinity,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                base64Decode(output),
                fit: BoxFit.contain,
                errorBuilder: (c, e, s) => Text(
                  '图片解码失败',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ),
            ),
          ),
          // 保存图表——存/分享 PNG（matplotlib 图或图片块都可用）
          if (onSaveChart != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: onSaveChart,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.success.withValues(alpha: 0.18)
                        : const Color(0xFFE8F8F0),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.download_outlined,
                        size: 13,
                        color: AppColors.success,
                      ),
                      SizedBox(width: 4),
                      Text(
                        '保存图表',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
  // 小梦 AI 结果——紫色左线+浅紫底+「✨ 小梦」头，跟真实代码运行的绿色
  // 「✓ 输出」区分开，不让人误以为是运行结果
  if (type == 'ai') {
    const accent = AppColors.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? accent.withValues(alpha: 0.08)
            : const Color(0xFFF3F2FF),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
        border: const Border(left: BorderSide(color: accent, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome, size: 11, color: accent),
              SizedBox(width: 4),
              Text(
                '小梦',
                style: TextStyle(
                  fontSize: 9,
                  color: accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 限高 200 + 内部滚动：长 AI 输出在框内滚，不撑高整个 Cell。
          // 用 AiContentRenderer 正确渲染 Markdown/代码块/公式，不再是生的 Text
          _BoundedScroll(
            maxHeight: 200,
            child: AiContentRenderer(content: output, isDark: isDark),
          ),
          // 复制 / 应用——应用会把 AI 回复落到编辑器（代码块替换当前 cell，
          // 纯文字则插入新 markdown cell）
          if (onApplyAi != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: output)),
                  icon: const Icon(Icons.copy, size: 14, color: accent),
                  label: const Text(
                    '复制',
                    style: TextStyle(fontSize: 12, color: accent),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: onApplyAi,
                  icon: const Icon(Icons.check, size: 14),
                  label: const Text('应用'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
  final isError = type == 'error';
  final accent = isError ? const Color(0xFFDC2626) : AppColors.success;
  final lightBg = isError ? const Color(0xFFFEF2F2) : const Color(0xFFF0FFF5);
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: isDark ? accent.withValues(alpha: 0.06) : lightBg,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
      border: Border(left: BorderSide(color: accent, width: 2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isError ? '✗ 错误' : '✓ 输出',
          style: TextStyle(
            fontSize: 9,
            color: accent,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 3),
        // 限高 200 + 内部滚动：长文本/报错栈在框内滚，不撑高整个 Cell
        _BoundedScroll(
          maxHeight: 200,
          child: Text(
            output,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              height: 1.5,
              color: isDark ? const Color(0xFFB0B0C0) : const Color(0xFF555555),
            ),
          ),
        ),
      ],
    ),
  );
}

// 限高 + Scrollbar + SingleChildScrollView 的通用容器。放成 StatefulWidget 是
// 为了持有并释放自己的 ScrollController（Scrollbar 和 SingleChildScrollView 共用
// 同一个 controller，避免抓到页面的 PrimaryScrollController 冲突）
class _BoundedScroll extends StatefulWidget {
  final double maxHeight;
  final Widget child;
  const _BoundedScroll({required this.maxHeight, required this.child});

  @override
  State<_BoundedScroll> createState() => _BoundedScrollState();
}

class _BoundedScrollState extends State<_BoundedScroll> {
  final _ctrl = ScrollController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      child: Scrollbar(
        controller: _ctrl,
        child: SingleChildScrollView(
          controller: _ctrl,
          child: widget.child,
        ),
      ),
    );
  }
}
