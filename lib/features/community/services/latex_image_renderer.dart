import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_math_fork/flutter_math.dart';

// 这个文件专门负责"把 latex 公式离屏渲染成 PNG"，故意跟
// tutorial_export_service.dart（pdf 世界）分开：printing 会把 pdf 的 widget
// 名字（Text/Container/Border…）不带前缀地导出，跟 flutter/material 大面积
// 撞名。两边放一个文件里会导致这些名字全部歧义，所以拆开——这里只 import
// flutter，不碰 pdf。

String _latexBody(String c) => c
    .replaceAll(r'$$', '')
    .replaceAll(r'$', '')
    .replaceAll(r'\[', '')
    .replaceAll(r'\]', '')
    .replaceAll(r'\(', '')
    .replaceAll(r'\)', '')
    .trim();

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
  final formulas = blocks
      .whereType<Map>()
      .where((b) => b['type'] == 'latex')
      .map((b) => b['content'] as String? ?? '')
      .where((c) => c.trim().isNotEmpty)
      .toSet();
  if (formulas.isEmpty) return {};

  // 这个函数是从 initState 里同步链路调过来的（导出进度页一 initState
  // 就发起生成），这时当前这一帧的 build 还没走完，Overlay.of(...).insert()
  // 会撞上"setState()/markNeedsBuild() called during build"——先等当前帧
  // 结束，再去动 Overlay，跟下面等公式截图完成用的是同一个安全点写法
  await WidgetsBinding.instance.endOfFrame;
  if (!context.mounted) return {};

  final overlayState = Overlay.of(context, rootOverlay: true);
  final glyphColor = isDark ? const Color(0xFFFFFFFF) : const Color(0xFF4F46E5);
  final result = <String, Uint8List>{};

  // 第二道防线：调用方已改成在 addPostFrameCallback 里启动（脱离 build
  // 阶段）；这里再等一帧确保万一有别的调用方在 build 期调用，也不会在
  // build 阶段往 Overlay 里 insert，触发
  // "setState()/markNeedsBuild() called during build"
  await WidgetsBinding.instance.endOfFrame;

  for (final raw in formulas) {
    final body = _latexBody(raw);
    if (body.isEmpty) continue;
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
              body,
              mathStyle: MathStyle.display,
              textStyle: TextStyle(fontSize: 22, color: glyphColor),
              onErrorFallback: (_) => Text(
                body,
                style: TextStyle(fontSize: 15, color: glyphColor),
              ),
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
