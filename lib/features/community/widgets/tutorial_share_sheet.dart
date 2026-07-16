import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart' show Share;

import '../../../shared/widgets/app_toast.dart';

const _primary = Color(0xFF6366F1);

void showTutorialShareSheet(
  BuildContext context,
  Map<String, dynamic> tutorial,
) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => _ShareSheet(tutorial: tutorial),
  );
}

String _tutorialLink(Map<String, dynamic> tutorial) =>
    'https://dreamingpolar.com/tutorial/${tutorial['id']}';

void _copyLink(BuildContext context, Map<String, dynamic> tutorial) {
  Clipboard.setData(ClipboardData(text: _tutorialLink(tutorial)));
  Navigator.pop(context);
  // 全站统一的浮动圆角胶囊提示（绿勾+柔和阴影），替代原来那条铺满全宽的
  // 深色 SnackBar，跟 app 的卡片视觉语言一致
  showAppToast(context, '链接已复制', ok: true);
}

// share_plus 的 Share.share() 只会调起系统通用分享面板，让用户自己在
// 里面挑要分享到哪个 App——项目里没有接微信 SDK，做不到"直接分享进
// 微信朋友圈"这种专属跳转。微信/朋友圈/微博/QQ 这几个图标本质上都是
// 同一个通用分享入口，只是给用户一个"大概率能找到这几个 App"的视觉
// 提示，不是真的分别拉起各自的原生分享 API
void _shareGeneral(BuildContext context, Map<String, dynamic> tutorial) {
  Navigator.pop(context);
  Share.share(
    '${tutorial['title'] ?? ''}\n\n'
    '${_tutorialLink(tutorial)}\n\n'
    '来自极梦知识平台',
    subject: tutorial['title']?.toString() ?? '',
  );
}

class _ShareSheet extends StatelessWidget {
  final Map<String, dynamic> tutorial;
  const _ShareSheet({required this.tutorial});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = tutorial['title']?.toString() ?? '';
    final username = tutorial['username']?.toString() ?? '';
    final views = (tutorial['views'] as num?)?.toInt() ?? 0;

    return Container(
      decoration: BoxDecoration(
        // 之前深色底写死用了 #1A1A2E 这种偏紫的藏青色，跟全项目深色主题
        // 实际的 cardColor（#2C2C2E，中性灰）不是一个色系——直接读主题
        // cardColor，跟设置页/更多菜单那些 sheet 用的是同一个来源
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 32,
              height: 3,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '分享文章',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark
                  ? Theme.of(context).scaffoldBackgroundColor
                  : const Color(0xFFF8F8FF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark
                    ? Theme.of(context).dividerColor
                    : const Color(0xFFE8E8F0),
                width: 0.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.auto_stories,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '极梦 · $username · $views次阅读',
                        style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 4,
            childAspectRatio: 0.85,
            mainAxisSpacing: 10,
            crossAxisSpacing: 6,
            children: [
              _ShareItem(
                icon: Icons.wechat,
                color: const Color(0xFF07C160),
                label: '微信',
                onTap: () => _shareGeneral(context, tutorial),
              ),
              _ShareItem(
                icon: Icons.people,
                color: const Color(0xFF07C160),
                label: '朋友圈',
                onTap: () => _shareGeneral(context, tutorial),
              ),
              _ShareItem(
                icon: Icons.public,
                color: const Color(0xFFE6162D),
                label: '微博',
                onTap: () => _shareGeneral(context, tutorial),
              ),
              _ShareItem(
                icon: Icons.chat_bubble,
                color: const Color(0xFF12B7F5),
                label: 'QQ',
                onTap: () => _shareGeneral(context, tutorial),
              ),
              _ShareItem(
                icon: Icons.image,
                color: const Color(0xFFFF6B35),
                label: '生成海报',
                onTap: () {
                  Navigator.pop(context);
                  context.push('/tutorial/poster', extra: tutorial);
                },
              ),
              _ShareItem(
                icon: Icons.link,
                color: Colors.grey,
                label: '复制链接',
                onTap: () => _copyLink(context, tutorial),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? Theme.of(context).scaffoldBackgroundColor
                  : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark
                    ? Theme.of(context).dividerColor
                    : const Color(0xFFEBEBEB),
                width: 0.5,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'dreamingpolar.com/tutorial/${tutorial['id']}',
                    style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: () => _copyLink(context, tutorial),
                  child: const Text(
                    '复制',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: _primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                backgroundColor: isDark
                    ? Theme.of(context).scaffoldBackgroundColor
                    : const Color(0xFFF5F5F5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text('取消', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _ShareItem({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
