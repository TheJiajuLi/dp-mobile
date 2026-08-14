import 'dart:ui' as ui;
import '../../../core/theme/app_colors.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart' show Share;

const _primary = AppColors.primary;

class TutorialPosterScreen extends StatefulWidget {
  final Map<String, dynamic> tutorial;
  const TutorialPosterScreen({super.key, required this.tutorial});

  @override
  State<TutorialPosterScreen> createState() => _TutorialPosterScreenState();
}

class _TutorialPosterScreenState extends State<TutorialPosterScreen> {
  final _repaintKey = GlobalKey();
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F0F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF0F0F8),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18, color: Colors.black87),
          onPressed: () => context.pop(),
        ),
        title: const Text('分享海报', style: TextStyle(color: Colors.black87)),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined, color: Colors.black87),
            onPressed: _saving ? null : _saveImage,
            tooltip: '保存图片',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: RepaintBoundary(key: _repaintKey, child: _buildPoster()),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            child: Column(
              children: [
                Text(
                  '长按图片保存到相册',
                  style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _saving ? null : _saveImage,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('保存图片'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Share.share(
                          '${widget.tutorial['title'] ?? ''}\n\n'
                          'https://dreamingpolar.com/tutorial/${widget.tutorial['id']}\n\n'
                          '来自极梦知识平台',
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('分享链接'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPoster() {
    final tutorial = widget.tutorial;
    final title = tutorial['title']?.toString() ?? '';
    final username = tutorial['username']?.toString() ?? '';
    final views = (tutorial['views'] as num?)?.toInt() ?? 0;
    final likes = (tutorial['likes'] as num?)?.toInt() ?? 0;

    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: _primary,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.auto_stories, color: Colors.white, size: 14),
              ),
              const SizedBox(width: 6),
              const Text(
                '极梦知识平台',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white70,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              height: 1.4,
            ),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 14),
          Container(height: 0.5, color: Colors.white24),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Text(
                    '梦',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  username,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.favorite, color: Colors.white54, size: 12),
                  const SizedBox(width: 3),
                  Text('$likes', style: const TextStyle(fontSize: 10, color: Colors.white54)),
                  const SizedBox(width: 8),
                  const Icon(Icons.visibility, color: Colors.white54, size: 12),
                  const SizedBox(width: 3),
                  Text('$views', style: const TextStyle(fontSize: 10, color: Colors.white54)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.qr_code, color: _primary, size: 36),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '扫码阅读全文',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'dreamingpolar.com',
                      style: TextStyle(fontSize: 10, color: Colors.white54),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _saveImage() async {
    setState(() => _saving = true);
    try {
      final boundary =
          _repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      await Gal.putImageBytes(
        bytes,
        name: 'jimeng_poster_${DateTime.now().millisecondsSinceEpoch}',
      );

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已保存到相册')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
