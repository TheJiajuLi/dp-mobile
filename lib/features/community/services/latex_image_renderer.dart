import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../../shared/utils/latex_utils.dart';

// 这个文件专门负责"把 latex 公式离屏渲染成 PNG"，故意跟
// tutorial_export_service.dart（pdf 世界）分开：printing 会把 pdf 的 widget
// 名字（Text/Container/Border…）不带前缀地导出，跟 flutter/material 大面积
// 撞名。两边放一个文件里会导致这些名字全部歧义，所以拆开——这里只 import
// flutter，不碰 pdf。

/// 把每个 latex 公式用 flutter_math_fork 排版成透明底 PNG，供 PDF 以真实公式
/// 嵌入——pdf 包没有 TeX 引擎，这是唯一能得到真排版的路子。必须在有 Overlay
/// 的 UI 上下文里调用（导出进度页 initState 时），靠一个屏外
/// RepaintBoundary.toImage() 截图。返回 {原始 content 字符串: png 字节}，
/// PDF 侧按这个 key 查图；查不到就退回纯文本斜体。
Future<Map<String, Uint8List>> renderTutorialLatexImages(
  BuildContext context,
  List<dynamic> blocks, {
  required bool isDark,
}) async {
  // 收集所有要离屏渲染成 PNG 的公式：
  //  · latex 块整块就是一条公式（key = 整块 content）
  //  · text/heading/callout 块里的行内 $...$ / \(...\) / \[...\]（key = 含定界
  //    符原文，跟渲染端 splitInlineLatex 出来的一致）
  // 分开收集「块级公式」和「行内公式」——两者要用不同排版：块级 display（大、
  // 独占一行），行内 text（紧凑、跟正文一个量级）。混在一起统一 display+22 会
  // 让行内的 \mathbf{x} 这类比周围正文大一圈
  final blockFormulas = <String>{};
  final inlineFormulas = <String>{};
  for (final b in blocks.whereType<Map>()) {
    final type = b['type'] as String? ?? 'text';
    final content = b['content'] as String? ?? '';
    if (content.trim().isEmpty) continue;
    if (type == 'latex') {
      blockFormulas.add(content);
    } else if (type == 'text' || type == 'heading' || type == 'callout') {
      for (final seg in splitInlineLatex(content)) {
        if (seg.isFormula) inlineFormulas.add(seg.raw);
      }
    }
  }
  final allFormulas = {...blockFormulas, ...inlineFormulas};
  if (allFormulas.isEmpty) return {};

  final overlayState = Overlay.of(context, rootOverlay: true);
  // PDF 是白底纸张——公式用黑色（原来浅色分支是品牌紫 #4F46E5，导出后公式
  // 全是紫的）。深色 PDF 才用白
  final glyphColor = isDark ? const Color(0xFFFFFFFF) : const Color(0xFF1A1A1A);
  final result = <String, Uint8List>{};

  // 第二道防线：调用方已改成在 addPostFrameCallback 里启动（脱离 build
  // 阶段）；这里再等一帧确保万一有别的调用方在 build 期调用，也不会在
  // build 阶段往 Overlay 里 insert，触发
  // "setState()/markNeedsBuild() called during build"。等完这一帧后
  // 页面也可能已经被用户取消退出了，先判一次 mounted 再继续
  await WidgetsBinding.instance.endOfFrame;
  if (!context.mounted) return {};

  for (final raw in allFormulas) {
    final body = latexInnerBody(raw);
    if (body.isEmpty) continue;
    // 块级公式用 display+较大字号；行内公式用 text 模式+较小字号，跟正文一个
    // 量级，避免 \mathbf 等粗体字比周围文字大一圈
    final isBlock = blockFormulas.contains(raw);
    final boundaryKey = GlobalKey();
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        // 挪到屏外——仍会走绘制流程，RepaintBoundary 照样能截到，
        // 但用户在导出进度页上看不到闪一下
        left: -10000,
        top: 0,
        child: Material(
          type: MaterialType.transparency,
          child: RepaintBoundary(
            key: boundaryKey,
            child: Math.tex(
              preprocessLatex(body),
              mathStyle: isBlock ? MathStyle.display : MathStyle.text,
              textStyle: TextStyle(
                fontSize: isBlock ? 20 : 15,
                color: glyphColor,
              ),
              onErrorFallback: (_) =>
                  Text(body, style: TextStyle(fontSize: 15, color: glyphColor)),
            ),
          ),
        ),
      ),
    );
    overlayState.insert(entry);
    try {
      // 等公式完成布局+绘制；偶发首帧还没挂上时再多等一帧
      await WidgetsBinding.instance.endOfFrame;
      if (boundaryKey.currentContext == null) {
        await WidgetsBinding.instance.endOfFrame;
      }
      final obj = boundaryKey.currentContext?.findRenderObject();
      if (obj is RenderRepaintBoundary) {
        final image = await obj.toImage(pixelRatio: 3.0);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        if (data != null) result[raw] = data.buffer.asUint8List();
      }
    } catch (_) {
      // 单个公式截图失败就跳过，PDF 侧退化成文字，不影响整篇导出
    } finally {
      entry.remove();
    }
  }
  return result;
}
