import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../models/user_profile_model.dart';
import 'profile_painters.dart';

const _primary = AppColors.primary;

// 主页不公开（私密账号）时的受限视图——头图+头像+基本信息+关注/私信按钮
// 照常显示，下面用一把锁图标替掉真实内容
class ProfileBlockedWidget extends StatelessWidget {
  final UserProfile profile;
  final AppLocalizations l10n;
  final double topPad;
  final bool isMe;
  final bool showBackButton;
  final bool startingChat;
  final Widget avatar;
  final VoidCallback onBack;
  final VoidCallback onStartChat;
  final VoidCallback onToggleFollow;

  const ProfileBlockedWidget({
    super.key,
    required this.profile,
    required this.l10n,
    required this.topPad,
    required this.isMe,
    required this.showBackButton,
    required this.startingChat,
    required this.avatar,
    required this.onBack,
    required this.onStartChat,
    required this.onToggleFollow,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 真机实测抓到的真正崩溃根因：CoverGradient 自己的注释就说明它是
        // 设计给 Stack 里的 Positioned.fill 用的（靠 Stack 已经解出来的
        // 有限尺寸撑开），但这里直接把它当 Stack 的裸的非定位子项放，Stack
        // 外层又是 Column 直接摆放、没有任何地方给出高度上限——
        // Container(height: double.infinity) 在无边界高度约束下解不出
        // 数值，直接炸 "BoxConstraints forces an infinite height"，然后
        // 每一帧重新布局都再炸一次，表现为疯狂反复的崩溃日志。点一个设置了
        // "主页不公开" 的用户头像、落到这个受限视图，就是这么崩的——
        // 用固定高度的 SizedBox 包一层，配合 Positioned.fill 用法一致
        SizedBox(
          height: 200,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Positioned.fill(child: CoverGradient()),
              if (showBackButton)
                Positioned(
                  top: topPad + 8,
                  left: 8,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                    onPressed: onBack,
                  ),
                ),
              Positioned(
                bottom: -40,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.fromBorderSide(
                        BorderSide(color: Colors.white, width: 3),
                      ),
                    ),
                    child: avatar,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 48),
        Text(
          profile.username,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        if (profile.handle != null) ...[
          const SizedBox(height: 4),
          Text(
            '@${profile.handle}',
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
        const SizedBox(height: 16),
        if (!isMe)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: startingChat ? null : onStartChat,
                icon: startingChat
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _primary,
                        ),
                      )
                    : const Icon(Icons.message_outlined, size: 16),
                label: Text(l10n.sendMessageAction),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _primary,
                  side: const BorderSide(color: _primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: onToggleFollow,
                style: ElevatedButton.styleFrom(
                  backgroundColor: profile.isFollowing
                      ? Theme.of(context).cardColor
                      : _primary,
                  foregroundColor: profile.isFollowing
                      ? Theme.of(context).textTheme.bodyLarge?.color
                      : Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                ),
                child: Text(
                  profile.isFollowing ? l10n.followingAction : l10n.followAction,
                ),
              ),
            ],
          ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 40,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.profileIsPrivate,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
