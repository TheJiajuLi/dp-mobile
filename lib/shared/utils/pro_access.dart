import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_service.dart';
import '../models/user_model.dart';
import '../widgets/pro_badge.dart';

// 会员判定：pro / pro_max 是付费档；极光创作者（isAuroraCreator）按规则
// 免费获得全部 Pro 权益，也算 Pro
extension ProAccess on UserModel {
  bool get isPro =>
      membership == 'pro' || membership == 'pro_max' || isAuroraCreator;
  bool get isProMax => membership == 'pro_max';
}

// 权限门禁的统一入口——设计原则：不做任何视觉加锁（不灰、不锁图标、不禁用
// 按钮）。功能按钮照常显示，用户"点了之后"才在这里检查：是 Pro 就放行返回
// true；不是就从底部轻柔弹出会员 Sheet 并返回 false，调用方据此中断。
//
//   if (!requirePro(context, ref, feature: '一键导出 PDF')) return;
//   ...继续执行需要 Pro 的操作...
bool requirePro(BuildContext context, WidgetRef ref, {String? feature}) {
  final user = ref.read(currentUserProvider);
  if (user?.isPro ?? false) return true;
  showProUpgradeSheet(context, feature: feature);
  return false;
}

// 需要 Pro Max 的更高档权益（如大视频 >50MB）——同款无视觉加锁，点了才校验
bool requireProMax(BuildContext context, WidgetRef ref, {String? feature}) {
  final user = ref.read(currentUserProvider);
  if (user?.isProMax ?? false) return true;
  showProUpgradeSheet(context, feature: feature, proMax: true);
  return false;
}

// 底部会员 Sheet：解锁提示 + 三条核心权益 + 立即升级 / 暂不。轻柔弹出、
// 不打断心流、不破坏界面美观
void showProUpgradeSheet(
  BuildContext context, {
  String? feature,
  bool proMax = false,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      final ink = isDark ? Colors.white : const Color(0xFF1A1A1A);
      final muted = isDark ? Colors.white60 : const Color(0xFF888888);
      return Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF17171F) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: isDark
              ? Border(
                  top: BorderSide(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 0.5,
                  ),
                )
              : null,
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.of(ctx).padding.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 拖拽条
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF333333)
                      : const Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  feature == null ? '解锁此功能需要' : '「$feature」需要',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                const SizedBox(width: 6),
                ProBadge(membership: proMax ? 'pro_max' : 'pro', fontSize: 11),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              proMax ? '升级极梦 PRO MAX，解锁无限 AI 与大文件' : '升级极梦 PRO，解锁全部创作与阅读增强',
              style: TextStyle(fontSize: 13, color: muted, height: 1.5),
            ),
            const SizedBox(height: 18),
            // 三条核心权益
            if (proMax) ...[
              _benefit(
                ink,
                muted,
                Icons.all_inclusive,
                'AI 生成次数无限',
                '摘要 / 封面 / 头像不再有每日上限',
              ),
              _benefit(
                ink,
                muted,
                Icons.cloud_outlined,
                '20 GB 云端存储',
                '海量音视频、数据集无压力',
              ),
              _benefit(
                ink,
                muted,
                Icons.videocam_outlined,
                '视频上限 100 MB',
                '高清视频随意传 + 新功能优先体验',
              ),
            ] else ...[
              _benefit(
                ink,
                muted,
                Icons.play_circle_outline,
                '他人 Notebook 代码可运行',
                '免费只能看代码，Pro 能交互运行',
              ),
              _benefit(
                ink,
                muted,
                Icons.auto_awesome_outlined,
                '小梦 AI 摘要 · 封面 · 头像',
                '一键生成，告别空白页',
              ),
              _benefit(
                ink,
                muted,
                Icons.workspace_premium_outlined,
                '5 GB 云端存储 · 一键导出 PDF',
                '专属 Pro 角标与创作者字体',
              ),
            ],
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/settings/subscription');
                },
                child: Container(
                  height: 50,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: proGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    '立即升级',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('暂不', style: TextStyle(fontSize: 15, color: muted)),
              ),
            ),
          ],
        ),
      );
    },
  );
}

Widget _benefit(
  Color ink,
  Color muted,
  IconData icon,
  String title,
  String sub,
) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF6D5DF6).withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: const Color(0xFF6D5DF6)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(sub, style: TextStyle(fontSize: 12, color: muted)),
            ],
          ),
        ),
      ],
    ),
  );
}
