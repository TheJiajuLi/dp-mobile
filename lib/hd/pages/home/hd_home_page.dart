import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/community/widgets/article_body_view.dart';
import '../../state/hd_home_state.dart';
import 'hd_article_list_panel.dart';
import 'hd_article_reader_panel.dart';
import 'hd_toc_panel.dart';

// HD 首页三栏：左 280 列表 → 选中 articleId → 中间 ArticleBodyView → 右 180 目录。
// 顶层持有 scrollController + ArticleBodyController，按 selectedId 重建（换文章
// 即换滚动上下文 + 目录联动），中间面板和右侧目录面板共享同一个 bodyController。
//
// 自适应：≥1024 三栏全开；768-1024 收起右侧目录（阅读顶栏出「目录」浮层入口）；
// <768 P3（先按中窄屏处理）。
class HdHomePage extends ConsumerStatefulWidget {
  const HdHomePage({super.key});

  @override
  ConsumerState<HdHomePage> createState() => _HdHomePageState();
}

class _HdHomePageState extends ConsumerState<HdHomePage> {
  String? _id;
  ScrollController? _scrollCtrl;
  ArticleBodyController? _bodyController;

  // selectedId 变了就换文章重建控制器。旧控制器延后到本帧结束再 dispose——先让
  // 旧 reader 面板卸载（ArticleBodyView.dispose 会在还活着的 scrollController 上
  // removeListener），避免在已 dispose 的 controller 上操作
  void _sync(String? id) {
    if (id == _id) return;
    final oldScroll = _scrollCtrl;
    final oldBody = _bodyController;
    _id = id;
    if (id != null) {
      _scrollCtrl = ScrollController();
      _bodyController = ArticleBodyController();
    } else {
      _scrollCtrl = null;
      _bodyController = null;
    }
    if (oldScroll != null || oldBody != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        oldScroll?.dispose();
        oldBody?.dispose();
      });
    }
  }

  @override
  void dispose() {
    _scrollCtrl?.dispose();
    _bodyController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 选中项变化时重建控制器（listen 回调在 build 后触发，setState 再刷新一帧）
    ref.listen<String?>(homeSelectedArticleProvider, (prev, next) {
      setState(() => _sync(next));
    });
    final selectedId = ref.watch(homeSelectedArticleProvider);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final divider = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFE5E5EA);
    final width = MediaQuery.sizeOf(context).width;
    final showToc = width >= 1024; // 三栏全开门槛

    final ready = selectedId != null && _scrollCtrl != null;

    return Row(
      children: [
        const HdArticleListPanel(),
        VerticalDivider(width: 0.5, thickness: 0.5, color: divider),
        Expanded(
          child: ready
              ? HdArticleReaderPanel(
                  key: ValueKey(selectedId),
                  tutorialId: selectedId,
                  scrollController: _scrollCtrl!,
                  bodyController: _bodyController!,
                  showTocButton: !showToc,
                )
              : _EmptyReader(isDark: isDark),
        ),
        if (showToc) ...[
          VerticalDivider(width: 0.5, thickness: 0.5, color: divider),
          ready
              ? HdTocPanel(tutorialId: selectedId, controller: _bodyController!)
              : _TocEmpty(isDark: isDark),
        ],
      ],
    );
  }
}

class _EmptyReader extends StatelessWidget {
  final bool isDark;
  const _EmptyReader({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final bg = isDark
        ? Theme.of(context).scaffoldBackgroundColor
        : const Color(0xFFFAFAF8);
    final muted = isDark ? const Color(0xFF888C9E) : const Color(0xFF999999);
    return Container(
      color: bg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined, size: 48, color: muted),
            const SizedBox(height: 12),
            Text('从左侧选择一篇文章', style: TextStyle(fontSize: 14, color: muted)),
          ],
        ),
      ),
    );
  }
}

class _TocEmpty extends StatelessWidget {
  final bool isDark;
  const _TocEmpty({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final bg = isDark
        ? Theme.of(context).scaffoldBackgroundColor
        : const Color(0xFFF5F5F7);
    return Container(width: 180, color: bg);
  }
}
