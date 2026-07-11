import 'package:flutter/material.dart';

import '../utils/online_status.dart';

// 头像右下角的在线状态小圆点。离线不显示（返回空），在线绿点/最近活跃橙点
class OnlineDot extends StatelessWidget {
  final int? lastSeenAt;
  final double size;

  const OnlineDot({super.key, this.lastSeenAt, this.size = 10});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (OnlineStatusHelper.fromLastSeen(lastSeenAt) == OnlineStatus.offline) {
      return const SizedBox.shrink();
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: OnlineStatusHelper.dotColor(lastSeenAt, isDark),
        shape: BoxShape.circle,
        border: Border.all(
          color: isDark ? const Color(0xFF0A0A1A) : Colors.white,
          width: 1.5,
        ),
      ),
    );
  }
}
