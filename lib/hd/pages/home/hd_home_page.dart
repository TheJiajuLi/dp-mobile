import 'package:flutter/material.dart';

import '../../state/hd_home_state.dart';
import '../hd_reader_workspace.dart';
import 'hd_article_list_panel.dart';

// HD 首页——用通用工作区 HdReaderWorkspace（列表→阅读→目录 + 自适应），左侧
// 列表是 homeFeedProvider 的 HdArticleListPanel，选中态走 homeSelectedArticleProvider
class HdHomePage extends StatelessWidget {
  const HdHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return HdReaderWorkspace(
      selectedProvider: homeSelectedArticleProvider,
      listPanel: HdArticleListPanel(
        selectedProvider: homeSelectedArticleProvider,
      ),
    );
  }
}
