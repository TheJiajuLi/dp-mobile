import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../l10n/generated/app_localizations.dart';

enum ZodiacSign {
  aries,
  taurus,
  gemini,
  cancer,
  leo,
  virgo,
  libra,
  scorpio,
  sagittarius,
  capricorn,
  aquarius,
  pisces,
}

extension ZodiacSignExt on ZodiacSign {
  String get assetPath => 'assets/icons/zodiac/$name.svg';

  // 根据生日返回星座
  static ZodiacSign fromBirthday(int month, int day) {
    if ((month == 3 && day >= 21) || (month == 4 && day <= 19)) return ZodiacSign.aries;
    if ((month == 4 && day >= 20) || (month == 5 && day <= 20)) return ZodiacSign.taurus;
    if ((month == 5 && day >= 21) || (month == 6 && day <= 21)) return ZodiacSign.gemini;
    if ((month == 6 && day >= 22) || (month == 7 && day <= 22)) return ZodiacSign.cancer;
    if ((month == 7 && day >= 23) || (month == 8 && day <= 22)) return ZodiacSign.leo;
    if ((month == 8 && day >= 23) || (month == 9 && day <= 22)) return ZodiacSign.virgo;
    if ((month == 9 && day >= 23) || (month == 10 && day <= 23)) return ZodiacSign.libra;
    if ((month == 10 && day >= 24) || (month == 11 && day <= 22)) return ZodiacSign.scorpio;
    if ((month == 11 && day >= 23) || (month == 12 && day <= 21)) return ZodiacSign.sagittarius;
    if ((month == 12 && day >= 22) || (month == 1 && day <= 19)) return ZodiacSign.capricorn;
    if ((month == 1 && day >= 20) || (month == 2 && day <= 18)) return ZodiacSign.aquarius;
    return ZodiacSign.pisces;
  }
}

// chineseName是纯中文展示用的（历史遗留），后端实际存的zodiac值是
// ZodiacSign.name这个英文enum标识（如"aries"），跟展示语言无关——这个
// 函数才是UI要用的，按当前locale换文案
String zodiacDisplayName(AppLocalizations l10n, ZodiacSign sign) => switch (sign) {
  ZodiacSign.aries => l10n.zodiacAries,
  ZodiacSign.taurus => l10n.zodiacTaurus,
  ZodiacSign.gemini => l10n.zodiacGemini,
  ZodiacSign.cancer => l10n.zodiacCancer,
  ZodiacSign.leo => l10n.zodiacLeo,
  ZodiacSign.virgo => l10n.zodiacVirgo,
  ZodiacSign.libra => l10n.zodiacLibra,
  ZodiacSign.scorpio => l10n.zodiacScorpio,
  ZodiacSign.sagittarius => l10n.zodiacSagittarius,
  ZodiacSign.capricorn => l10n.zodiacCapricorn,
  ZodiacSign.aquarius => l10n.zodiacAquarius,
  ZodiacSign.pisces => l10n.zodiacPisces,
};

class ZodiacIcon extends StatelessWidget {
  final ZodiacSign sign;
  final double size;

  const ZodiacIcon({super.key, required this.sign, this.size = 48});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(sign.assetPath, width: size, height: size);
  }
}
