import 'package:flutter_riverpod/flutter_riverpod.dart';

// HD「列表→阅读」工作区当前选中的 articleId。首页和发现各一个（分支保活、
// 互不干扰）：左侧列表点选写它，中间阅读面板 + 右侧目录面板都 watch 它。
// 深链（P1）以后和 /hd/home?article= 双向同步

// 首页工作区选中项
final homeSelectedArticleProvider = StateProvider<String?>((ref) => null);

// 发现工作区选中项（跟首页分开，切分支互不影响）
final discoverSelectedArticleProvider = StateProvider<String?>((ref) => null);
