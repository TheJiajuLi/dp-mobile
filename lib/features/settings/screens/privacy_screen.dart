import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_client.dart';
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
    await _syncToBackend();
  }

  // 实测 PUT /auth/users/privacy 目前是 404，后端还没做这个接口——真上线
  // 后这里会自动生效，不用等接口就绪再改代码。失败就悄悄忽略：本地已经
  // 存下了这次改动，不能因为后端还没跟上就打断用户操作或弹错误
  Future<void> _syncToBackend() async {
    try {
      await ref.read(apiClientProvider).put(
        '/auth/users/privacy',
        data: {
          'publicProfile': _publicProfile,
          'publicFavorites': _publicFavorites,
          'allowComments': _allowComments,
          'allowMessages': _allowMessages,
        },
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('隐私设置'),
        backgroundColor: Theme.of(context).cardColor,
        foregroundColor: Theme.of(context).textTheme.bodyLarge?.color,
        elevation: 0,
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: ListView(
        children: [
          const SizedBox(height: 8),
          Container(
            color: Theme.of(context).cardColor,
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('公开个人主页'),
                  subtitle: const Text('关闭后其他用户无法查看你的主页（功能完善中，暂未生效）'),
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
                  subtitle: const Text('允许其他用户查看你的收藏（功能完善中，暂未生效）'),
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
                  subtitle: const Text('关闭后其他用户无法评论你的教程（功能完善中，暂未生效）'),
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
                  subtitle: const Text('关闭后其他用户无法给你发消息（功能完善中，暂未生效）'),
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
