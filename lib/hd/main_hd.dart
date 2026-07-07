import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'hd_app.dart';

void mainHd() {
  runApp(const ProviderScope(child: HdApp()));
}

// 临时入口——只是为了能单独跑这个沙盒验证 Rail 出得来，不接入
// lib/main.dart，不影响真实 App 的启动路径
void main() => mainHd();
