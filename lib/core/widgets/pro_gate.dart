import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_service.dart';
import '../utils/membership_utils.dart';

// 包裹需要 Pro 权限的功能入口——有权限直接渲染 child；没权限要么整个
// 隐藏（showLock: false），要么保留原样但半透明+右上角小锁标，点一下
// 提示升级并跳转会员页
class ProGate extends ConsumerWidget {
  final bool Function(String?) check;
  final Widget child;
  final String featureName;
  final bool showLock;

  const ProGate({
    super.key,
    required this.check,
    required this.child,
    required this.featureName,
    this.showLock = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membership = ref.watch(currentUserProvider)?.membership;

    if (check(membership)) return child;

    if (!showLock) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(MembershipUtils.upgradeHint(featureName)),
            action: SnackBarAction(
              label: '升级',
              onPressed: () => context.push('/settings/subscription'),
            ),
          ),
        );
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Opacity(opacity: 0.35, child: child),
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Color(0xFF6366F1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock, size: 10, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
