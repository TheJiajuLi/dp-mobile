import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

// 兴趣标签的毛玻璃配色表——跟 shared/utils/topic_badge.dart 是两套独立的
// 配色系统，不是重复维护：topic_badge.dart 服务的是白色卡片背景上的浅底
// 实色 badge（首页 Feed 话题角标等），这里服务的是个人主页深色玻璃头图区
// 专用的毛玻璃兴趣标签（半透明彩色底+浅色字+同色描边），两边的视觉语境
// 完全不同，硬要合并成一套只会让其中一边打折扣
class TagCategory {
  final Color bgColor;
  final Color borderColor;
  final Color textColor;
  final Color glowColor;

  const TagCategory({
    required this.bgColor,
    required this.borderColor,
    required this.textColor,
    required this.glowColor,
  });
}

const tagCategories = {
  'Python': TagCategory(
    bgColor: Color(0x443B82F6),
    borderColor: Color(0x663B82F6),
    textColor: Color(0xFFBFDBFE),
    glowColor: Color(0xFF3B82F6),
  ),
  'LaTeX': TagCategory(
    bgColor: Color(0x44A855F7),
    borderColor: Color(0x66A855F7),
    textColor: Color(0xFFE9D5FF),
    glowColor: Color(0xFFA855F7),
  ),
  'matplotlib': TagCategory(
    bgColor: Color(0x4422C55E),
    borderColor: Color(0x6622C55E),
    textColor: Color(0xFFBBF7D0),
    glowColor: Color(0xFF22C55E),
  ),
  '数据': TagCategory(
    bgColor: Color(0x446366F1),
    borderColor: Color(0x666366F1),
    textColor: Color(0xFFC7D2FE),
    glowColor: AppColors.primary,
  ),
  '编程': TagCategory(
    bgColor: Color(0x4406B6D4),
    borderColor: Color(0x6606B6D4),
    textColor: Color(0xFFA5F3FC),
    glowColor: Color(0xFF06B6D4),
  ),
  '科学': TagCategory(
    bgColor: Color(0x44F59E0B),
    borderColor: Color(0x66F59E0B),
    textColor: Color(0xFFFDE68A),
    glowColor: Color(0xFFF59E0B),
  ),
  '经济': TagCategory(
    bgColor: Color(0x44EF4444),
    borderColor: Color(0x66EF4444),
    textColor: Color(0xFFFECACA),
    glowColor: Color(0xFFEF4444),
  ),
  '生活': TagCategory(
    bgColor: Color(0x44EC4899),
    borderColor: Color(0x66EC4899),
    textColor: Color(0xFFFBCFE8),
    glowColor: Color(0xFFEC4899),
  ),
  '时事': TagCategory(
    bgColor: Color(0x44F97316),
    borderColor: Color(0x66F97316),
    textColor: Color(0xFFFED7AA),
    glowColor: Color(0xFFF97316),
  ),
  '宇宙': TagCategory(
    bgColor: Color(0x448B5CF6),
    borderColor: Color(0x668B5CF6),
    textColor: Color(0xFFDDD6FE),
    glowColor: Color(0xFF8B5CF6),
  ),
  '生命科学': TagCategory(
    bgColor: Color(0x4410B981),
    borderColor: Color(0x6610B981),
    textColor: Color(0xFFA7F3D0),
    glowColor: Color(0xFF10B981),
  ),
};

// 智能推理：从标签文字匹配类别——先看是不是表里的原词直接命中（区分
// 大小写，'Python' 命中专属配色，'python' 命中的是下面编程类目关键词），
// 再退回关键词模糊匹配，都没匹配到就落在"数据"当默认类目
TagCategory inferCategory(String tag) {
  if (tagCategories.containsKey(tag)) return tagCategories[tag]!;

  final lower = tag.toLowerCase();
  if ([
    'python',
    'dart',
    'js',
    'rust',
    'code',
    '代码',
    '算法',
  ].any(lower.contains)) {
    return tagCategories['编程']!;
  }
  if (['数据', '分析', '统计', 'pandas', 'numpy', '可视化'].any(lower.contains)) {
    return tagCategories['数据']!;
  }
  if (['物理', '化学', '数学', 'latex', '公式'].any(lower.contains)) {
    return tagCategories['科学']!;
  }
  if (['经济', '金融', '股票', '宏观'].any(lower.contains)) {
    return tagCategories['经济']!;
  }
  if (['宇宙', '天文', '星系', '黑洞', 'nasa'].any(lower.contains)) {
    return tagCategories['宇宙']!;
  }
  if (['生物', '基因', 'dna', '细胞', '医学'].any(lower.contains)) {
    return tagCategories['生命科学']!;
  }
  if (['新闻', '时事', '政治', '社会'].any(lower.contains)) {
    return tagCategories['时事']!;
  }
  return tagCategories['数据']!;
}
