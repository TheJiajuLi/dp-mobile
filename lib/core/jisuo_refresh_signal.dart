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

// 极索进入"回答态"（小梦直答的回答在页内流式输出）时置 true——MainShell
// 监听它，为 true 时隐藏底部导航栏，让极索页变成沉浸式全屏，靠页内左上角
// 的返回键退出回答态。极索是 tab 分支、本身没有上一页可 pop，只能用这个
// 共享 flag 跟父级 MainShell 通信
final jisuoImmersiveProvider = StateProvider<bool>((ref) => false);
