import 'package:flutter_riverpod/flutter_riverpod.dart';

// 个人主页的教程/专栏 Tab 是 StatefulShellRoute.indexedStack 的一个分支，
// 切走再切回来 State 不会重建，_loadProfile 不会自动重跑。发布教程/新建
// 专栏这些操作发生在别的页面（甚至发布成功后用 context.go 直接跳到
// /community，压根不会 pop 回个人主页），没有天然的回调时机去刷新它——
// 所以用这个计数器当全局信号：谁改了内容就 +1，UserProfileScreen 里
// ref.listen 到变化就重新拉数据
final profileRefreshSignalProvider = StateProvider<int>((ref) => 0);

void notifyProfileShouldRefresh(WidgetRef ref) {
  ref.read(profileRefreshSignalProvider.notifier).state++;
}
