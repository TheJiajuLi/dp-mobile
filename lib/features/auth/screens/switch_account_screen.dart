import 'dart:async';
import '../../../core/theme/app_colors.dart';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth_service.dart';
import '../../../core/network/api_client.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../messages/providers/messages_provider.dart';
import '../../settings/widgets/settings_row.dart';

const _primary = AppColors.primary;

class SwitchAccountScreen extends ConsumerStatefulWidget {
  const SwitchAccountScreen({super.key});

  @override
  ConsumerState<SwitchAccountScreen> createState() =>
      _SwitchAccountScreenState();
}

class _SwitchAccountScreenState extends ConsumerState<SwitchAccountScreen> {
  List<Map<String, dynamic>> _accounts = [];
  bool _loading = true;
  bool _managing = false;
  String? _switchingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final accounts = await ref.read(authServiceProvider).getRecentAccounts();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _loading = false;
    });
  }

  Future<void> _switchTo(String userId) async {
    if (_switchingId != null) return;
    setState(() => _switchingId = userId);
    final ok = await ref.read(authServiceProvider).switchToAccount(userId);
    if (!mounted) return;
    if (ok) {
      // 之前这里用 context.go('/splash?fromSwitch=true') 让整个底部导航
      // shell 离开再回来，逼着每个 tab 的页面实例重新 initState、重新
      // 拉数据。实测（2026-07-05）快速多次切换会撞上 go_router
      // StatefulShellRoute 内部 Navigator 用的 GlobalKey——上一次离开
      // shell 的 Navigator 还没销毁完，下一次又带着同一个 key 进来，
      // 抛"Duplicate GlobalKey detected in widget tree"。这个异常一旦
      // 抛出，之后的 go() 都会静默失败，界面卡死在切换前那个账号上，
      // 表现就是"切了好几次都没反应，一直是原来那个号"。
      //
      // switchToAccount() 里已经验证过 token 并把 currentUserProvider
      // 设成新账号了，根本不需要再绕道 /splash 重新查一遍 /auth/me。
      // 改成原地刷新，不离开 shell：清掉换账号前缓存的"我的"关注数、
      // 主动重新拉一次私信/通知（不用等 30 秒轮询），然后 go('/home')
      // 弹回首页 tab——这只是在已经存活的 shell 内部切 branch，不会碰
      // shell 自己的 Navigator，没有 GlobalKey 冲突的风险。首页的
      // homeFeedProvider 本来就 watch 了 currentUserProvider，
      // 会自动用新账号重新拉；"我的" tab 有专门的保险（build() 里发现
      // currentUserProvider 跟已加载的资料对不上号就自动重新加载）
      ref.read(myFollowingCountProvider.notifier).state = null;
      unawaited(ref.read(notificationsProvider.notifier).fetch());
      unawaited(ref.read(conversationsProvider.notifier).fetch());
      unawaited(_refreshUnreadCount());
      context.go('/home');
      return;
    }
    setState(() {
      _switchingId = null;
      _accounts.removeWhere((e) => e['id'] == userId);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.loginExpiredPleaseRelogin),
      ),
    );
  }

  // 底部导航消息 tab 的未读角标数——跟 MessagesScreen._loadData() 里查的
  // 是同一个接口，换完账号主动查一次，不用等消息 tab 那边 30 秒轮询。
  // 'total' 是通知+群组消息未读之和，跟 messages_screen.dart 保持同一个字段
  Future<void> _refreshUnreadCount() async {
    final res = await ref
        .read(apiClientProvider)
        .get('/auth/notifications/unread-count');
    if (res.success && res.data != null) {
      ref.read(unreadCountProvider.notifier).state =
          (res.data['total'] as num?)?.toInt() ?? 0;
    }
  }

  Future<void> _remove(String userId) async {
    await ref.read(authServiceProvider).removeRecentAccount(userId);
    if (!mounted) return;
    setState(() => _accounts.removeWhere((e) => e['id'] == userId));
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(currentUserProvider)?.id;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios),
                        onPressed: () => context.pop(),
                      ),
                      Expanded(
                        child: Text(
                          l10n.switchAccount,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _accounts.length <= 1
                            ? null
                            : () => setState(() => _managing = !_managing),
                        child: Text(
                          _managing ? l10n.done : l10n.manage,
                          style: TextStyle(
                            fontSize: 15,
                            color: _accounts.length <= 1
                                ? Colors.grey
                                : _primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_loading)
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  Expanded(
                    child: ListView(
                      children: [
                        const SizedBox(height: 8),
                        // 账号列表 + "添加其他账号" 合进同一个 SettingsGroup，
                        // 渲染成一整张圆角大卡片（行间只画分割线），不再是
                        // 两张各自带间距的独立卡片块
                        SettingsGroup(dividerIndent: 68, [
                          ..._accounts.map(
                            (a) => _AccountRow(
                              id: a['id']?.toString() ?? '',
                              username: a['username']?.toString() ?? '',
                              avatar: a['avatar']?.toString(),
                              isCurrent: a['id']?.toString() == currentUserId,
                              managing: _managing,
                              switching: _switchingId == a['id']?.toString(),
                              onSwitch: () =>
                                  _switchTo(a['id']?.toString() ?? ''),
                              onRemove: () =>
                                  _remove(a['id']?.toString() ?? ''),
                            ),
                          ),
                          ListTile(
                            leading: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Theme.of(
                                  context,
                                ).inputDecorationTheme.fillColor,
                              ),
                              child: const Icon(Icons.add, color: _primary),
                            ),
                            title: Text(
                              l10n.addOtherAccount,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            onTap: () => context.push('/login'),
                          ),
                        ]),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                          child: Text(
                            l10n.maxAccountsSupported,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).textTheme.bodySmall?.color,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // 切换过程中盖一层遮罩，避免用户看到"点了没反应"再到"内容突然
          // 换了"这种割裂感——只在真正发起切换后才显示，行内那个小
          // spinner(switching:)已经够表示"这一行在处理"，这层遮罩解决的
          // 是"整个过渡期间"的观感，不是重复同一个状态
          if (_switchingId != null)
            Positioned.fill(
              child: IgnorePointer(
                ignoring: false,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.6),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: _primary,
                          ),
                        ),
                        SizedBox(height: 16),
                        Text(
                          '切换账号中...',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  final String id;
  final String username;
  final String? avatar;
  final bool isCurrent;
  final bool managing;
  final bool switching;
  final VoidCallback onSwitch;
  final VoidCallback onRemove;

  const _AccountRow({
    required this.id,
    required this.username,
    required this.avatar,
    required this.isCurrent,
    required this.managing,
    required this.switching,
    required this.onSwitch,
    required this.onRemove,
  });

  Widget _buildAvatar() {
    if (avatar != null && avatar!.isNotEmpty) {
      if (avatar!.startsWith('data:image')) {
        try {
          final base64Data = avatar!.split(',').last;
          return CircleAvatar(
            radius: 22,
            backgroundImage: MemoryImage(base64Decode(base64Data)),
          );
        } catch (_) {
          // 解码失败落到下面的首字母占位
        }
      } else {
        return CircleAvatar(
          radius: 22,
          backgroundImage: CachedNetworkImageProvider(avatar!),
        );
      }
    }
    return CircleAvatar(
      radius: 22,
      backgroundColor: _primary,
      child: Text(
        (username.isNotEmpty ? username[0] : '?').toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      leading: _buildAvatar(),
      title: Text(
        username,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: Theme.of(context).textTheme.bodyLarge?.color,
        ),
      ),
      trailing: managing
          ? (isCurrent
                ? null
                : GestureDetector(
                    onTap: onRemove,
                    child: const Icon(
                      Icons.remove_circle_outline,
                      color: Colors.red,
                    ),
                  ))
          : isCurrent
          // 之前是粉底红字——"当前登录"是个中性状态，不是警告/错误，用
          // 报错色语义不对。改成中性灰底+跟随主题文字色，跟整套设置页
          // 的黑白基调统一
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                AppLocalizations.of(context)!.currentlyLoggedIn,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
            )
          : switching
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: _primary),
            )
          // 之前是紫色描边+紫字的 OutlinedButton，一圈实心边框跟整个
          // 页面（圆角卡片、无描边、填充色胶囊）的视觉语言割裂。改成
          // 同一套填充色胶囊、不描边
          : GestureDetector(
              onTap: onSwitch,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: _primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  AppLocalizations.of(context)!.switchToThisAccount,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _primary,
                  ),
                ),
              ),
            ),
    );
  }
}
