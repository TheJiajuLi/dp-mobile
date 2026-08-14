import 'dart:async';
import '../../../core/theme/app_colors.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/latex_image_renderer.dart';
import '../services/tutorial_export_service.dart';

const _primary = AppColors.primary;

// 真实 PDF 生成就是 buildTutorialPdfBytes 一次同步调用，没有"解析/渲染
// 公式/代码高亮/排版"这四个真实可观测的阶段——这四步是定时模拟的视觉
// 反馈，不是真实进度信号。真实生成在后台并行跑，动画播完 4 步后如果
// 生成还没完成会等它，两者都好了才跳转，不会出现"看着显示完成、其实
// 文件还没生成好"的情况
class TutorialExportProgressScreen extends StatefulWidget {
  final Map<String, dynamic> tutorial;
  final List<dynamic> blocks;
  final String style;

  const TutorialExportProgressScreen({
    super.key,
    required this.tutorial,
    required this.blocks,
    required this.style,
  });

  @override
  State<TutorialExportProgressScreen> createState() =>
      _TutorialExportProgressScreenState();
}

class _TutorialExportProgressScreenState
    extends State<TutorialExportProgressScreen> {
  static const _steps = ['解析内容', '渲染公式', '代码高亮', '排版输出'];

  int _step = 0;
  bool _cancelled = false;
  Timer? _timer;
  Future<Uint8List>? _generateFuture;

  @override
  void initState() {
    super.initState();
    // 关键：不要在 initState（build 阶段）里同步启动 _generate——它会往
    // Overlay 里插一层离屏公式渲染，而在 build 阶段动 Overlay 会抛
    // "setState()/markNeedsBuild() called during build"。推到首帧构建
    // 结束后再启动，此刻框架已脱离 build 阶段，插 Overlay 安全
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _generateFuture ??= _generate();
    });
    _timer = Timer.periodic(const Duration(milliseconds: 600), _onTick);
  }

  // 先在当前 UI 上下文（有 Overlay）把公式离屏渲染成真实排版图片，再交给
  // buildTutorialPdfBytes 嵌进 PDF。公式渲染必须有 Overlay/RepaintBoundary，
  // 没法塞进纯后台的 buildTutorialPdfBytes 里，所以在这里先跑
  Future<Uint8List> _generate() async {
    final latexImages = await renderTutorialLatexImages(
      context,
      widget.blocks,
      isDark: widget.style == 'dark',
    );
    return buildTutorialPdfBytes(
      tutorial: widget.tutorial,
      blocks: widget.blocks,
      style: widget.style,
      latexImages: latexImages,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _onTick(Timer timer) async {
    setState(() => _step++);
    if (_step >= _steps.length) {
      timer.cancel();
      await _finish();
    }
  }

  Future<void> _finish() async {
    Uint8List? bytes;
    try {
      // 正常情况下 postFrameCallback 早已把 _generateFuture 赋好；兜底一下
      // 万一还没赋（极端时序），这里再启动一次
      bytes = await (_generateFuture ??= _generate());
    } catch (e) {
      if (!mounted || _cancelled) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出失败：$e')));
      context.pop();
      return;
    }
    if (!mounted || _cancelled) return;
    context.pushReplacement(
      '/tutorial/export/preview',
      extra: {'bytes': bytes, 'title': widget.tutorial['title']?.toString() ?? '文章'},
    );
  }

  void _cancel() {
    _cancelled = true;
    _timer?.cancel();
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.tutorial['title']?.toString() ?? '';
    final progress = _step / _steps.length;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 4),
            Text(
              '导出进度 → 完成',
              style: TextStyle(fontSize: 11, color: Colors.grey[400]),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _cancel,
                    child: Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      child: const Icon(Icons.close, size: 20),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '正在导出',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 34),
                ],
              ),
            ),
            const Divider(height: 20, thickness: 0.5),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF0FF),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(
                          Icons.picture_as_pdf,
                          color: _primary,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        '生成 PDF 中',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                      ),
                      const SizedBox(height: 24),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          backgroundColor: const Color(0xFFEBEBEB),
                          valueColor: const AlwaysStoppedAnimation(_primary),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${(progress * 100).round()}%',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _primary,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Column(
                        children: List.generate(_steps.length, (i) {
                          final done = i < _step;
                          final current = i == _step;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: done || current
                                        ? _primary
                                        : Colors.grey[200],
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: done
                                        ? const Icon(
                                            Icons.check,
                                            size: 13,
                                            color: Colors.white,
                                          )
                                        : Text(
                                            '${i + 1}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: current
                                                  ? Colors.white
                                                  : Colors.grey[500],
                                            ),
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  _steps[i],
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: current
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: done || current
                                        ? Theme.of(
                                            context,
                                          ).textTheme.bodyLarge?.color
                                        : Colors.grey[400],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
