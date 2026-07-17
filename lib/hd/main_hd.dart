import '../core/app_bootstrap.dart';
import 'hd_app.dart';

// RunnerHD（iPad）的 Dart 入口。跟 lib/main.dart 走同一套 bootstrapAndRun
// 地基（cookie/crashlytics/apiClient override/ProviderScope），只是 root 换成
// HdApp。iPhone 的 Runner 入口是 lib/main.dart，两个 target 各跑各的
void main() => bootstrapAndRun(() => const HdApp());
