import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/auth_service.dart';
import '../../column/models/column_model.dart';

const _primary = Color(0xFF6366F1);
const _ink = Color(0xFF1A1A1A);
const _muted = Color(0xFF999999);
const _heroBg = AppColors.bg;
const _profileDarkBg = Color(0xFF1C1C1E);

// 统计数字内联文字排列——文章/获赞/粉丝/关注挨个写在一行，last:true
// 的最后一项右边不再留间距
class ColumnsTabView extends StatelessWidget {
  final AppLocalizations l10n;
  final bool isSelfView;
  final List<ColumnModel> columns;
  final Future<void> Function() onRefresh;
  final VoidCallback onCreateColumn;
  final void Function(ColumnModel column) onColumnTap;
  // 点击 Tab 时才闪现数量，随后收起——由父级 user_profile_screen 控制
  final bool showCount;

  const ColumnsTabView({
    super.key,
    required this.l10n,
    required this.isSelfView,
    required this.columns,
    required this.onRefresh,
    required this.onCreateColumn,
    required this.onColumnTap,
    this.showCount = true,
  });

  @override
  Widget build(BuildContext context) {
    if (columns.isEmpty && !isSelfView) {
      return RefreshIndicator(
        color: _primary,
        onRefresh: onRefresh,
        child: Column(
          children: [
            _tabCountHeader(
              context,
              l10n.columnsCountHeader(columns.length),
              showCount: showCount,
            ),
            Expanded(
              child: _refreshableCenter(
                key: const PageStorageKey('profile-tab-columns-empty'),
                child: Text(
                  l10n.noColumnsCreatedYetPrompt,
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
            ),
          ],
        ),
      );
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final placeholderColor = isDark ? Colors.white54 : const Color(0xFFC7C7CC);
    return RefreshIndicator(
      color: _primary,
      onRefresh: onRefresh,
      child: Column(
        children: [
          _tabCountHeader(
            context,
            l10n.columnsCountHeader(columns.length),
            showCount: showCount,
          ),
          Expanded(
            child: ListView.builder(
              key: const PageStorageKey('profile-tab-columns'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              itemCount: columns.length + (isSelfView ? 1 : 0),
              itemBuilder: (ctx, i) {
                if (isSelfView && i == columns.length) {
                  return GestureDetector(
                    onTap: onCreateColumn,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark
                              ? Colors.white24
                              : const Color(0xFFD1D1D6),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.add_circle_outline,
                            color: placeholderColor,
                            size: 28,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            l10n.createColumnAction,
                            style: TextStyle(
                              fontSize: 13,
                              color: placeholderColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final col = columns[i];
                return ColumnCard(column: col, onTap: () => onColumnTap(col));
              },
            ),
          ),
        ],
      ),
    );
  }
}

// 收藏/点赞等占位 Tab 也要能下拉刷新——RefreshIndicator 得包一个真正
// 可滚动的 Scrollable 才能识别下拉手势，光一个 Center 不够，所以套一层
// 带 AlwaysScrollableScrollPhysics 的 ListView
Widget _refreshableCenter({required Key key, required Widget child}) {
  return ListView(
    key: key,
    physics: const AlwaysScrollableScrollPhysics(),
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 80),
        child: Center(child: child),
      ),
    ],
  );
}

// 文章/专栏/文件这几个数量之前挤在头图区那一整排统计里，跟"效仿知乎"
// 的要求一样改成不带 pill 底色的纯文字，内嵌在各自 Tab 内容最上面——
// 自己/别人主页都会显示（这几个数字本来就是公开信息，隐私设置目前
// 还没有覆盖到"是否隐藏内容数量"这一项）
// showCount=false 时用 AnimatedSize 把高度收成 0，不长期占位——跟
// user_profile_screen 里文章/文件 tab 的 _tabCountHeader 同款"点击闪现"行为
Widget _tabCountHeader(
  BuildContext context,
  String text, {
  bool showCount = true,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return AnimatedSize(
    duration: const Duration(milliseconds: 220),
    curve: Curves.easeOut,
    alignment: Alignment.topCenter,
    child: !showCount
        ? const SizedBox(width: double.infinity)
        : Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 2),
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white38 : Colors.grey[500],
              ),
            ),
          ),
  );
}

// "新建专栏"弹层——名称必填/简介可选，创建成功后回调 onCreated 让调用方
// 重新拉一次专栏列表
void showCreateColumnSheet(
  BuildContext context,
  WidgetRef ref, {
  required String? profileId,
  required Future<void> Function(String userId) onCreated,
}) {
  final l10n = AppLocalizations.of(context)!;
  final nameCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  l10n.createColumnAction,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    if (nameCtrl.text.trim().isEmpty) return;
                    final res = await ref
                        .read(apiClientProvider)
                        .post(
                          '/auth/columns',
                          data: {
                            'name': nameCtrl.text.trim(),
                            'description': descCtrl.text.trim(),
                          },
                        );
                    if (!context.mounted) return;
                    if (res.success) {
                      Navigator.pop(ctx);
                      final userId =
                          profileId ?? ref.read(currentUserProvider)?.id;
                      if (userId != null) await onCreated(userId);
                    } else if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            l10n.actionFailedWithReason('${res.message}'),
                          ),
                        ),
                      );
                    }
                  },
                  child: Text(
                    l10n.createColumnAction,
                    style: const TextStyle(
                      color: _primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.columnNameLabel,
                hintText: l10n.columnNameHint,
                filled: true,
                fillColor: Colors.grey[50],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _primary),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: l10n.columnDescOptionalLabel,
                filled: true,
                fillColor: Colors.grey[50],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _primary),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// Notebook tab 列表项：文件名 + 语言 badge + cells 数量 + 时间
class NotebookListItem extends StatelessWidget {
  final Map<String, dynamic> notebook;
  final VoidCallback onTap;

  const NotebookListItem({
    super.key,
    required this.notebook,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final lang = notebook['lang'] as String? ?? 'python';
    final badgeLabel =
        const {'python': 'PY', 'latex': 'TEX', 'mixed': 'MD'}[lang] ?? 'PY';
    final badgeColor =
        const {
          'python': _primary,
          'latex': Color(0xFFC026D3),
          'mixed': Color(0xFF16A34A),
        }[lang] ??
        _primary;
    final name = notebook['name'] as String? ?? '';
    final cellCount = notebook['cellCount'] as int? ?? 0;
    final updatedAt = (notebook['updatedAt'] as num?)?.toInt() ?? 0;
    final dt = DateTime.fromMillisecondsSinceEpoch(updatedAt * 1000);
    final dateStr =
        '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.description_outlined,
                size: 18,
                color: badgeColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : _ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: badgeColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          badgeLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$cellCount cells',
                        style: const TextStyle(fontSize: 12, color: _muted),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        dateStr,
                        style: const TextStyle(fontSize: 12, color: _muted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: _muted),
          ],
        ),
      ),
    );
  }
}

class ColumnCard extends StatelessWidget {
  final ColumnModel column;
  final VoidCallback onTap;

  const ColumnCard({super.key, required this.column, required this.onTap});

  static const _gradients = [
    [Color(0xFF4F46E5), Color(0xFF818CF8)],
    [Color(0xFF059669), Color(0xFF34D399)],
    [Color(0xFFD97706), Color(0xFFFBBF24)],
    [Color(0xFFDC2626), Color(0xFFF87171)],
  ];

  // 之前是大banner封面+左上角深色圆角标签叠"收录内容·N篇"的样式——
  // 改成跟 tutorial_list_card.dart 一样效仿知乎"创作"页签的列表行：左边
  // 一个小缩略图，右边标题/简介/纯文字元信息，篇数不再单独用一个 pill
  // 底色的标签浮在封面上，并入下面这一排跟浏览/点赞同样朴素的文字里
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ci = column.name.isNotEmpty
        ? column.name.codeUnitAt(0) % _gradients.length
        : 0;
    final gradient = _gradients[ci];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.white12 : const Color(0xFFF0F0F0),
            width: 0.5,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 70,
                height: 66,
                child:
                    column.coverImage != null && column.coverImage!.isNotEmpty
                    ? ExcludeSemantics(
                        child: CachedNetworkImage(
                          imageUrl: column.coverImage!,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) =>
                              _gradBg(gradient),
                        ),
                      )
                    : _gradBg(gradient),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    column.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                    ),
                  ),
                  if (column.description?.isNotEmpty == true) ...[
                    const SizedBox(height: 2),
                    Text(
                      column.description!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Colors.white54
                            : const Color(0xFF8E8E93),
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _stat(
                        isDark,
                        Icons.collections_bookmark_outlined,
                        '${column.articleCount}',
                      ),
                      const SizedBox(width: 12),
                      _stat(
                        isDark,
                        Icons.remove_red_eye_outlined,
                        '${column.viewCount}',
                      ),
                      const SizedBox(width: 12),
                      _stat(
                        isDark,
                        Icons.favorite_outline,
                        '${column.likeCount}',
                      ),
                      const SizedBox(width: 12),
                      _stat(
                        isDark,
                        Icons.bookmark_outline,
                        '${column.saveCount}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gradBg(List<Color> colors) => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      ),
    ),
  );

  Widget _stat(bool isDark, IconData icon, String val) {
    final color = isDark ? Colors.white60 : Colors.grey;
    return Row(
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(val, style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }
}

// TabBar 包成 SliverPersistentHeader 需要的 delegate，背景色跟着
// isDark 走——minExtent/maxExtent 再收紧到 34（42→38→34），让整组 tab
// 尽量贴近上面圆角沿，不用随内容变化
class ProfileTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final bool isDark;
  const ProfileTabBarDelegate({required this.tabBar, required this.isDark});

  @override
  double get minExtent => 34;
  @override
  double get maxExtent => 34;

  // 圆角"卡片沿"是头图区自己 Stack 里的一个装饰层（ProfileHeaderWidget
  // 末尾那个 Positioned），不是这里——这层 pinned header 只负责紧接着
  // 圆角沿之后原样铺开一块同色平面，两者颜色一致、紧贴着，看起来才是
  // 一整块从头图上"浮"出来的圆角卡片。之前想在这里单独裁一次圆角，
  // 指望能透出上一个 sliver（头图）的颜色——NestedScrollView 的普通
  // sliver 之间没有这种重叠机制，圆角背后只会露出页面主背景色，跟这里
  // 的白/深色几乎撞色，圆角形同虚设，所以挪到头图自己的 Stack 里做
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(color: isDark ? _profileDarkBg : _heroBg),
      child: tabBar,
    );
  }

  // tabBar 每次父级 build() 都会 new 一个新实例，按引用比较 (!=) 永远为
  // true——之前这行等于白写，父级任何一次 setState 都会连带把这个 pinned
  // header 重新 build 一遍。只有 isDark 会真的影响这里画出来的东西
  @override
  bool shouldRebuild(covariant ProfileTabBarDelegate oldDelegate) =>
      oldDelegate.isDark != isDark;
}
