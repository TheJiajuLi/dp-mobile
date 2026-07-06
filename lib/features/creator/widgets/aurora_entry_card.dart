import 'package:flutter/material.dart';

const _cyan = Color(0xFFA5F3FC);
const _primary = Color(0xFF6366F1);

// 极光计划入口卡——不管创作者中心当前是浅色还是深色主题，这张卡始终用
// 深色星空底 + 极光光晕，跟个人主页头图区一样是刻意保留的局部深色例外，
// 用来强调"这是个稀有/值得追寻的东西"，不跟着整体主题切换褪色
class AuroraEntryCard extends StatelessWidget {
  final int noteCount;
  final int noteTarget;
  final int likesSaves;
  final int likesSavesTarget;
  final int followers;
  final int followerTarget;
  final VoidCallback onTap;

  const AuroraEntryCard({
    super.key,
    required this.noteCount,
    required this.noteTarget,
    required this.likesSaves,
    required this.likesSavesTarget,
    required this.followers,
    required this.followerTarget,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F0C29), Color(0xFF1A1040), Color(0xFF24243E)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -30,
              top: -40,
              child: _glow(_primary, 140),
            ),
            Positioned(
              left: -20,
              bottom: -30,
              child: _glow(_cyan, 100),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Icon(
                          Icons.auto_awesome,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '极光创作者计划',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              'AURORA CREATOR PROGRAM',
                              style: TextStyle(
                                fontSize: 10,
                                letterSpacing: 1,
                                color: Colors.white.withValues(alpha: 0.55),
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: onTap,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            '查看',
                            style: TextStyle(fontSize: 12, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _progressCol('笔记', noteCount, noteTarget),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _progressCol(
                          '获赞/收藏',
                          likesSaves,
                          likesSavesTarget,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _progressCol('粉丝', followers, followerTarget),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text(
                        '继续创作，达成条件后自动解锁',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.55),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward,
                        size: 13,
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glow(Color color, double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0)],
      ),
    ),
  );

  Widget _progressCol(String label, int value, int target) {
    final ratio = target <= 0 ? 0.0 : (value / target).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.55)),
        ),
        const SizedBox(height: 4),
        Text(
          '$value/$target',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 4,
            backgroundColor: Colors.white.withValues(alpha: 0.12),
            valueColor: const AlwaysStoppedAnimation(_cyan),
          ),
        ),
      ],
    );
  }
}
