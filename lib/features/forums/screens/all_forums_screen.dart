import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/utils/forum_gradient.dart';
import '../models/forum_model.dart';

const _primary = AppColors.primary;

// 消息页论坛Tab——只显示"我关注的论坛"，不再是浏览全部论坛的入口。
// GET /auth/forums 目前唯一支持的排序是 post_count DESC，也没有
// "只返回我关注的" 这个过滤参数，所以还是拉全量列表，在客户端按
// is_following 筛出关注的这几个——量级上可以接受（论坛数量远小于用户/
// 帖子数量），比让后端专门加一个新接口划算
//
// 关注按钮挪掉了：这个页面现在是纯只读的"我的论坛"列表，取消关注要去
// 论坛主页（ForumHomeScreen）操作，取消后下次回到这个列表会因为
// is_following 变化自动被过滤掉，不需要另外处理"移除"逻辑
class AllForumsScreen extends ConsumerStatefulWidget {
  const AllForumsScreen({super.key});

  @override
  ConsumerState<AllForumsScreen> createState() => _AllForumsScreenState();
}

class _AllForumsScreenState extends ConsumerState<AllForumsScreen> {
  List<ForumModel> _followedForums = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadForums();
  }

  Future<void> _loadForums() async {
    if (!mounted) return;
    if (_followedForums.isEmpty) setState(() => _loading = true);
    final res = await ref.read(apiClientProvider).get('/auth/forums');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        final all = ((res.data['forums'] as List?) ?? [])
            .map(
              (f) => ForumModel.fromJson(Map<String, dynamic>.from(f as Map)),
            )
            .toList();
        _followedForums = all.where((f) => f.isFollowing).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 整页米白底 #FAFAF8，白色分区卡片浮在上面（跟首页/编辑资料一套视觉语言）
    final pageBg = isDark
        ? Theme.of(context).scaffoldBackgroundColor
        : const Color(0xFFFAFAF8);

    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.arrow_back_ios, size: 18),
                  ),
                  Text(
                    l10n.forum,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: _primary),
                    )
                  : _followedForums.isEmpty
                  ? _buildEmptyState(isDark)
                  : RefreshIndicator(
                      color: _primary,
                      onRefresh: _loadForums,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(top: 6, bottom: 24),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 8, 24, 10),
                            child: Text(
                              '${l10n.myFollowedForums} · ${_followedForums.length}',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                                color: isDark
                                    ? Colors.white38
                                    : const Color(0xFF9AA0AB),
                              ),
                            ),
                          ),
                          _forumCard(isDark),
                          const SizedBox(height: 12),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              l10n.unfollowAutoRemove,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.3)
                                    : Colors.grey[400],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // 一张浮起的白色圆角卡片，把关注的论坛按行排进去，行间细分割线
  Widget _forumCard(bool isDark) {
    final rows = <Widget>[];
    for (var i = 0; i < _followedForums.length; i++) {
      if (i > 0) {
        rows.add(
          Divider(
            height: 0.5,
            thickness: 0.5,
            indent: 72,
            endIndent: 16,
            color: Theme.of(context).dividerColor,
          ),
        );
      }
      rows.add(_forumRow(_followedForums[i], isDark));
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).dividerColor, width: 0.5),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.045),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(children: rows),
      ),
    );
  }

  Widget _forumRow(ForumModel forum, bool isDark) {
    final l10n = AppLocalizations.of(context)!;
    final muted = isDark
        ? Colors.white.withValues(alpha: 0.45)
        : const Color(0xFF9AA0AB);
    final hasAvatar = forum.avatar?.isNotEmpty ?? false;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/forum-home/${forum.id}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: hasAvatar
                    ? null
                    : LinearGradient(
                        colors: forumGradientFor(forum.colorIdx),
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                image: hasAvatar
                    ? DecorationImage(
                        image: NetworkImage(forum.avatar!),
                        fit: BoxFit.cover,
                      )
                    : null,
                borderRadius: BorderRadius.circular(13),
              ),
              child: hasAvatar
                  ? null
                  : Center(
                      child: Text(
                        forum.name.isNotEmpty
                            ? forum.name.substring(0, 1)
                            : '论',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    forum.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      _stat(
                        Icons.article_outlined,
                        '${forum.postCount} ${l10n.postsUnit}',
                        muted,
                      ),
                      const SizedBox(width: 12),
                      _stat(
                        Icons.group_outlined,
                        '${forum.followerCount} ${l10n.membersUnit}',
                        muted,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: isDark ? Colors.white24 : const Color(0xFFC7C7CC),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }

  Widget _buildEmptyState(bool isDark) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: _primary.withValues(alpha: isDark ? 0.16 : 0.08),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(
              Icons.forum_outlined,
              size: 34,
              color: _primary.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.noFollowedForums,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : const Color(0xFF555555),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.discoverForumsHint,
            style: TextStyle(fontSize: 13, color: Colors.grey[400]),
          ),
          const SizedBox(height: 22),
          ElevatedButton(
            // search_screen.dart 目前只有 教程/用户/话题/群组 四个Tab，
            // 没有论坛Tab，也没有论坛搜索功能——这里老实跳转到搜索页本身，
            // 不假装能自动切到一个还不存在的论坛Tab
            onPressed: () => context.push('/search'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            child: Text(
              l10n.goSearch,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
