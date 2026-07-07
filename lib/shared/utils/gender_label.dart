import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';

// 性别的后端存储值必须保持中文（'男'/'女'/'保密'，跟后端contract一致，
// 见CONTEXT.md），只有展示文案跟着locale换——编辑资料页/主页都要用这个
String genderDisplayLabel(AppLocalizations l10n, String gender) =>
    switch (gender) {
      '男' => l10n.genderMale,
      '女' => l10n.genderFemale,
      '保密' => l10n.genderPrivate,
      _ => gender,
    };

// 主页信息行用的性别图标——"保密"永远不会走到这里（调用方在那之前就
// 已经把 gender=='保密' 的情况过滤掉，不展示这一项了），这里的 default
// 只是给任何未来意外值兜底
IconData genderIconFor(String gender) => switch (gender) {
  '男' => Icons.male,
  '女' => Icons.female,
  _ => Icons.person_outline,
};
