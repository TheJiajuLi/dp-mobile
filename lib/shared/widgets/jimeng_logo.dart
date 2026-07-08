import 'package:flutter/material.dart';

// 品牌 icon——深色卡片底 + 四条极光弧线，不跟随主题（深浅色下背景都是这
// 同一块深紫色，跟真实 App 图标保持一致），登录/注册/启动页复用同一份
class JimengLogo extends StatelessWidget {
  final double size;

  const JimengLogo({super.key, this.size = 80});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1630), Color(0xFF120F24)],
        ),
        borderRadius: BorderRadius.circular(size * 0.25),
      ),
      child: Center(
        child: FractionallySizedBox(
          widthFactor: 0.72,
          child: AspectRatio(
            aspectRatio: 52 / 38,
            child: CustomPaint(painter: _AuroraLogoPainter()),
          ),
        ),
      ),
    );
  }
}

class _AuroraArc {
  final Offset start;
  final Offset control;
  final Offset end;
  final Color from;
  final Color to;

  const _AuroraArc(this.start, this.control, this.end, this.from, this.to);
}

// 四条弧线从外到内，坐标取自 52×38 的原始 viewBox
const _arcs = [
  _AuroraArc(
    Offset(2, 34),
    Offset(26, 2),
    Offset(50, 34),
    Color(0xFFC9A840),
    Color(0xFF8BC34A),
  ),
  _AuroraArc(
    Offset(7, 34),
    Offset(26, 8),
    Offset(45, 34),
    Color(0xFF6B7FD4),
    Color(0xFF5B8FE0),
  ),
  _AuroraArc(
    Offset(12, 34),
    Offset(26, 13),
    Offset(40, 34),
    Color(0xFF5B5DA8),
    Color(0xFF7B6FC4),
  ),
  _AuroraArc(
    Offset(17, 34),
    Offset(26, 18),
    Offset(35, 34),
    Color(0xFF4CAF60),
    Color(0xFF66BB6A),
  ),
];

class _AuroraLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 52;
    canvas.scale(scale);

    for (final arc in _arcs) {
      final path = Path()
        ..moveTo(arc.start.dx, arc.start.dy)
        ..quadraticBezierTo(
          arc.control.dx,
          arc.control.dy,
          arc.end.dx,
          arc.end.dy,
        );
      final bounds = path.getBounds();
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(colors: [arc.from, arc.to]).createShader(bounds);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AuroraLogoPainter oldDelegate) => false;
}
