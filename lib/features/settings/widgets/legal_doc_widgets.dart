import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

import '../../../shared/widgets/brand_logo.dart';

const kLegalAccent = AppColors.primary;

// 法律文档页（用户服务协议/隐私政策）共用的排版组件——跟 PDF 版本的
// 视觉语言对齐：品牌色小节标题+细分割线、缩进要点、左侧强调色竖线的
// 提示框，两份文档的结构本来就高度相似，抽出来避免各写一套
class LegalDocHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final String effectiveDate;
  final String version;
  const LegalDocHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.effectiveDate,
    required this.version,
  });

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).textTheme.bodyLarge?.color;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const BrandLogo(width: 48, height: 36),
            const SizedBox(width: 10),
            Text(
              'Dreaming Polar',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          title,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
        ),
        const SizedBox(height: 10),
        Text(
          '生效日期：$effectiveDate · 版本：$version',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
        const SizedBox(height: 18),
        Container(height: 2, color: kLegalAccent.withValues(alpha: 0.5)),
        const SizedBox(height: 20),
      ],
    );
  }
}

// 一级小节标题，比如"一、信息控制者"
class LegalH2 extends StatelessWidget {
  final String text;
  const LegalH2(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: kLegalAccent,
        ),
      ),
    );
  }
}

// 二级小节标题，比如"2.1 您主动提供的信息"
class LegalH3 extends StatelessWidget {
  final String text;
  const LegalH3(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).textTheme.bodyLarge?.color;
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
      ),
    );
  }
}

// 正文段落
class LegalP extends StatelessWidget {
  final String text;
  const LegalP(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).brightness == Brightness.dark
        ? Colors.white70
        : const Color(0xFF444444);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: TextStyle(fontSize: 14, height: 1.7, color: color),
      ),
    );
  }
}

// 加粗强调段落（比如承诺回复时限）
class LegalPBold extends StatelessWidget {
  final String text;
  const LegalPBold(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).textTheme.bodyLarge?.color;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          height: 1.7,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
      ),
    );
  }
}

// 项目符号列表——每行前面一个圆点
class LegalBullets extends StatelessWidget {
  final List<String> items;
  const LegalBullets(this.items, {super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).brightness == Brightness.dark
        ? Colors.white70
        : const Color(0xFF444444);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items
            .map(
              (t) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: kLegalAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        t,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.6,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

// 编号列表——比如用户行为规范那 8 条
class LegalNumbered extends StatelessWidget {
  final List<String> items;
  const LegalNumbered(this.items, {super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).brightness == Brightness.dark
        ? Colors.white70
        : const Color(0xFF444444);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items
            .asMap()
            .entries
            .map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 20,
                      child: Text(
                        '${e.key + 1}.',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: kLegalAccent,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        e.value,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.6,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

// 左侧强调色竖线的提示框——PDF 里那种紫色引用块（开篇摘要/重要提示/
// 儿童隐私声明）
class LegalCallout extends StatelessWidget {
  final String text;
  const LegalCallout(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: isDark
            ? kLegalAccent.withValues(alpha: 0.12)
            : kLegalAccent.withValues(alpha: 0.06),
        border: const Border(left: BorderSide(color: kLegalAccent, width: 3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13.5,
          height: 1.7,
          fontStyle: FontStyle.italic,
          color: isDark ? Colors.white70 : const Color(0xFF444444),
        ),
      ),
    );
  }
}

// 联系方式一行——邮箱/网址这类
class LegalContactLine extends StatelessWidget {
  final String label;
  final String value;
  const LegalContactLine(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).textTheme.bodyLarge?.color;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: TextStyle(fontSize: 14, height: 1.6, color: ink),
          children: [
            TextSpan(text: '$label：'),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: kLegalAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LegalFooter extends StatelessWidget {
  const LegalFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 32, bottom: 20),
      child: Center(
        child: Text(
          '极梦（Dreaming Polar） · dreamingpolar.com · 2026',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
      ),
    );
  }
}
