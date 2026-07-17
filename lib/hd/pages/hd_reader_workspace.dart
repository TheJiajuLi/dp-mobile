import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/community/widgets/article_body_view.dart';
import 'home/hd_article_reader_panel.dart';
import 'home/hd_toc_panel.dart';

// HD「列表 → 阅读 → 目录」通用工作区——首页、发现共用。左侧列表面板（外部
// 传入，各自的数据源）→ 选中 articleId（外部 provider）→ 中间 ArticleBodyView
// → 右侧目录面板。顶层持 scrollController + ArticleBodyController，按 selectedId
// 重建（换文章即换滚动上下文，中间面板/目录面板共享同一个 bodyController）。
//
// 自适应：≥1024 三栏全开；768-1024 收起右侧目录（阅读顶栏出目录浮层）；
// <768 退化单栏页面栈（列表 ↔ 阅读，阅读顶栏带返回）。
class HdReaderWorkspace extends ConsumerStatefulWidget {
  final Widget listPanel;
  final StateProvider<String?> selectedProvider;
  const HdReaderWorkspace({
    super.key,
    required this.listPanel,
    required this.selectedProvider,
  });

  @override
  ConsumerState<HdReaderWorkspace> createState() => _HdReaderWorkspaceState();
}

class _HdReaderWorkspaceState extends ConsumerState<HdReaderWorkspace> {
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
    ref.listen<String?>(widget.selectedProvider, (prev, next) {
      setState(() => _sync(next));
    });
    final selectedId = ref.watch(widget.selectedProvider);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final divider = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFE5E5EA);
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < 768; // 单栏页面栈
    final showToc = width >= 1024; // 三栏全开

    final ready = selectedId != null && _scrollCtrl != null;

    // <768：单栏——没选中显示列表（全宽），选中后显示阅读（全宽 + 返回）
    if (narrow) {
      return ready
          ? HdArticleReaderPanel(
              key: ValueKey(selectedId),
              tutorialId: selectedId,
              scrollController: _scrollCtrl!,
              bodyController: _bodyController!,
              showTocButton: true,
              onBack: () =>
                  ref.read(widget.selectedProvider.notifier).state = null,
            )
          : widget.listPanel;
    }

    return Row(
      children: [
        SizedBox(width: 280, child: widget.listPanel),
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
        : const Color(0xFFFAFAF8);
    return Container(width: 180, color: bg);
  }
}
