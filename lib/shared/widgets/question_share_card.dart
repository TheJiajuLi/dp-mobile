import 'package:flutter/material.dart';

// 聊天里「极梦社区问题」分享卡片——紫色渐变头（来源标识 + 问题标题）+ 白色
// 内容区（标签 + 回答数 + 双按钮：写回答 / 查看详情）。私聊/群聊共用。
// metadata 结构：{questionId, title, tag, answerCount}
class QuestionShareCard extends StatelessWidget {
  final Map<String, dynamic> metadata;
  final VoidCallback onAnswerTap;
  final VoidCallback onDetailTap;

  const QuestionShareCard({
    super.key,
    required this.metadata,
    required this.onAnswerTap,
    required this.onDetailTap,
  });

  static const _primary = Color(0xFF6366F1);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? const Color(0xFF17171F) : Colors.white;
    final border = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFEDEDE9);
    final ink = isDark ? const Color(0xFFF0F2F8) : const Color(0xFF1A1A1A);
    final muted = isDark ? const Color(0xFF7A80A0) : const Color(0xFF888888);
    final surface2 = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : const Color(0xFFF5F5F7);

    final title = metadata['title']?.toString() ?? '';
    final tag = metadata['tag']?.toString() ?? '';
    final answerCount = (metadata['answerCount'] as num?)?.toInt() ?? 0;

    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 紫色渐变头部
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_primary, Color(0xFF818CF8)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 来源标识
                Row(
                  children: [
                    Container(
                      width: 15,
                      height: 15,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '极',
                        style: TextStyle(
                          fontSize: 8.5,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '极梦社区问题',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          // 白色内容区
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (tag.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? _primary.withValues(alpha: 0.18)
                              : const Color(0xFFEEF0FF),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          tag,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: _primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      '$answerCount 个回答',
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: onAnswerTap,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _primary,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Text(
                            '✍️ 写回答',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: onDetailTap,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: surface2,
                            border: Border.all(color: border),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            '查看详情',
                            style: TextStyle(fontSize: 12, color: ink),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
