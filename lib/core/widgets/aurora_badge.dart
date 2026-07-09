import 'package:flutter/material.dart';

// 极光创作者标识——跟 founding_badge.dart 同一套视觉语言（深底+描边+
// 星标小标签+头像渐变圈），颜色换成金色系区分"元老"（靛紫极光）和
// "极光创作者"（暖金），两种身份互不冲突，可能同时显示在同一个用户身上
const _auroraBg = Color(0xFF1A0E2E);
const _auroraBorder = Color(0xFFF59E0B);
const _auroraStar = Color(0xFFF59E0B);
const _auroraText = Color(0xFFF59E0B);

// 小标签（用户名旁，评论区/教程列表/私信等场景）
class AuroraBadgeSmall extends StatelessWidget {
  const AuroraBadgeSmall({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 5),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: _auroraBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: _auroraBorder.withValues(alpha: 0.5),
          width: 0.5,
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('★', style: TextStyle(fontSize: 8, color: _auroraStar)),
          SizedBox(width: 3),
          Text(
            '极光',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: _auroraText,
            ),
          ),
        ],
      ),
    );
  }
}

// 头像外圈（金色渐变边框）——非极光创作者原样返回 child，不额外占位
class AuroraAvatarRing extends StatelessWidget {
  final Widget child;
  final bool isAuroraCreator;
  final double size;

  const AuroraAvatarRing({
    super.key,
    required this.child,
    required this.isAuroraCreator,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    if (!isAuroraCreator) return child;
    return Container(
      width: size + 5,
      height: size + 5,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            Color(0xFFF59E0B),
            Color(0xFFFFD700),
            Color(0xFFF59E0B),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.all(2.5),
      child: child,
    );
  }
}

// 个人主页大标签
class AuroraBadgeLarge extends StatelessWidget {
  const AuroraBadgeLarge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: _auroraBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _auroraBorder.withValues(alpha: 0.5),
          width: 0.5,
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('★', style: TextStyle(fontSize: 14, color: _auroraStar)),
          SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '极光创作者',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              Text(
                'AURORA CREATOR',
                style: TextStyle(
                  fontSize: 9,
                  color: Color(0xFFFBBF24),
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
