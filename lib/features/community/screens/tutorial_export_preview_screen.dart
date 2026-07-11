import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

const _primary = Color(0xFF6366F1);

// 用 printing 包自带的 PdfPreview 控件直接渲染真实生成的 PDF 字节——
// 所见即所得，不会跟实际导出结果走样（不是自己用 Container/Text 仿一份
// "看起来像 PDF" 的卡片，那样两套排版逻辑各改各的迟早会不一致）。
// 关掉包自带的操作栏（打印/分享按钮），自己按截图参考做一个更简洁的
// 顶部栏（返回 + 标题 + 分享），分享走 Printing.sharePdf 调起系统分享面板
class TutorialExportPreviewScreen extends StatelessWidget {
  final Uint8List bytes;
  final String title;

  const TutorialExportPreviewScreen({
    super.key,
    required this.bytes,
    required this.title,
  });

  Future<void> _share() {
    return Printing.sharePdf(bytes: bytes, filename: '$title.pdf');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 4),
            Text(
              'PDF 预览',
              style: TextStyle(fontSize: 11, color: Colors.grey[400]),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      child: const Icon(Icons.arrow_back_ios, size: 16),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '预览',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _share,
                    child: const SizedBox(
                      width: 34,
                      height: 34,
                      child: Icon(Icons.ios_share, size: 20, color: _primary),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 12, thickness: 0.5),
            Expanded(
              child: PdfPreview(
                build: (format) async => bytes,
                initialPageFormat: PdfPageFormat.a4,
                useActions: false,
                canChangePageFormat: false,
                canChangeOrientation: false,
                canDebug: false,
                allowPrinting: false,
                allowSharing: false,
                scrollViewDecoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
