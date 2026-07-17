import 'package:flutter_riverpod/flutter_riverpod.dart';

// HD 首页工作区当前选中的 articleId——左侧列表点选写它，中间阅读面板 + 右侧
// 目录面板都 watch 它。被 StatefulShellRoute.indexedStack 分支保活，切走再回来
// 选中项还在。深链（P1）以后和 /hd/home?article= 双向同步
final homeSelectedArticleProvider = StateProvider<String?>((ref) => null);
