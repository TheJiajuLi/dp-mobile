import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

// 论坛头像的6种渐变色——建论坛页选一个存进 forums.color_index，
// AllForumsScreen/ForumHomeScreen 渲染头像时用同一份表取色，三处共享
// 一份，不要各自复制一份数组，否则容易改一处漏改另外两处
const List<List<Color>> forumGradients = [
  [AppColors.primary, Color(0xFF8B5CF6)],
  [AppColors.success, Color(0xFF0891B2)],
  [Color(0xFFD97706), Color(0xFFEF4444)],
  [Color(0xFFEC4899), Color(0xFF8B5CF6)],
  [Color(0xFF0891B2), AppColors.primary],
  [Color(0xFFEF4444), Color(0xFFD97706)],
];

List<Color> forumGradientFor(int colorIdx) =>
    forumGradients[colorIdx.clamp(0, forumGradients.length - 1)];
