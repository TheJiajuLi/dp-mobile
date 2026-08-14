import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

// CONTEXT.md 里的话题领域配色规则表，唯一数据来源——个人主页的兴趣领域
// badge、首页 Feed 卡片的话题角标都从这一份表里取色，不要各自维护一份，
// 不然规则改一次要改好几个地方，迟早会不一致
class TopicBadgeRule {
  final String label;
  final List<String> keywords;
  final Color bg;
  final Color fg;

  const TopicBadgeRule({
    required this.label,
    required this.keywords,
    required this.bg,
    required this.fg,
  });
}

const topicBadgeRules = [
  TopicBadgeRule(
    label: '数据科学',
    keywords: ['数据'],
    bg: AppColors.primaryLight,
    fg: AppColors.primary,
  ),
  TopicBadgeRule(
    label: '生命科学',
    keywords: ['生命', '生物'],
    bg: Color(0xFFE8F8F0),
    fg: AppColors.success,
  ),
  TopicBadgeRule(
    label: '经济',
    keywords: ['经济', '金融'],
    bg: Color(0xFFFFF7E6),
    fg: Color(0xFFD97706),
  ),
  TopicBadgeRule(
    label: '宇宙天文',
    keywords: ['宇宙', '天文', '物理'],
    bg: Color(0xFFFDF0F8),
    fg: Color(0xFFC026D3),
  ),
  TopicBadgeRule(
    label: '编程',
    keywords: ['编程', '代码', '开发', 'python', 'javascript'],
    bg: Color(0xFFE6F0FF),
    fg: Color(0xFF2563EB),
  ),
  TopicBadgeRule(
    label: '时事',
    keywords: ['时事', '新闻', '政策', '社会'],
    bg: Color(0xFFF5F5F5),
    fg: Color(0xFF555555),
  ),
];

const topicBadgeDefault = (bg: Color(0xFFF5F5F5), fg: Color(0xFF999999));

// 给一个具体的 tag 找配色，找不到匹配规则就用中性灰兜底——不强行拍进
// 某个不相关的分类里
(Color bg, Color fg) topicBadgeStyleFor(String tag) {
  final lower = tag.toLowerCase();
  for (final rule in topicBadgeRules) {
    if (rule.keywords.any(lower.contains)) return (rule.bg, rule.fg);
  }
  return (topicBadgeDefault.bg, topicBadgeDefault.fg);
}

// 从一堆 tag 里找第一个能匹配到规则表分类的整条规则（标签文案+配色一次性
// 拿到，不用先查标签再单独查一次颜色，两边保证是同一条规则），一个都匹配
// 不到就返回 null，调用方自己决定怎么兜底（通常是原始 tag 文本 + 中性灰）
TopicBadgeRule? matchedTopicRuleFor(List<String> tags) {
  for (final tag in tags) {
    final lower = tag.toLowerCase();
    for (final rule in topicBadgeRules) {
      if (rule.keywords.any(lower.contains)) return rule;
    }
  }
  return null;
}

// 从一堆 tag 里找第一个能匹配到规则表分类的，返回规则的"标准名"
// （比如把 tutorial 自己的 tag "泊松分布" 映射成"数据科学"这个分类名）；
// 一个都匹配不到就退回第一个原始 tag，不吞掉这条信息
String? topicCategoryLabelFor(List<String> tags) {
  final matched = matchedTopicRuleFor(tags);
  if (matched != null) return matched.label;
  return tags.isNotEmpty ? tags.first : null;
}
