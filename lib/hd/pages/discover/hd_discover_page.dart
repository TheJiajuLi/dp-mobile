import 'package:flutter/material.dart';

import '../../state/hd_home_state.dart';
import '../hd_reader_workspace.dart';
import 'hd_discover_list_panel.dart';

// HD 发现——跟首页共用 HdReaderWorkspace（列表→阅读→目录 + 自适应），左侧列表
// 换成 communityProvider 的 HdDiscoverListPanel（标签筛选），选中态走
// discoverSelectedArticleProvider（跟首页分开）。原 575 行固定占位稿已弃用
class HdDiscoverPage extends StatelessWidget {
  const HdDiscoverPage({super.key});

  @override
  Widget build(BuildContext context) {
    return HdReaderWorkspace(
      selectedProvider: discoverSelectedArticleProvider,
      listPanel: HdDiscoverListPanel(
        selectedProvider: discoverSelectedArticleProvider,
      ),
    );
  }
}
