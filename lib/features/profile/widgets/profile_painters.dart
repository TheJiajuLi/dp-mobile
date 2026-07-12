import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

const _primary = Color(0xFF6366F1);

// 没有真实封面图时的默认底——头像/用户名这一圈无论 App 是浅色还是深色
// 主题都固定叠白字白描边（见本文件里关于崩溃修复/暗色适配的说明，这块
// 区域本来就设计成"独立于 App 主题、始终够暗"），之前是一块很平的两色
// 斜向渐变，看起来更像"占位色块"而不是产品自己的视觉。改成呼应品牌
// 愿景文案本身那句"极地——无尽的白与深邃的星空"：深靛紫到品牌
// 靛蓝（#6366F1）过渡的极光渐变，叠一层稀疏的星点，靠固定随机种子生成、
// 每次 build 位置都一样，不会一重绘就"星星在跳"
// 深色模式保留极地星空（呼应品牌文案"无尽的白与深邃的星空"）；浅色模式
// 换成晴天/海边基调——深邃的星空放在浅色页面上会显得脏，晴空蓝到暖白
// 光晕再到海面蓝的渐变配一个柔和的"日光"光晕，跟深色版的星点是同一个
// 设计语言（渐变+一个 CustomPaint 点缀层），只是主题不同
class CoverGradient extends StatelessWidget {
  const CoverGradient();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.hardEdge,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? const [
                      Color(0xFF1A0E2E),
                      Color(0xFF0D1A3A),
                      Color(0xFF0A0A1A),
                    ]
                  : const [
                      Color(0xFF7EC8E3),
                      Color(0xFFFFF3D6),
                      Color(0xFF3D8FB0),
                    ],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
        ),
        if (isDark) ...[
          Positioned(
            top: -60,
            left: -40,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _primary.withValues(alpha: 0.2),
              ),
            ),
          ),
          Positioned(
            top: 10,
            right: -60,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
              ),
            ),
          ),
          const CustomPaint(painter: StarFieldPainter()),
        ] else
          const CustomPaint(painter: SunGlowPainter()),
      ],
    );
  }
}

class StarFieldPainter extends CustomPainter {
  const StarFieldPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(7);
    final paint = Paint();
    for (var i = 0; i < 60; i++) {
      final dx = rnd.nextDouble() * size.width;
      final dy = rnd.nextDouble() * size.height;
      final radius = 0.4 + rnd.nextDouble() * 1.0;
      paint.color = Colors.white.withValues(
        alpha: 0.12 + rnd.nextDouble() * 0.3,
      );
      canvas.drawCircle(Offset(dx, dy), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant StarFieldPainter oldDelegate) => false;
}

// 浅色模式的"日光"光晕——右上角一圈柔和白光，叠在晴空蓝渐变上，
// 营造晴天/海边的暖意，固定位置，不需要随机
class SunGlowPainter extends CustomPainter {
  const SunGlowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.78, size.height * 0.22);
    final radius = size.width * 0.32;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.55),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant SunGlowPainter oldDelegate) => false;
}

// AI头像生成等待弹窗——带计时+轮换提示语，跟 publish_screen.dart 的
// _AiGeneratingDialog 是同一套设计，只是文案换成头像场景，不共用一个
// widget 是因为两边弹窗的调用方各自处理自己的 dialogShowing 防重复pop，
// 抽成公共组件反而要多传一层回调，不值当
class AiGeneratingAvatarDialog extends StatefulWidget {
  const AiGeneratingAvatarDialog();

  @override
  State<AiGeneratingAvatarDialog> createState() =>
      AiGeneratingAvatarDialogState();
}

class AiGeneratingAvatarDialogState extends State<AiGeneratingAvatarDialog> {
  int _seconds = 0;
  Timer? _timer;

  static const _tips = [
    '小梦正在理解你的描述...',
    '正在构思头像风格...',
    '头像生成中，请稍候...',
    '即将完成，再等一下...',
  ];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _tip {
    if (_seconds < 5) return _tips[0];
    if (_seconds < 15) return _tips[1];
    if (_seconds < 35) return _tips[2];
    return _tips[3];
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: _primary),
          const SizedBox(height: 20),
          Text(
            _tip,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            '已等待 $_seconds 秒',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          const Text(
            '头像生成通常需要 15-25 秒',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
