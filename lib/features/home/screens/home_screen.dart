import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/tutorial_model.dart';
import '../../../shared/utils/greeting.dart';
import '../../auth/auth_service.dart';
import '../providers/tutorials_provider.dart';

enum _EntryStatus { live, comingSoon, stayTuned }

extension on _EntryStatus {
  String get label => switch (this) {
    _EntryStatus.live => '已上线',
    _EntryStatus.comingSoon => '即将上线',
    _EntryStatus.stayTuned => '敬请期待',
  };
}

class _AppEntry {
  final String name;
  final IconData icon;
  final Color color;
  final _EntryStatus status;
  final String? route;
  final bool usePush;

  const _AppEntry({
    required this.name,
    required this.icon,
    required this.color,
    required this.status,
    this.route,
    this.usePush = false,
  });
}

const _appEntries = <_AppEntry>[
  _AppEntry(
    name: 'Power Notebook',
    icon: Icons.code,
    color: Color(0xFF6366F1),
    status: _EntryStatus.live,
    route: '/notebook',
    usePush: true,
  ),
  _AppEntry(
    name: 'ARIA 分析助手',
    icon: Icons.auto_awesome,
    color: Color(0xFF16A34A),
    status: _EntryStatus.live,
    route: '/aria',
    usePush: true,
  ),
  _AppEntry(
    name: '数据网格 Grid',
    icon: Icons.grid_on,
    color: Color(0xFF2563EB),
    status: _EntryStatus.comingSoon,
  ),
  _AppEntry(
    name: '可视化工厂',
    icon: Icons.bar_chart,
    color: Color(0xFFD97706),
    status: _EntryStatus.comingSoon,
  ),
  _AppEntry(
    name: '数学建模',
    icon: Icons.functions,
    color: Color(0xFFC026D3),
    status: _EntryStatus.comingSoon,
  ),
  _AppEntry(
    name: '更多敬请期待',
    icon: Icons.more_horiz,
    color: Color(0xFF8E8E93),
    status: _EntryStatus.stayTuned,
  ),
];

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  void _onEntryTap(BuildContext context, _AppEntry entry) {
    if (entry.route != null) {
      if (entry.usePush) {
        context.push(entry.route!);
      } else {
        context.go(entry.route!);
      }
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('即将上线，敬请期待')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final tutorialsAsync = ref.watch(recentTutorialsProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Dreaming Polar',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => context.go('/profile'),
                    child: _Avatar(avatar: user?.avatar, username: user?.username),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                '${greetingText()}，${user?.username ?? ''}',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                greetingSubtext(),
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
              const SizedBox(height: 24),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _appEntries.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.95,
                ),
                itemBuilder: (context, index) {
                  final entry = _appEntries[index];
                  return _AppEntryCard(
                    entry: entry,
                    onTap: () => _onEntryTap(context, entry),
                  );
                },
              ),
              tutorialsAsync.when(
                data: (list) {
                  // 没有自己创建的教程就整块隐藏，不展示占位文案
                  if (list.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 28),
                      Text(
                        '最近教程',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...list.map((t) => _TutorialTile(tutorial: t)),
                    ],
                  );
                },
                loading: () => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 28),
                    Text(
                      '最近教程',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...List.generate(3, (_) => const _TutorialSkeleton()),
                  ],
                ),
                // 加载失败静默隐藏——首页仪表盘不需要为这一小块内容展示报错
                error: (e, st) => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? avatar;
  final String? username;
  const _Avatar({this.avatar, this.username});

  @override
  Widget build(BuildContext context) {
    ImageProvider? provider;
    if (avatar != null && avatar!.isNotEmpty) {
      // 旧数据是 base64（data:image 开头），新数据是 COS URL
      if (avatar!.startsWith('data:image')) {
        try {
          provider = MemoryImage(base64Decode(avatar!.split(',').last));
        } catch (_) {
          provider = null;
        }
      } else {
        provider = CachedNetworkImageProvider(avatar!);
      }
    }
    // 没头像时跟个人主页保持一致，用首字母圆形占位，
    // 不要用灰底人形图标——两处观感不一样会让人以为头像没同步
    return CircleAvatar(
      radius: 18,
      backgroundColor: AppColors.primary,
      backgroundImage: provider,
      child: provider == null
          ? Text(
              (username?.isNotEmpty ?? false) ? username![0].toUpperCase() : '?',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );
  }
}

class _AppEntryCard extends StatelessWidget {
  final _AppEntry entry;
  final VoidCallback onTap;

  const _AppEntryCard({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final live = entry.status == _EntryStatus.live;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: Theme.of(context).dividerColor, width: 0.5),
        ),
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: entry.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(entry.icon, color: entry.color, size: 22),
                ),
                const SizedBox(height: 8),
                Text(
                  entry.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
              ],
            ),
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: live
                      ? const Color(0xFF16A34A).withValues(alpha: 0.12)
                      : Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  entry.status.label,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: live
                        ? const Color(0xFF16A34A)
                        : Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TutorialTile extends StatelessWidget {
  final TutorialModel tutorial;
  const _TutorialTile({required this.tutorial});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: () => context.push('/tutorial/${tutorial.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: Theme.of(context).dividerColor, width: 0.5),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tutorial.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tutorial.username,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Row(
              children: [
                Icon(
                  Icons.favorite_border,
                  size: 14,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
                const SizedBox(width: 4),
                Text(
                  '${tutorial.likes}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TutorialSkeleton extends StatelessWidget {
  const _TutorialSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Theme.of(context).dividerColor, width: 0.5),
      ),
      child: Shimmer.fromColors(
        baseColor: Theme.of(context).dividerColor,
        highlightColor: Theme.of(context).scaffoldBackgroundColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 160, height: 14, color: Colors.white),
            const SizedBox(height: 8),
            Container(width: 80, height: 12, color: Colors.white),
          ],
        ),
      ),
    );
  }
}
