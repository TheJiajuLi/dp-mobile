import 'package:flutter/material.dart';

import '../pages/discover/hd_discover_page.dart';
import '../pages/messages/hd_messages_page.dart';
import '../pages/profile/hd_profile_page.dart';
import '../pages/settings/hd_settings_page.dart';
import 'hd_rail.dart';
import 'hd_top_bar.dart';

enum HdPage { discover, messages, profile, settings }

class HdShell extends StatefulWidget {
  const HdShell({super.key});

  @override
  State<HdShell> createState() => _HdShellState();
}

class _HdShellState extends State<HdShell> {
  HdPage _currentPage = HdPage.discover;

  void _onNavTap(HdPage page) {
    setState(() => _currentPage = page);
  }

  Widget _buildCurrentPage() {
    switch (_currentPage) {
      case HdPage.discover:
        return const HdDiscoverPage();
      case HdPage.messages:
        return const HdMessagesPage();
      case HdPage.profile:
        return const HdProfilePage();
      case HdPage.settings:
        return const HdSettingsPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: SafeArea(
        child: Row(
          children: [
            // 左侧Rail（固定，永远在）
            HdRail(currentPage: _currentPage, onNavTap: _onNavTap),

            // 分割线
            const VerticalDivider(
              width: 0.5,
              thickness: 0.5,
              color: Color(0xFFE5E5EA),
            ),

            // 右侧内容区
            Expanded(
              child: Column(
                children: [
                  // 顶部工具栏
                  HdTopBar(currentPage: _currentPage),
                  // 内容
                  Expanded(child: _buildCurrentPage()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
