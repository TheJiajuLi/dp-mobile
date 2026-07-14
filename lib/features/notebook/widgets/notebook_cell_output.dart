import 'dart:convert';

import 'package:flutter/material.dart';

// 输出区：文字=绿左线浅绿底 / 图片=浅紫底 / 错误=红左线。从
// notebook_editor_screen.dart 抽出来，纯展示，不持有状态
Widget buildNotebookCellOutput(String output, String? type, bool isDark) {
  if (type == 'image') {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF13131F) : const Color(0xFFEEF0FF),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
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
    );
  }
  final isError = type == 'error';
  final accent = isError ? const Color(0xFFDC2626) : const Color(0xFF16A34A);
  final lightBg = isError ? const Color(0xFFFEF2F2) : const Color(0xFFF0FFF5);
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: isDark ? accent.withValues(alpha: 0.06) : lightBg,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
      border: Border(left: BorderSide(color: accent, width: 2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isError ? '✗ 错误' : '✓ 输出',
          style: TextStyle(fontSize: 9, color: accent, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 3),
        Text(
          output,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            height: 1.5,
            color: isDark ? const Color(0xFFB0B0C0) : const Color(0xFF555555),
          ),
        ),
      ],
    ),
  );
}
