import 'package:flutter/widgets.dart';

import '../../l10n/generated/app_localizations.dart';

// 按当前小时分时段问候，首页/Notebook 首页共用，避免同一套分段逻辑抄两遍
String greetingText(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  final hour = DateTime.now().hour;
  if (hour >= 5 && hour < 12) return l10n.greetingGoodMorning;
  if (hour >= 12 && hour < 14) return l10n.greetingGoodNoon;
  if (hour >= 14 && hour < 18) return l10n.greetingGoodAfternoon;
  if (hour >= 18 && hour < 22) return l10n.greetingGoodEvening;
  return l10n.greetingLateNight;
}

String greetingSubtext(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  final hour = DateTime.now().hour;
  if (hour >= 5 && hour < 12) return l10n.greetingSubMorning;
  if (hour >= 12 && hour < 14) return l10n.greetingSubNoon;
  if (hour >= 14 && hour < 18) return l10n.greetingSubAfternoon;
  if (hour >= 18 && hour < 22) return l10n.greetingSubEvening;
  return l10n.greetingSubNight;
}
