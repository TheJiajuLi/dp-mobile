import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/pro_badge.dart';
import '../../auth/auth_service.dart';
import '../widgets/aurora_entry_card.dart';

const _primary = Color(0xFF6366F1);
const _darkBg = Color(0xFF0A0A1A);

// 极光计划的达成门槛，跟 AuroraScreen 保持同一份数字，两处都是从这里改，
// 不要各写各的
const auroraNoteTarget = 10;
const auroraLikesSavesTarget = 100;
const auroraFollowerTarget = 50;

class CreatorCenterScreen extends ConsumerStatefulWidget {
  const CreatorCenterScreen({super.key});
  @override
  ConsumerState<CreatorCenterScreen> createState() =>
      _CreatorCenterScreenState();
}

class _CreatorCenterScreenState extends ConsumerState<CreatorCenterScreen> {
  bool _loading = true;
  int _publishedCount = 0;
  int _draftCount = 0;
  int _totalViews = 0;
  // 获赞/收藏没有单独的"收藏数"接口，用点赞数顶替——跟极光计划详情页的
  // 口径保持一致，不是这里独有的简化
  int _totalLikes = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final api = ref.read(apiClientProvider);

    final results = await Future.wait([
      api.get(
        '/auth/tutorials',
        queryParameters: {
          'author': user.username,
          'status': 'published',
          'limit': 50,
        },
      ),
      api.get(
        '/auth/tutorials',
        queryParameters: {
          'author': user.username,
          'status': 'draft',
          'limit': 1,
        },
      ),
    ]);

    if (!mounted) return;

    final publishedRes = results[0];
    var views = 0;
    var likes = 0;
    var publishedTotal = 0;
    if (publishedRes.success && publishedRes.data != null) {
      final list = (publishedRes.data['tutorials'] as List? ?? [])
          .where((j) => (j as Map)['user_id'] == user.id)
          .toList();
      publishedTotal =
          (publishedRes.data['total'] as num?)?.toInt() ?? list.length;
      for (final j in list) {
        views += ((j as Map)['views'] as num?)?.toInt() ?? 0;
        likes += (j['likes'] as num?)?.toInt() ?? 0;
      }
    }

    final draftRes = results[1];
    final draftTotal = draftRes.success && draftRes.data != null
        ? (draftRes.data['total'] as num?)?.toInt() ?? 0
        : 0;

    setState(() {
      _publishedCount = publishedTotal;
      _draftCount = draftTotal;
      _totalViews = views;
      _totalLikes = likes;
      _loading = false;
    });
  }

  String _formatCount(int n) {
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }

  void _soon() => showAppToast(context, '功能即将上线，敬请期待');

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = ref.watch(currentUserProvider);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // 整页米白背景，状态栏图标用深色才看得清（深色模式反过来）
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: isDark ? _darkBg : const Color(0xFFFAFAF8),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: EdgeInsets.zero,
                children: [
                  _buildHero(user, isDark),
                  const SizedBox(height: 18),
                  // 极光创作者进度卡——保留，位置在功能入口上方
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: AuroraEntryCard(
                      noteCount: _publishedCount,
                      noteTarget: auroraNoteTarget,
                      likesSaves: _totalLikes,
                      likesSavesTarget: auroraLikesSavesTarget,
                      followers: user?.followerCount ?? 0,
                      followerTarget: auroraFollowerTarget,
                      isAuroraCreator: user?.isAuroraCreator ?? false,
                      onTap: () => context.push(
                        user?.isAuroraCreator == true
                            ? '/aurora/progress'
                            : '/creator/aurora',
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildToolsSection(isDark),
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildMonthlyCard(isDark),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildRevenueCard(isDark),
                  ),
                  const SizedBox(height: 28),
                ],
              ),
      ),
    );
  }

  // ============ 顶部 Hero（米白，跟全页同背景，不再是黑块）============
  Widget _buildHero(dynamic user, bool isDark) {
    final ink = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final muted = isDark ? Colors.white54 : const Color(0xFF999999);
    return SizedBox(
      width: double.infinity,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.arrow_back_ios_new,
                        size: 18,
                        color: ink,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  _heroAvatar(user),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (user?.username as String?)?.isNotEmpty == true
                              ? user.username as String
                              : '创作者',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: ink,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _handleLine(user),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _buildHeroStats(user, isDark),
            ],
          ),
        ),
      ),
    );
  }

  String _handleLine(dynamic user) {
    final handle = (user?.handle as String?)?.trim();
    final bio = (user?.bio as String?)?.trim();
    final h = (handle != null && handle.isNotEmpty)
        ? '@$handle'
        : '@${user?.username ?? ''}';
    if (bio != null && bio.isNotEmpty) return '$h · $bio';
    return h;
  }

  Widget _heroAvatar(dynamic user) {
    final av = user?.avatar as String?;
    final name = (user?.username as String?) ?? '';
    Widget circle;
    if (av != null && av.isNotEmpty) {
      if (av.startsWith('data:image')) {
        try {
          circle = CircleAvatar(
            radius: 30,
            backgroundImage: MemoryImage(base64Decode(av.split(',').last)),
          );
        } catch (_) {
          circle = _initialAvatar(name);
        }
      } else {
        circle = CircleAvatar(
          radius: 30,
          backgroundImage: CachedNetworkImageProvider(av),
        );
      }
    } else {
      circle = _initialAvatar(name);
    }
    return SizedBox(
      width: 60,
      height: 60,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          circle,
          // ProBadge 自己对免费用户返回空，这里不用判断
          Positioned(
            bottom: -7,
            left: 0,
            right: 0,
            child: Center(child: ProBadge(membership: user?.membership)),
          ),
        ],
      ),
    );
  }

  Widget _initialAvatar(String name) => CircleAvatar(
    radius: 30,
    backgroundColor: _primary,
    child: Text(
      name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  // 顶部四项数据——跟下面「创作工具」白卡统一视觉：一张白底描边卡，四格
  // 用竖细线连在一起，每格一个彩色图标 + 数值 + 标签
  Widget _buildHeroStats(dynamic user, bool isDark) {
    final card = isDark ? const Color(0xFF17171F) : Colors.white;
    final border = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : const Color(0xFFEBEBEB);
    final divider = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : const Color(0xFFF0F0F0);
    Widget vDiv() =>
        VerticalDivider(width: 0.5, thickness: 0.5, color: divider);
    return Container(
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 0.5),
      ),
      clipBehavior: Clip.hardEdge,
      child: IntrinsicHeight(
        child: Row(
          children: [
            _heroStatCell(
              icon: Icons.description_outlined,
              iconBg: const Color(0xFFEEF0FF),
              iconColor: const Color(0xFF6366F1),
              value: _formatCount(_publishedCount),
              label: '作品',
              isDark: isDark,
            ),
            vDiv(),
            _heroStatCell(
              icon: Icons.people_outline,
              iconBg: const Color(0xFFEFF6FF),
              iconColor: const Color(0xFF2563EB),
              value: _formatCount((user?.followerCount as int?) ?? 0),
              label: '粉丝',
              isDark: isDark,
            ),
            vDiv(),
            _heroStatCell(
              icon: Icons.favorite_border,
              iconBg: const Color(0xFFFEECEC),
              iconColor: const Color(0xFFEF4444),
              value: _formatCount(_totalLikes),
              label: '获赞',
              isDark: isDark,
            ),
            vDiv(),
            _heroStatCell(
              icon: Icons.bookmark_border,
              iconBg: const Color(0xFFFEF3C7),
              iconColor: const Color(0xFFD97706),
              // 收藏没有 per-user 聚合接口，先 0 占位
              value: '0',
              label: '收藏',
              isDark: isDark,
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroStatCell({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String value,
    required String label,
    required bool isDark,
  }) {
    final ink = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final muted = isDark ? Colors.white54 : const Color(0xFF888888);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          children: [
            Container(
              width: 38,
              height: 38,
              // 跟「创作工具」图标盒同款：浅色彩底 + 彩色图标（深浅色一致）
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 19, color: iconColor),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: muted)),
          ],
        ),
      ),
    );
  }

  // ============ 功能入口 2×4 网格 ============
  Widget _buildToolsSection(bool isDark) {
    final ink = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final card = isDark ? const Color(0xFF17171F) : Colors.white;
    final border = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : const Color(0xFFEBEBEB);
    final divider = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : const Color(0xFFF0F0F0);
    final greyBg = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : const Color(0xFFF5F5F5);
    final greyIcon = isDark ? Colors.white54 : const Color(0xFF888888);

    Widget vDiv() =>
        VerticalDivider(width: 0.5, thickness: 0.5, color: divider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Text(
            '创作工具',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white54 : const Color(0xFF999999),
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border, width: 0.5),
          ),
          clipBehavior: Clip.hardEdge,
          child: Column(
            children: [
              IntrinsicHeight(
                child: Row(
                  children: [
                    _toolCell(
                      ink: ink,
                      icon: Icons.description_outlined,
                      iconBg: const Color(0xFFEEF0FF),
                      iconColor: const Color(0xFF6366F1),
                      label: '作品管理',
                      dot: _draftCount > 0,
                      onTap: () => context.push('/creator/works'),
                    ),
                    vDiv(),
                    _toolCell(
                      ink: ink,
                      icon: Icons.view_agenda_outlined,
                      iconBg: const Color(0xFFF0FFF5),
                      iconColor: const Color(0xFF16A34A),
                      label: '专栏管理',
                      onTap: () => context.push('/creator/columns'),
                    ),
                    vDiv(),
                    _toolCell(
                      ink: ink,
                      icon: Icons.insights_outlined,
                      iconBg: const Color(0xFFFEF3C7),
                      iconColor: const Color(0xFFD97706),
                      label: '数据分析',
                      onTap: () => context.push('/creator/stats'),
                    ),
                    vDiv(),
                    _toolCell(
                      ink: ink,
                      icon: Icons.account_balance_wallet_outlined,
                      iconBg: const Color(0xFFEFF6FF),
                      iconColor: const Color(0xFF2563EB),
                      label: '收益中心',
                      onTap: _soon,
                    ),
                  ],
                ),
              ),
              Divider(height: 0.5, thickness: 0.5, color: divider),
              IntrinsicHeight(
                child: Row(
                  children: [
                    _toolCell(
                      ink: ink,
                      icon: Icons.workspace_premium_rounded,
                      iconBg: const Color(0xFFFEF3C7),
                      iconColor: Colors.white,
                      iconGradient: proGradient,
                      label: '会员中心',
                      onTap: () => context.push('/subscription/manage'),
                    ),
                    vDiv(),
                    _toolCell(
                      ink: ink,
                      icon: Icons.tune_outlined,
                      iconBg: greyBg,
                      iconColor: greyIcon,
                      label: '创作设置',
                      onTap: () => context.push('/creator/settings'),
                    ),
                    vDiv(),
                    _toolCell(
                      ink: ink,
                      icon: Icons.menu_book_outlined,
                      iconBg: greyBg,
                      iconColor: greyIcon,
                      label: '创作指南',
                      onTap: () => context.push('/creator/guide'),
                    ),
                    vDiv(),
                    _toolCell(
                      ink: ink,
                      icon: Icons.person_add_alt_outlined,
                      iconBg: greyBg,
                      iconColor: greyIcon,
                      label: '邀请好友',
                      onTap: () => context.push('/invite-list'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _toolCell({
    required Color ink,
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String label,
    required VoidCallback onTap,
    bool dot = false,
    // 会员中心用品牌紫金渐变把入口"深化"出来——比其它扁平色块更抢眼
    Gradient? iconGradient,
  }) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: iconGradient == null ? iconBg : null,
                      gradient: iconGradient,
                      borderRadius: BorderRadius.circular(11),
                      boxShadow: iconGradient == null
                          ? null
                          : [
                              BoxShadow(
                                color: const Color(
                                  0xFF6D5DF6,
                                ).withValues(alpha: 0.28),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                    ),
                    child: Icon(icon, size: 19, color: iconColor),
                  ),
                  if (dot)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEF4444),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(label, style: TextStyle(fontSize: 11, color: ink)),
            ],
          ),
        ),
      ),
    );
  }

  // ============ 本月数据卡 ============
  Widget _buildMonthlyCard(bool isDark) {
    final ink = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final muted = isDark ? Colors.white54 : const Color(0xFF999999);
    final card = isDark ? const Color(0xFF17171F) : Colors.white;
    final border = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : const Color(0xFFEBEBEB);

    Widget stat(String value, String label) {
      return Expanded(
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: muted)),
            const SizedBox(height: 3),
            // 没有本月趋势接口，用「—」占位（不显示假的 ↑%）
            Text('—', style: TextStyle(fontSize: 11, color: muted)),
          ],
        ),
      );
    }

    final followers = ref.watch(currentUserProvider)?.followerCount ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '本月数据',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _soon,
                child: const Text(
                  '查看详情',
                  style: TextStyle(fontSize: 13, color: _primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              stat(_formatCount(_totalViews), '浏览量'),
              stat(_formatCount(_totalLikes), '获赞'),
              // 无本月新增粉丝接口，用总粉丝数顶替
              stat(_formatCount(followers), '新粉丝'),
              // 代码运行无数据源，0 占位
              stat('0', '代码运行'),
            ],
          ),
        ],
      ),
    );
  }

  // ============ 本月收益卡 ============
  Widget _buildRevenueCard(bool isDark) {
    final ink = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final muted = isDark ? Colors.white54 : const Color(0xFF999999);
    final card = isDark ? const Color(0xFF17171F) : Colors.white;
    final border = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : const Color(0xFFEBEBEB);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '本月收益',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _soon,
                child: const Text(
                  '明细',
                  style: TextStyle(fontSize: 13, color: _primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 无收益/提现接口，¥0.00 占位
                    Text(
                      '¥0.00',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text('可提现', style: TextStyle(fontSize: 12, color: muted)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: _soon,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    '提现',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
