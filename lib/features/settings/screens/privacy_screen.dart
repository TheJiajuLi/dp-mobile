import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/auth_service.dart';

class PrivacyScreen extends ConsumerStatefulWidget {
  const PrivacyScreen({super.key});

  @override
  ConsumerState<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends ConsumerState<PrivacyScreen> {
  bool _publicProfile = true;
  bool _publicFavorites = false;
  bool _allowComments = true;
  bool _allowMessages = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = ref.read(currentUserProvider)?.id ?? '';
    if (!mounted) return;
    setState(() {
      _publicProfile = prefs.getBool('${userId}_privacy_public_profile') ?? true;
      _publicFavorites =
          prefs.getBool('${userId}_privacy_public_favorites') ?? false;
      _allowComments = prefs.getBool('${userId}_privacy_allow_comments') ?? true;
      _allowMessages = prefs.getBool('${userId}_privacy_allow_messages') ?? true;
    });
  }

  Future<void> _save(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = ref.read(currentUserProvider)?.id ?? '';
    await prefs.setBool('${userId}_$key', value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('隐私设置'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF8F8F8),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          Container(
            color: Colors.white,
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('公开个人主页'),
                  subtitle: const Text('关闭后其他用户无法查看你的主页'),
                  value: _publicProfile,
                  activeThumbColor: const Color(0xFF6366F1),
                  onChanged: (v) {
                    setState(() => _publicProfile = v);
                    _save('privacy_public_profile', v);
                  },
                ),
                const Divider(height: 0.5, indent: 16),
                SwitchListTile(
                  title: const Text('公开收藏列表'),
                  subtitle: const Text('允许其他用户查看你的收藏'),
                  value: _publicFavorites,
                  activeThumbColor: const Color(0xFF6366F1),
                  onChanged: (v) {
                    setState(() => _publicFavorites = v);
                    _save('privacy_public_favorites', v);
                  },
                ),
                const Divider(height: 0.5, indent: 16),
                SwitchListTile(
                  title: const Text('允许评论'),
                  subtitle: const Text('关闭后其他用户无法评论你的教程'),
                  value: _allowComments,
                  activeThumbColor: const Color(0xFF6366F1),
                  onChanged: (v) {
                    setState(() => _allowComments = v);
                    _save('privacy_allow_comments', v);
                  },
                ),
                const Divider(height: 0.5, indent: 16),
                SwitchListTile(
                  title: const Text('允许私信'),
                  subtitle: const Text('关闭后其他用户无法给你发消息'),
                  value: _allowMessages,
                  activeThumbColor: const Color(0xFF6366F1),
                  onChanged: (v) {
                    setState(() => _allowMessages = v);
                    _save('privacy_allow_messages', v);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
