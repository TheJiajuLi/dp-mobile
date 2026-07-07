import 'package:flutter/material.dart';

import 'hd_shell.dart';

class HdTopBar extends StatelessWidget {
  final HdPage currentPage;

  const HdTopBar({super.key, required this.currentPage});

  static const _titles = {
    HdPage.discover: '发现',
    HdPage.messages: '消息',
    HdPage.profile: '我的',
    HdPage.settings: '设置',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E5EA), width: 0.5)),
      ),
      child: Row(
        children: [
          Text(
            _titles[currentPage] ?? '',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
        ],
      ),
    );
  }
}
