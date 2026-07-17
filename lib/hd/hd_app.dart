import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_material.dart';
import '../core/app_session_host.dart';
import 'hd_router.dart';

// HD 版根 widget——不再是裸 MaterialApp。复用主 App 的地基：buildDreamingApp
// 给全套主题/深色/l10n/字号/隐藏 Pyodide WebView（只把 router 换成 hdRouter），
// AppSessionHost 给内购 init + 回前台静默续 token。拿到的 provider（apiClient/
// currentUser/...）和手机端同一套，登录态/网络直接可用
class HdApp extends ConsumerWidget {
  const HdApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppSessionHost(
      child: buildDreamingApp(ref: ref, routerConfig: hdRouter),
    );
  }
}
