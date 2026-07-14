import 'package:flutter/material.dart';

// 极梦 PRO 紫金渐变——角标和"立即升级"按钮共用同一套配色
const proGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF6D5DF6), Color(0xFFE0A83E)],
);

// Pro 角标——紫金渐变小药丸，跟在用户名后。传 membership 字符串即可，
// 免费用户（非 pro / pro_max）自动渲染成空、不占位，调用方不用自己判断
class ProBadge extends StatelessWidget {
  final String? membership;
  final double fontSize;
  const ProBadge({super.key, required this.membership, this.fontSize = 8.5});

  @override
  Widget build(BuildContext context) {
    final m = membership;
    if (m != 'pro' && m != 'pro_max') return const SizedBox.shrink();
    final isMax = m == 'pro_max';
    return Container(
      padding: EdgeInsets.symmetric(horizontal: fontSize * 0.7, vertical: 1.5),
      decoration: BoxDecoration(
        gradient: proGradient,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isMax ? 'PRO MAX' : 'PRO',
        style: TextStyle(
          fontSize: fontSize,
          height: 1.1,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
