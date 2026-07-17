import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/pro_access.dart';
import '../../../shared/widgets/app_toast.dart';
import 'tutorial_export_sheet.dart';
import 'tutorial_share_sheet.dart';

// 文章「要 UI/context」的动作——手机底栏、HD 顶/底栏共用一套，别两处各写。
// 改状态的动作（点赞/收藏）不在这里，走 articleProvider.notifier.toggleLike/Save。

// 分享——打开系统分享面板选择去向
void showArticleShareSheet(
  BuildContext context,
  Map<String, dynamic> tutorial,
) {
  showTutorialShareSheet(context, tutorial);
}

// 导出 PDF/Markdown——Pro 权益，点了才校验，非 Pro 弹会员 Sheet
void openArticleExportSheet(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> tutorial,
  List<dynamic> blocks,
) {
  if (!requirePro(context, ref, feature: '一键导出 PDF')) return;
  showTutorialExportSheet(context, tutorial: tutorial, blocks: blocks);
}

// 小梦解读——阶段2 先占位 toast，阶段3 接 xmeng 流式
void explainArticleWithXmeng(BuildContext context) {
  showAppToast(context, '小梦解读即将上线', ok: true);
}
