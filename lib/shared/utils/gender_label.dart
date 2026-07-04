import '../../l10n/generated/app_localizations.dart';

// 性别的后端存储值必须保持中文（'男'/'女'/'保密'，跟后端contract一致，
// 见CONTEXT.md），只有展示文案跟着locale换——编辑资料页/主页都要用这个
String genderDisplayLabel(AppLocalizations l10n, String gender) => switch (gender) {
  '男' => l10n.genderMale,
  '女' => l10n.genderFemale,
  '保密' => l10n.genderPrivate,
  _ => gender,
};
