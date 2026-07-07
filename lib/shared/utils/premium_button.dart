import 'package:flutter/material.dart';

// 一线 App 里的紫色实心按钮基本不会是纯色一块平铺——iOS 系统控件那种
// "有厚度"的质感来自三样东西一起上：顶深底浅的渐变、边缘一圈极淡的高光
// 描边、加上按钮自身色调的投影（不是纯黑阴影）。这个装饰专门给"运行"/
// "小梦生成"/"发布"这几个紫色按钮统一复用，避免每处各写一套、样式慢慢
// 长歪
const _glowTop = Color(0xFF818CF8);
const _glowBottom = Color(0xFF5457E5);
const _mutedTop = Color(0xFFB0B4BD);
const _mutedBottom = Color(0xFF8B8F98);

BoxDecoration premiumPillDecoration({double radius = 999, bool muted = false}) {
  final colors = muted
      ? const [_mutedTop, _mutedBottom]
      : const [_glowTop, _glowBottom];
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: colors,
    ),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: Colors.white.withValues(alpha: 0.16), width: 0.6),
    boxShadow: [
      BoxShadow(
        color: (muted ? _mutedBottom : _glowBottom).withValues(alpha: 0.35),
        blurRadius: 10,
        offset: const Offset(0, 3),
      ),
    ],
  );
}

// iOS 原生按钮按下去有一点"回弹缩小"的触感反馈，纯色块直接换色远不如
// 这个有质感。轻量级封装，按下缩到 0.94 倍，松手弹回，不依赖额外的包
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const PressableScale({super.key, required this.child, this.onTap});

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  double _scale = 1;

  void _set(double v) {
    if (widget.onTap == null) return;
    setState(() => _scale = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _set(0.94),
      onTapUp: (_) => _set(1),
      onTapCancel: () => _set(1),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
