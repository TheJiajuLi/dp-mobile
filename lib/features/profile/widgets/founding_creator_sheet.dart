import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_service.dart';

const _primary = Color(0xFF6366F1);
const _star = Color(0xFFF59E0B);

// 元老创作者卡片——极稀有身份，只有注册时用邀请码拿到元老标识的用户，在
// 自己主页点头像旁的「元老」标签才能唤出（见 profile_header_widget）。展示
// 元老 → 自动获得极光创作者 → PRO MAX 6 个月体验 → 到期转永久 PRO 的权益说明，
// 并按当前会员真实状态补一行剩余天数/永久已激活
void showFoundingCreatorSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const FoundingCreatorSheet(),
  );
}

class FoundingCreatorSheet extends ConsumerWidget {
  const FoundingCreatorSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = ref.watch(currentUserProvider);
    final membership = user?.membership ?? 'free';
    final expiresAt = user?.membershipExpiresAt;
    // 后端永久会员既可能是 null 也可能是 0
    final permanent = expiresAt == null || expiresAt == 0;

    String? statusLine;
    IconData? statusIcon;
    if (membership == 'pro_max' && !permanent) {
      final days =
          ((expiresAt * 1000 - DateTime.now().millisecondsSinceEpoch) /
                  86400000)
              .ceil()
              .clamp(0, 99999);
      statusLine = '距 PRO MAX 体验结束还有 $days 天';
      statusIcon = Icons.hourglass_bottom_outlined;
    } else if (membership == 'pro' && permanent) {
      statusLine = '永久 PRO 会员已激活';
      statusIcon = Icons.verified_outlined;
    }

    final card = isDark ? const Color(0xFF17171F) : Colors.white;
    final textColor = isDark
        ? const Color(0xFFD1D1D6)
        : const Color(0xFF3A3A3A);

    return Container(
      decoration: BoxDecoration(
        color: card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 0),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A0E2E),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                      color: _primary.withValues(alpha: 0.5),
                      width: 0.5,
                    ),
                  ),
                  child: const Text(
                    '★',
                    style: TextStyle(fontSize: 18, color: _star),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '元老创作者',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                    const Text(
                      'FOUNDING CREATOR',
                      style: TextStyle(
                        fontSize: 9,
                        letterSpacing: 1.4,
                        color: Color(0xFF818CF8),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Icon(Icons.close, size: 22, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '您是极梦元老创作者，已自动获得极光创作者身份。\n\n'
                  '当前享有 PRO MAX 6 个月体验权益，到期后自动转为永久 PRO 会员。',
                  style: TextStyle(fontSize: 14, height: 1.75, color: textColor),
                ),
                if (statusLine != null) ...[
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 13,
                    ),
                    decoration: BoxDecoration(
                      color: _primary.withValues(alpha: isDark ? 0.14 : 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _primary.withValues(alpha: 0.25),
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(statusIcon, size: 17, color: _primary),
                        const SizedBox(width: 8),
                        Text(
                          statusLine,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: _primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
