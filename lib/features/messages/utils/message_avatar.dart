import 'dart:convert';
import '../../../core/theme/app_colors.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';

const kMessagesPrimary = AppColors.primary;

String avatarInitial(String? name) {
  if (name == null || name.isEmpty) return '?';
  return name.substring(0, 1).toUpperCase();
}

// 消息/好友相关几个页面共用同一套头像渲染规则：data:image 开头是旧的
// base64 头像，否则是 COS 图片 URL，都没有就用首字母占位
Widget buildMessageAvatar(
  String? avatar,
  String username, {
  double radius = 24,
}) {
  if (avatar != null && avatar.isNotEmpty) {
    if (avatar.startsWith('data:image')) {
      try {
        return CircleAvatar(
          radius: radius,
          backgroundImage: MemoryImage(base64Decode(avatar.split(',').last)),
        );
      } catch (_) {
        // 解码失败落到下面的首字母占位
      }
    } else {
      return CircleAvatar(
        radius: radius,
        backgroundImage: CachedNetworkImageProvider(avatar),
      );
    }
  }
  return CircleAvatar(
    radius: radius,
    backgroundColor: kMessagesPrimary,
    child: Text(
      avatarInitial(username),
      style: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
        fontSize: radius * 0.67,
      ),
    ),
  );
}

// 相对时间格式化——通知/私信/好友列表共用
String messageTimeAgo(AppLocalizations l10n, int tsMs) {
  final diff = DateTime.now().difference(
    DateTime.fromMillisecondsSinceEpoch(tsMs),
  );
  if (diff.inMinutes < 1) return l10n.timeJustNow;
  if (diff.inMinutes < 60) return l10n.timeMinutesAgo(diff.inMinutes);
  if (diff.inHours < 24) return l10n.timeHoursAgo(diff.inHours);
  if (diff.inDays < 30) return l10n.timeDaysAgo(diff.inDays);
  return l10n.timeMonthsAgo(diff.inDays ~/ 30);
}
