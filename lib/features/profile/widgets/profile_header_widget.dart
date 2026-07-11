import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/aurora_badge.dart';
import '../../../core/widgets/founding_badge.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/utils/gender_label.dart';
import '../../../shared/widgets/interest_tag.dart';
import '../../../shared/widgets/zodiac_icon.dart';
import '../models/user_profile_model.dart';
import 'profile_painters.dart';

const _primary = Color(0xFF6366F1);
const _ink = Color(0xFF1A1A1A);
const _heroBg = AppColors.bg;
const _profileDarkBg = Color(0xFF1C1C1E);
const _kTabBarRadius = 20.0;

// 头图区——封面背景铺满，内容按截图参考重排：顶部图标行、头像+用户名/
// 认证勾/handle、简介、位置+星座+链接一行（右侧挂编辑资料/关注+发消息
// 按钮）、内容计数统计行、连续创作卡片。不再用固定屏幕高度的 Positioned
// 绝对定位堆叠——高度跟内容走，封面图作为背景层用 Stack 撑到内容实际
// 高度（Stack 默认按非 Positioned 子项——也就是这条内容 Column——来定
// 尺寸，Positioned.fill 的背景层会跟着一起伸缩）
class ProfileHeaderWidget extends StatelessWidget {
  final AppLocalizations l10n;
  final bool isSelfView;
  final bool isMe;
  final String displayUsername;
  final String? displayBio;
  final String? displayLocation;
  final String? displayIpLocation;
  final String? displayOccupation;
  final String? displayGender;
  final ZodiacSign? displayZodiacSign;
  final List<String> interestTags;
  final double topPad;
  final UserProfile profile;
  final bool showBackButton;
  final bool uploadingCover;
  final bool uploadingAvatar;
  final String? coverImageUrl;
  final int creationStreak;
  final int totalLikes;
  final int totalViews;
  final String Function(int) formatCount;
  final List<String> links;
  final Widget avatar;
  final Widget vipBadge;
  final bool startingChat;
  final VoidCallback onBack;
  final VoidCallback onToggleTheme;
  final VoidCallback onAvatarTap;
  final VoidCallback onCoverTap;
  final VoidCallback onLinksTap;
  final Future<void> Function() onEditProfile;
  final VoidCallback onToggleFollow;
  final VoidCallback onStartChat;
  final void Function(String link) onOpenLink;

  const ProfileHeaderWidget({
    super.key,
    required this.l10n,
    required this.isSelfView,
    required this.isMe,
    required this.displayUsername,
    required this.displayBio,
    required this.displayLocation,
    required this.displayIpLocation,
    required this.displayOccupation,
    required this.displayGender,
    required this.displayZodiacSign,
    required this.interestTags,
    required this.topPad,
    required this.profile,
    required this.showBackButton,
    required this.uploadingCover,
    required this.uploadingAvatar,
    required this.coverImageUrl,
    required this.creationStreak,
    required this.totalLikes,
    required this.totalViews,
    required this.formatCount,
    required this.links,
    required this.avatar,
    required this.vipBadge,
    required this.startingChat,
    required this.onBack,
    required this.onToggleTheme,
    required this.onAvatarTap,
    required this.onCoverTap,
    required this.onLinksTap,
    required this.onEditProfile,
    required this.onToggleFollow,
    required this.onStartChat,
    required this.onOpenLink,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      // 默认 Clip.hardEdge 会把下面圆角"卡片沿"故意超出 Stack 底边的
      // 2px 出血裁掉——那 2px 就是专门用来盖住跟下一个 sliver（pinned
      // 的 TabBar）拼接处那条灰线的，不能被裁
      clipBehavior: Clip.none,
      children: [
        // 封面图/渐变纯装饰，排除出语义树——跟 tutorial_detail_screen.dart/
        // column_detail_screen.dart 的封面图同一个坑：图片异步加载完成的
        // relayout 可能跟这个页面自己入场的转场动画抢语义树更新
        Positioned.fill(
          child: ExcludeSemantics(
            child: GestureDetector(
              onTap: isSelfView && !uploadingCover ? onCoverTap : null,
              child: coverImageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: coverImageUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) =>
                          const CoverGradient(),
                    )
                  : const CoverGradient(),
            ),
          ),
        ),
        const Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x33000000), Color(0xCC000000)],
                ),
              ),
            ),
          ),
        ),
        if (uploadingCover)
          const Positioned.fill(
            child: IgnorePointer(
              ignoring: false,
              child: ColoredBox(
                color: Colors.black38,
                child: Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
            ),
          ),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (showBackButton)
                      _heroIconButton(Icons.arrow_back_ios_new, onBack),
                    const Spacer(),
                    if (isSelfView) ...[
                      _heroIconButton(
                        Theme.of(context).brightness == Brightness.dark
                            ? Icons.dark_mode_outlined
                            : Icons.light_mode_outlined,
                        onToggleTheme,
                      ),
                      _heroIconButton(
                        Icons.people_outline,
                        () => context.push('/friends'),
                      ),
                      _heroIconButton(
                        Icons.settings_outlined,
                        () => context.push('/settings'),
                      ),
                    ] else if (links.isNotEmpty)
                      _heroIconButton(Icons.link_rounded, onLinksTap),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        // 极光创作者外圈叠在元老外圈外面——两个身份不互斥，
                        // 极光圈(金)在外/元老圈(极光紫)在内都会显示；只有
                        // 其中一个身份时，另一层直接原样返回 child，不额外
                        // 占位，不会露出多余的空环
                        AuroraAvatarRing(
                          isAuroraCreator: profile.isAuroraCreator,
                          size: 68,
                          child: FoundingAvatarRing(
                            isFoundingCreator: profile.isFoundingCreator,
                            size: 68,
                            child: Container(
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.fromBorderSide(
                                  BorderSide(color: Colors.white, width: 2.5),
                                ),
                              ),
                              child: avatar,
                            ),
                          ),
                        ),
                        if (uploadingAvatar)
                          const CircleAvatar(
                            radius: 34,
                            backgroundColor: Colors.black45,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          ),
                        // VIP 标识挪到头像右上角当角标——不分自己/别人都
                        // 显示，自己会员是真实数据（currentUserProvider，
                        // GET /auth/me 直接返回），看别人主页时目前后端 GET
                        // /auth/users/profile/:identifier 还没把 membership
                        // 字段加进 SELECT 列表，_profile.membership 会先
                        // 恒为 'free'（灰色角标），等后端加了这一列直接生效
                        Positioned(right: -6, top: -4, child: vipBadge),
                        if (isSelfView)
                          Positioned(
                            right: -4,
                            bottom: -4,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: onAvatarTap,
                              child: Container(
                                width: 32,
                                height: 32,
                                alignment: Alignment.center,
                                child: Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: _primary,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.camera_alt,
                                    color: Colors.white,
                                    size: 10,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  displayUsername,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              // 认证徽章——UserProfile.isVerified 目前后端恒为
                              // false，这里只是把渲染逻辑接好，字段一旦上线
                              // 直接生效，不需要再改这里
                              if (profile.isVerified) ...[
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.verified,
                                  size: 16,
                                  color: _primary,
                                ),
                              ],
                              if (profile.isFoundingCreator)
                                const FoundingBadgeSmall(),
                              if (profile.isAuroraCreator)
                                const AuroraBadgeSmall(),
                            ],
                          ),
                          if (profile.handle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              '@${profile.handle}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white60,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                if (interestTags.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: interestTags
                        .map((tag) => InterestTag(label: tag))
                        .toList(),
                  ),
                ],
                if (displayBio?.isNotEmpty == true) ...[
                  const SizedBox(height: 12),
                  Text(
                    displayBio!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (displayGender?.isNotEmpty ?? false)
                            _infoChip(
                              genderIconFor(displayGender!),
                              genderDisplayLabel(l10n, displayGender!),
                            ),
                          if (displayLocation?.isNotEmpty ?? false)
                            _infoChip(
                              Icons.location_on_outlined,
                              displayLocation!,
                            ),
                          if (displayIpLocation?.isNotEmpty ?? false)
                            _infoChip(Icons.public, displayIpLocation!),
                          if (displayOccupation?.isNotEmpty ?? false)
                            _infoChip(Icons.work_outline, displayOccupation!),
                          if (displayZodiacSign != null)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ZodiacIcon(sign: displayZodiacSign!, size: 12),
                                const SizedBox(width: 3),
                                Text(
                                  zodiacDisplayName(l10n, displayZodiacSign!),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          if (links.isNotEmpty)
                            GestureDetector(
                              onTap: () => onOpenLink(links.first),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.language,
                                    size: 12,
                                    color: Colors.white70,
                                  ),
                                  const SizedBox(width: 3),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 150,
                                    ),
                                    child: Text(
                                      links.first
                                          .replaceAll('https://', '')
                                          .replaceAll('http://', ''),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isMe) ...[
                      _headerActionButton(
                        label: l10n.editProfile,
                        filled: true,
                        onTap: () => onEditProfile(),
                      ),
                      const SizedBox(width: 6),
                      _heroIconButton(Icons.link_rounded, onLinksTap),
                    ] else ...[
                      _headerActionButton(
                        label: profile.isFollowing
                            ? l10n.followingAction
                            : l10n.followAction,
                        filled: !profile.isFollowing,
                        onTap: onToggleFollow,
                      ),
                      const SizedBox(width: 6),
                      _headerActionButton(
                        label: l10n.sendMessageAction,
                        filled: false,
                        loading: startingChat,
                        onTap: startingChat ? null : onStartChat,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                if (isSelfView) ...[
                  _buildStatsRow(context, l10n),
                  const SizedBox(height: 14),
                  _buildStreakCard(context, l10n),
                ],
                // 给下面圆角"卡片沿"留出空间——内容到这里为止，圆角沿贴在
                // 正下方，不会互相压着
                const SizedBox(height: _kTabBarRadius),
              ],
            ),
          ),
        ),
        // 网易云那种"卡片浮在头图上"的圆角沿——必须放在头图区自己这个
        // Stack 里（跟封面图渐变同一层，不隔着 Sliver 边界），圆角裁掉的
        // 两个直角三角形才能露出正下方的头图渐变色。之前想靠 tab栏
        // pinned header 自己的圆角去露头图颜色，指望它的绘制能"溢出"到
        // 上一个 sliver 的画面里——NestedScrollView 的普通 sliver 之间
        // 没有这种重叠机制（那是 SliverOverlapAbsorber 专门解决的问题，
        // 这里没用那套），所以完全不显示，圆角形同虚设
        //
        // bottom 故意给 -2 配 22px 高（顶部圆角位置不变，只是底边往下
        // 多铺 2px）：这块纯色矩形跟紧接着的 pinned TabBar 背景理论上是
        // 同一个颜色，但两块分属不同 sliver/RenderObject，各自独立走
        // 反走样光栅化，紧贴边界处会露出一条极淡的灰线（RRect 反走样在
        // 直边上也会画一点半透明像素，不是 TabBar 的 divider，dividerHeight
        // 设成0也去不掉）。让色块本身多铺出 2px 盖过这条拼接线，比继续
        // 在 TabBar 那边找原因更直接可靠
        Positioned(
          left: 0,
          right: 0,
          bottom: -2,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: isDarkMode ? _profileDarkBg : _heroBg,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(_kTabBarRadius),
                  topRight: Radius.circular(_kTabBarRadius),
                ),
              ),
              child: const SizedBox(
                height: _kTabBarRadius + 2,
                width: double.infinity,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _headerActionButton({
    required String label,
    required bool filled,
    VoidCallback? onTap,
    bool loading = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? Colors.white : Colors.transparent,
          border: filled ? null : Border.all(color: Colors.white54),
          borderRadius: BorderRadius.circular(8),
        ),
        child: loading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: filled ? _ink : Colors.white,
                ),
              ),
      ),
    );
  }

  // 内容计数统计行——文章/专栏/文件/收藏/点赞/阅读，纯展示不可点
  // （截图里这行没有任何一项有"可点"的视觉提示，真正的切 tab 交给下面
  // 单独的白底 TabBar）。收藏数没有真实后端聚合数据（只有单条save/unsave
  // 接口，没有"我收藏了多少篇"这个统计），显示"-"而不是编个假数字。
  // 关注/粉丝是真实数据（UserProfile.followingCount/followerCount），
  // 点击跳转到 FollowListScreen，是这行里唯一两个真正"可点"的项
  Widget _buildStatsRow(BuildContext context, AppLocalizations l10n) {
    Widget stat(String value, String label, {VoidCallback? onTap}) {
      final content = Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: Colors.white60),
            ),
          ],
        ),
      );
      if (onTap == null) return content;
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: content,
      );
    }

    final userId = profile.id;

    // 文章/专栏/文件这几个数量本来就是下面 Tab 切换后能直接看到的东西，
    // 跟这一行其它"要点进去才知道"的统计（点赞/阅读/关注/粉丝）放在一起
    // 纯属重复计数、白占一行横向滚动的空间——挪到各自 Tab 内容顶部用
    // 不带 pill 底色的纯文字展示（效仿知乎"创作"页签下方的计数写法），
    // 只在切到那个 Tab 时才看得到，减少头图区一上来就是一整排数字的
    // 视觉噪音
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          stat('-', l10n.tabBookmarksLabel),
          stat(formatCount(totalLikes), l10n.tabLikesLabel),
          stat(formatCount(totalViews), l10n.viewsCountLabel),
          stat(
            '${profile.followingCount}',
            l10n.followingCountLabel,
            onTap: () => context.push('/users/$userId/following'),
          ),
          stat(
            '${profile.followerCount}',
            l10n.followersCountLabel,
            onTap: () => context.push('/users/$userId/followers'),
          ),
        ],
      ),
    );
  }

  // 创作中心入口——原来头图区右上角另有一个独立的"创作者中心"图标按钮，
  // 跟这张卡片功能重叠，去掉那个图标改成直接点这张卡进创作者中心，只有
  // 自己看自己主页时才能点（看别人主页也可能显示这张卡，但点进去应该是
  // 打开自己的创作者中心，不是对方的，容易误解，所以干脆不给点）。
  // 之前这张卡在 creationStreak == 0 时上层完全不渲染——连续创作天数是
  // 0 在没有天天发布内容的账号上其实是常态而不是例外，导致"创作中心"
  // 这个入口经常直接从主页消失、根本摸不到，跟之前极索页邀请回答汇总卡
  // count==0 就整块消失是同一类问题——现在改成 streak==0 时也照样渲染，
  // 只是换成不带🔥文案的朴素版本，保证入口常在
  Widget _buildStreakCard(BuildContext context, AppLocalizations l10n) {
    final hasStreak = creationStreak > 0;
    return GestureDetector(
      onTap: isSelfView ? () => context.push('/creator') : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Text(hasStreak ? '🔥' : '✍️', style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasStreak
                        ? l10n.creationStreakDays(creationStreak)
                        : l10n.creatorCenterEntryLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasStreak
                        ? l10n.creationStreakSubtitle
                        : l10n.creatorCenterEntrySubtitle,
                    style: const TextStyle(fontSize: 11, color: Colors.white60),
                  ),
                ],
              ),
            ),
            if (isSelfView)
              const Icon(Icons.chevron_right, size: 18, color: Colors.white54),
          ],
        ),
      ),
    );
  }

  // 头图信息行的小图标+文字组合——性别/地区/职业公用同一个样式
  Widget _infoChip(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 12, color: Colors.white70),
      const SizedBox(width: 3),
      Text(text, style: const TextStyle(fontSize: 11, color: Colors.white70)),
    ],
  );

  // 头图区里叠在背景上的圆形按钮（返回/汉堡）——半透明白底保证无论背景
  // 是浅色渐变占位还是用户传的任意亮度照片，深色图标都能看清
  // filled:false 给不需要白底圆圈衬托的场景用（比如链接图标）——直接裸
  // 2026-07-06 去掉了原来 BackdropFilter 毛玻璃圆角底，改成裸图标+黑色
  // 投影衬托可见性；2026-07-11 这个投影本身出了问题——Shadow 没给
  // offset，默认零偏移只会让图标往四周晕开一圈模糊重影，看起来像图标
  // 下面叠了个鬼影，不是正常的阴影效果，按反馈直接去掉
  Widget _heroIconButton(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.all(6),
      child: Icon(icon, color: Colors.white, size: 22),
    ),
  );
}
