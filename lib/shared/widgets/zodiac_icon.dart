import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

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

  String get chineseName =>
      const {
        ZodiacSign.aries: '白羊座',
        ZodiacSign.taurus: '金牛座',
        ZodiacSign.gemini: '双子座',
        ZodiacSign.cancer: '巨蟹座',
        ZodiacSign.leo: '狮子座',
        ZodiacSign.virgo: '处女座',
        ZodiacSign.libra: '天秤座',
        ZodiacSign.scorpio: '天蝎座',
        ZodiacSign.sagittarius: '射手座',
        ZodiacSign.capricorn: '摩羯座',
        ZodiacSign.aquarius: '水瓶座',
        ZodiacSign.pisces: '双鱼座',
      }[this]!;

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

class ZodiacIcon extends StatelessWidget {
  final ZodiacSign sign;
  final double size;

  const ZodiacIcon({super.key, required this.sign, this.size = 48});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(sign.assetPath, width: size, height: size);
  }
}
