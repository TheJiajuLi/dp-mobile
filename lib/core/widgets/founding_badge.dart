import 'package:flutter/material.dart';

// 元老创作者标识——方案C（极简徽章）+ 极光头像边框的组合：平时用小标签，
// 个人主页展示大徽章，头像用彩色极光边框区分
const _foundingBg = Color(0xFF1A0E2E);
const _foundingBorder = Color(0xFF6366F1);
const _foundingStar = Color(0xFFF59E0B);
const _foundingText = Color(0xFFA5B4FC);

// 小标签（用户名旁，评论区/发现页等场景）
class FoundingBadgeSmall extends StatelessWidget {
  const FoundingBadgeSmall({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 5),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: _foundingBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: _foundingBorder.withValues(alpha: 0.5),
          width: 0.5,
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('★', style: TextStyle(fontSize: 8, color: _foundingStar)),
          SizedBox(width: 3),
          Text(
            '元老',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: _foundingText,
            ),
          ),
        ],
      ),
    );
  }
}

// 头像外圈（极光渐变边框）——非元老创作者原样返回 child，不额外占位
class FoundingAvatarRing extends StatelessWidget {
  final Widget child;
  final bool isFoundingCreator;
  final double size;

  const FoundingAvatarRing({
    super.key,
    required this.child,
    required this.isFoundingCreator,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    if (!isFoundingCreator) return child;
    return Container(
      width: size + 5,
      height: size + 5,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            Color(0xFFF59E0B),
            Color(0xFF818CF8),
            Color(0xFF4ADE80),
            Color(0xFF818CF8),
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
class FoundingBadgeLarge extends StatelessWidget {
  const FoundingBadgeLarge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: _foundingBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _foundingBorder.withValues(alpha: 0.5),
          width: 0.5,
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('★', style: TextStyle(fontSize: 14, color: _foundingStar)),
          SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '元老创作者',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              Text(
                'FOUNDING CREATOR',
                style: TextStyle(
                  fontSize: 9,
                  color: Color(0xFF818CF8),
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
