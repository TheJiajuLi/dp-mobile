import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/tutorial_model.dart';
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

  const _AppEntry({
    required this.name,
    required this.icon,
    required this.color,
    required this.status,
    this.route,
  });
}

const _appEntries = <_AppEntry>[
  _AppEntry(
    name: 'Power Notebook',
    icon: Icons.code,
    color: Color(0xFF6366F1),
    status: _EntryStatus.live,
    route: '/aria',
  ),
  _AppEntry(
    name: 'ARIA 分析助手',
    icon: Icons.auto_awesome,
    color: Color(0xFF16A34A),
    status: _EntryStatus.live,
    route: '/aria',
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
      context.go(entry.route!);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('即将上线，敬请期待')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final tutorialsAsync = ref.watch(recentTutorialsProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '极梦',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => context.go('/profile'),
                    child: _Avatar(avatar: user?.avatar),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                '你好，${user?.username ?? ''} 👋',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '今天想探索什么？',
                style: TextStyle(fontSize: 14, color: AppColors.textMuted),
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
              const SizedBox(height: 28),
              const Text(
                '最近教程',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              tutorialsAsync.when(
                data: (list) {
                  if (list.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          '暂无教程',
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                      ),
                    );
                  }
                  return Column(
                    children: list.map((t) => _TutorialTile(tutorial: t)).toList(),
                  );
                },
                loading: () => Column(
                  children: List.generate(3, (_) => const _TutorialSkeleton()),
                ),
                error: (e, st) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      '加载失败：$e',
                      style: const TextStyle(color: AppColors.danger, fontSize: 13),
                    ),
                  ),
                ),
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
  const _Avatar({this.avatar});

  @override
  Widget build(BuildContext context) {
    ImageProvider? provider;
    if (avatar != null && avatar!.isNotEmpty) {
      try {
        final raw = avatar!.contains(',') ? avatar!.split(',').last : avatar!;
        provider = MemoryImage(base64Decode(raw));
      } catch (_) {
        provider = null;
      }
    }
    return CircleAvatar(
      radius: 18,
      backgroundColor: AppColors.border,
      backgroundImage: provider,
      child: provider == null
          ? const Icon(Icons.person, color: AppColors.textMuted, size: 20)
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
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.border, width: 0.5),
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
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
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
                      : AppColors.border,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  entry.status.label,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: live ? const Color(0xFF16A34A) : AppColors.textMuted,
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
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border, width: 0.5),
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
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tutorial.author,
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Row(
            children: [
              const Icon(Icons.favorite_border, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Text(
                '${tutorial.likes}',
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
        ],
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Shimmer.fromColors(
        baseColor: AppColors.border,
        highlightColor: AppColors.bg,
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
