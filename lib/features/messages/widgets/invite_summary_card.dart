import 'package:flutter/material.dart';

// 邀请回答汇总卡——消息首页和"最近通知"页共用同一个组件，点击进
// /invite-list 专属列表页，不在卡片里直接接受/忽略。之前背景硬编码成
// Colors.white，跟页面其它卡片统一用的 Theme.of(context).cardColor 不
// 一致，深色模式下尤其显眼——这里改成跟随主题；同时之前只在
// count>0 时才整块渲染，找不到入口就是因为这张卡直接从页面上消失了，
// 现在改成常驻显示（count==0 时给一个"暂无待处理"的空态提示），
// 保证不管有没有邀请，入口都在同一个位置摸得到
class InviteSummaryCard extends StatelessWidget {
  final int count;
  final List<Map<String, dynamic>> invites;
  final VoidCallback onTap;

  const InviteSummaryCard({
    super.key,
    required this.count,
    required this.invites,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        // 跟同一个页面上"最近通知"/"私信"用的 _PreviewCard 统一成同一套
        // 圆角卡片语言——浅色靠细阴影撑轮廓不描边，圆角也对齐成20，不然
        // 两种卡片语言（描边 vs 阴影、14 vs 20）在同一屏里显得不统一
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFEEF0FF), Color(0xFFE0E7FF)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.question_answer_outlined,
                          size: 20,
                          color: Color(0xFF6366F1),
                        ),
                      ),
                      if (count > 0)
                        Positioned(
                          top: -4,
                          right: -4,
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 18),
                            height: 18,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(
                                color: Theme.of(context).cardColor,
                                width: 1.5,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '$count',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '邀请回答',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          count > 0 ? '有 $count 个问题等待你的见解' : '暂无待处理的邀请',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.4)
                                : Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.3)
                        : Colors.grey[400],
                  ),
                ],
              ),
            ),
            if (invites.isNotEmpty)
              SizedBox(
                height: 30,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
                  itemCount: invites.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (ctx, i) {
                    final q = (invites[i]['question_text'] as String?) ?? '';
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        q.length > 14 ? '${q.substring(0, 14)}...' : q,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6366F1),
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
