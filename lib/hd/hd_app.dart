import 'package:flutter/material.dart';

import 'shell/hd_shell.dart';

class HdApp extends StatelessWidget {
  const HdApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '极梦 HD',
      theme: ThemeData(
        fontFamily: 'PingFang SC',
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6366F1)),
      ),
      home: const HdShell(),
    );
  }
}
