import 'package:flutter/material.dart';
import 'hd_shell.dart';

class HdTopBar extends StatelessWidget {
  final HdPage currentPage;
  const HdTopBar({super.key, required this.currentPage});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE5E5EA), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Text(
            _title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const Spacer(),
          ..._actions(context),
        ],
      ),
    );
  }

  String get _title => switch (currentPage) {
    HdPage.discover => '发现',
    HdPage.messages => '消息',
    HdPage.profile => '我的主页',
    HdPage.settings => '设置',
  };

  List<Widget> _actions(BuildContext context) {
    switch (currentPage) {
      case HdPage.profile:
        return [
          _btn(Icons.share_outlined, '分享主页'),
          const SizedBox(width: 8),
          _btn(Icons.settings_outlined, '设置'),
          const SizedBox(width: 8),
          _btn(Icons.edit_outlined, '编辑资料', dark: true),
        ];
      case HdPage.discover:
        return [
          Container(
            width: 160,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5E5EA), width: 0.5),
            ),
            child: const Row(
              children: [
                SizedBox(width: 10),
                Icon(Icons.search, size: 14, color: Color(0xFF999999)),
                SizedBox(width: 6),
                Text(
                  '搜索内容...',
                  style: TextStyle(fontSize: 13, color: Color(0xFF999999)),
                ),
              ],
            ),
          ),
        ];
      default:
        return [];
    }
  }

  Widget _btn(IconData icon, String label, {bool dark = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1A1A1A) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: dark ? const Color(0xFF1A1A1A) : const Color(0xFFE5E5EA),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: dark ? Colors.white : const Color(0xFF555555),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: dark ? Colors.white : const Color(0xFF555555),
            ),
          ),
        ],
      ),
    );
  }
}
