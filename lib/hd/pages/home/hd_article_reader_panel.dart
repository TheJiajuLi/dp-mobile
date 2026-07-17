import 'package:flutter/material.dart';

import '../../../features/community/widgets/article_body_view.dart';
import 'hd_reader_bottom_bar.dart';
import 'hd_reader_top_bar.dart';

// HD 中间阅读面板：顶栏 + 无壳正文体(ArticleBodyView) + 底栏。scrollController
// 和 bodyController 由 HdHomePage 按 selectedId 持有并下传（换文章即重建），
// 目录面板共享同一个 bodyController。showTocButton: 中窄屏没有右侧目录面板时
// 顶栏露出目录浮层入口
class HdArticleReaderPanel extends StatelessWidget {
  final String tutorialId;
  final ScrollController scrollController;
  final ArticleBodyController bodyController;
  final bool showTocButton;
  const HdArticleReaderPanel({
    super.key,
    required this.tutorialId,
    required this.scrollController,
    required this.bodyController,
    this.showTocButton = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? Theme.of(context).scaffoldBackgroundColor
        : const Color(0xFFFAFAF8);
    return Container(
      color: bg,
      child: Column(
        children: [
          HdReaderTopBar(
            tutorialId: tutorialId,
            controller: bodyController,
            showTocButton: showTocButton,
          ),
          Expanded(
            child: ArticleBodyView(
              key: ValueKey(tutorialId),
              tutorialId: tutorialId,
              scrollController: scrollController,
              controller: bodyController,
              // scroll-spy 阈值：HD 顶栏 52，取略低于它
              activeHeadingTopThreshold: 64,
            ),
          ),
          HdReaderBottomBar(tutorialId: tutorialId),
        ],
      ),
    );
  }
}
