import 'package:flutter_riverpod/flutter_riverpod.dart';

// 极索页是 StatefulShellRoute 的一个常驻分支，切走再切回来 State 不会
// 重建，热门提问列表不会自动重新拉。发布回答发生在完全不同的页面（甚至
// 隔着 InviteListScreen/AnswerQuestionScreen 好几层），没有天然的回调
// 时机去刷新它——跟 profile_refresh_signal.dart 同一个套路，用这个计数器
// 当全局信号：谁发布了回答就 +1，JisuoScreen 里 ref.listen 到变化就
// 重新拉一次热门提问
final jisuoRefreshSignalProvider = StateProvider<int>((ref) => 0);

void notifyJisuoShouldRefresh(WidgetRef ref) {
  ref.read(jisuoRefreshSignalProvider.notifier).state++;
}
