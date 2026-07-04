import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('关于极梦'),
        backgroundColor: Theme.of(context).cardColor,
        foregroundColor: Theme.of(context).textTheme.bodyLarge?.color,
        elevation: 0,
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: ListView(
        children: [
          const SizedBox(height: 40),
          // Logo区
          Center(
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.auto_awesome, color: Colors.white, size: 40),
                ),
                const SizedBox(height: 16),
                const Text(
                  '极梦',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                const Text('为创造而生', style: TextStyle(fontSize: 14, color: Colors.grey)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF0FF),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Text(
                    'v1.0.0',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF6366F1),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),

          // 信息列表
          Container(
            color: Theme.of(context).cardColor,
            child: Column(
              children: [
                const ListTile(
                  title: Text('版本号'),
                  trailing: Text('v1.0.0', style: TextStyle(color: Colors.grey)),
                ),
                const Divider(height: 0.5, indent: 16),
                const ListTile(
                  title: Text('开发团队'),
                  trailing: Text(
                    'Dreaming Polar',
                    style: TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.w500),
                  ),
                ),
                const Divider(height: 0.5, indent: 16),
                ListTile(
                  title: const Text('官网'),
                  trailing: const Text(
                    'dreamingpolar.com',
                    style: TextStyle(color: Color(0xFF6366F1)),
                  ),
                  onTap: () => _open('https://dreamingpolar.com'),
                ),
                const Divider(height: 0.5, indent: 16),
                ListTile(
                  title: const Text('用户协议'),
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () => _open('https://dreamingpolar.com/terms'),
                ),
                const Divider(height: 0.5, indent: 16),
                ListTile(
                  title: const Text('隐私政策'),
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () => _open('https://dreamingpolar.com/privacy'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Center(
            child: Text(
              '© 2026 Dreaming Polar\n极梦，为创造而生',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.6),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
