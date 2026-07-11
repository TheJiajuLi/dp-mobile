import 'package:flutter/material.dart';

// 后端用 last_seen_at（秒级 Unix 时间戳）推导在线状态，不走 WebSocket：
// <5分钟=在线，<30分钟=最近活跃，其余=离线
enum OnlineStatus { online, recently, offline }

class OnlineStatusHelper {
  static int get _nowSec => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  static OnlineStatus fromLastSeen(int? lastSeenAt) {
    if (lastSeenAt == null) return OnlineStatus.offline;
    final diff = _nowSec - lastSeenAt;
    if (diff < 300) return OnlineStatus.online;
    if (diff < 1800) return OnlineStatus.recently;
    return OnlineStatus.offline;
  }

  static String label(int? lastSeenAt) {
    switch (fromLastSeen(lastSeenAt)) {
      case OnlineStatus.online:
        return '在线';
      case OnlineStatus.recently:
        return '最近活跃';
      case OnlineStatus.offline:
        if (lastSeenAt == null) return '离线';
        final diff = _nowSec - lastSeenAt;
        if (diff < 3600) return '${diff ~/ 60}分钟前活跃';
        if (diff < 86400) return '${diff ~/ 3600}小时前活跃';
        return '${diff ~/ 86400}天前活跃';
    }
  }

  static Color dotColor(int? lastSeenAt, bool isDark) {
    switch (fromLastSeen(lastSeenAt)) {
      case OnlineStatus.online:
        return const Color(0xFF22C55E);
      case OnlineStatus.recently:
        return const Color(0xFFF59E0B);
      case OnlineStatus.offline:
        return isDark ? Colors.white24 : Colors.grey.shade300;
    }
  }
}
