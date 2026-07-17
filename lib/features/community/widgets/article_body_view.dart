import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/services/pyodide_engine.dart';
import '../../../shared/widgets/tutorial_block_renderer.dart';
import '../../auth/auth_service.dart';
import '../providers/article_provider.dart';

// 正文体控制器——ArticleBodyView 创建并填充，外部目录面板消费。scroll-spy 的
// 当前章节 + 跳转 + 数据集注入态都通过它暴露，不把这些 UI 态塞进数据 provider。
// 手机目录 sheet 和 HD 右侧 180 目录面板都消费同一个实例（由持有方 new 后同时
// 传给中间 Body 面板和右侧目录面板）
class ArticleBodyController {
  // scroll-spy 当前所在章节（toc 下标，-1=还没滚到任何标题）
  final ValueNotifier<int> activeHeadingIndex = ValueNotifier(-1);

  // 数据集静默注入中——chrome 可据此显示「本文包含数据集，正在加载…」提示条
  final ValueNotifier<bool> datasetLoading = ValueNotifier(false);

  // jumpToHeading 的真正实现由 ArticleBodyView 挂进来（它才持有 heading 的
  // GlobalKey）。外部只调 jumpToHeading(tocIndex)
  void Function(int tocIndex)? _jump;
  void attachJump(void Function(int tocIndex) fn) => _jump = fn;
  void jumpToHeading(int tocIndex) => _jump?.call(tocIndex);

  void dispose() {
    activeHeadingIndex.dispose();
    datasetLoading.dispose();
  }
}

// 无壳的「文章正文体」——负责：加载(watch articleProvider) → 遍历 blocks 渲染
// (buildTutorialBlockWidget + 公式编号 + heading 挂 key) → scroll-spy → 数据集
// 静默注入。不含顶栏/底栏/封面/评论等 chrome，那些由各端注入 leading/trailing
// slivers 或在外层包裹。手机阅读页和 HD 中间面板都套用它。
//
// scrollController 外部传入（各端自己 new+dispose）：手机沉浸式 Header 和本
// 组件的 scroll-spy 挂同一个 controller。
class ArticleBodyView extends ConsumerStatefulWidget {
  final String tutorialId;
  final ScrollController scrollController;
  final ArticleBodyController controller;
  // chrome 注入的头部/尾部 sliver——手机: 沉浸 SliverAppBar / 封面 / 作者卡 /
  // 评论预览；HD: 一般为空（顶栏是 Column 里的固定条，不是 sliver）
  final List<Widget> leadingSlivers;
  final List<Widget> trailingSlivers;
  final EdgeInsets contentPadding;
  // 公式自动编号总开关（默认开；仍受每个 latex 块 autoNumber 字段约束）
  final bool autoNumberEquations;
  // scroll-spy 判定"已滚过顶栏"的阈值——手机顶栏 ~140，HD 顶栏更矮可调低
  final double activeHeadingTopThreshold;

  const ArticleBodyView({
    super.key,
    required this.tutorialId,
    required this.scrollController,
    required this.controller,
    this.leadingSlivers = const [],
    this.trailingSlivers = const [],
    this.contentPadding = EdgeInsets.zero,
    this.autoNumberEquations = true,
    this.activeHeadingTopThreshold = 140,
  });

  @override
  ConsumerState<ArticleBodyView> createState() => _ArticleBodyViewState();
}

class _ArticleBodyViewState extends ConsumerState<ArticleBodyView> {
  // 每个 heading 块一个 GlobalKey——scroll-spy 判定位置 + 目录 ensureVisible 跳转
  final Map<int, GlobalKey> _headingKeys = {};
  bool _datasetPreloaded = false;

  @override
  void initState() {
    super.initState();
    widget.controller.attachJump(_jumpToHeading);
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  GlobalKey _headingKeyFor(int blockIndex) =>
      _headingKeys.putIfAbsent(blockIndex, () => GlobalKey());

  // scroll-spy：当前章节 = 最后一个"顶边已滚过阈值"的 heading（用 GlobalKey 的
  // 全局 Y 判断，比 offset 换算稳）
  void _onScroll() {
    final toc = ref.read(articleProvider(widget.tutorialId)).toc;
    if (toc.isEmpty) return;
    final threshold = widget.activeHeadingTopThreshold;
    var active = -1;
    for (var k = 0; k < toc.length; k++) {
      final ctx = _headingKeys[toc[k]['index'] as int]?.currentContext;
      final ro = ctx?.findRenderObject();
      if (ro is! RenderBox || !ro.hasSize) continue;
      final dy = ro.localToGlobal(Offset.zero).dy;
      if (dy <= threshold) {
        active = k;
      } else {
        break;
      }
    }
    final c = widget.controller.activeHeadingIndex;
    if (active != c.value) c.value = active;
  }

  void _jumpToHeading(int tocIndex) {
    final toc = ref.read(articleProvider(widget.tutorialId)).toc;
    if (tocIndex < 0 || tocIndex >= toc.length) return;
    final blockIndex = toc[tocIndex]['index'] as int;
    final ctx = _headingKeys[blockIndex]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      // 标题落在顶栏下方一点，不被顶栏压住
      alignment: 0.08,
    );
  }

  // blocks 首次到手时跑一次：把 isDataset 代码块按序在共享内核里执行，注入 df
  // 等变量，读者随后运行下方代码块时 df 已存在。直接 engine.run 绕过 Pro 门禁
  // ——数据注入是"看文章"的一部分，不是读者主动运行代码
  Future<void> _preloadDatasets(List<dynamic> blocks) async {
    final datasets = blocks
        .whereType<Map>()
        .where((b) => b['type'] == 'code' && b['isDataset'] == true)
        .toList();
    if (datasets.isEmpty || !mounted) return;
    final l10n = AppLocalizations.of(context)!;
    widget.controller.datasetLoading.value = true;
    final engine = ref.read(pyodideEngineProvider);
    for (final b in datasets) {
      final id = b['id']?.toString() ?? 'dataset_${datasets.indexOf(b)}';
      final code = b['content']?.toString() ?? '';
      if (code.trim().isEmpty) continue;
      try {
        await engine.run(
          id,
          code,
          'python',
          l10n,
          timeout: const Duration(seconds: 90),
        );
      } catch (_) {
        // 单个注入失败不影响其它、不打扰读者
      }
    }
    if (mounted) widget.controller.datasetLoading.value = false;
  }

  // 遍历 blocks 渲染：先一遍算 latex 公式编号，再逐块 buildTutorialBlockWidget，
  // heading 挂 GlobalKey。作者本人看自己文章不拦运行(isSelfPreview)
  List<Widget> _buildBlockWidgets(AppLocalizations l10n, ArticleState state) {
    final blocks = state.blocks;
    final eqNums = <int?>[];
    var n = 0;
    for (final b in blocks) {
      if (b is Map &&
          b['type'] == 'latex' &&
          widget.autoNumberEquations &&
          (b['autoNumber'] as bool? ?? true)) {
        eqNums.add(++n);
      } else {
        eqNums.add(null);
      }
    }
    final t = state.tutorial ?? const <String, dynamic>{};
    final isSelf =
        (t['user_id'] as String?) != null &&
        t['user_id'] == ref.read(currentUserProvider)?.id;
    final widgets = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i] as Map;
      final w = buildTutorialBlockWidget(
        context,
        l10n,
        Map<String, dynamic>.from(b),
        readingMode: true,
        isSelfPreview: isSelf,
        equationNumber: eqNums[i],
      );
      widgets.add(
        b['type'] == 'heading'
            ? KeyedSubtree(key: _headingKeyFor(i), child: w)
            : w,
      );
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(articleProvider(widget.tutorialId));

    // blocks 到手后触发一次数据集注入（下一帧，避免在 build 里同步跑）
    if (!_datasetPreloaded && state.blocks.isNotEmpty) {
      _datasetPreloaded = true;
      final blocks = state.blocks;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _preloadDatasets(blocks),
      );
    }

    final l10n = AppLocalizations.of(context)!;
    final Widget bodySliver = state.loading
        ? const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 80),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        : SliverToBoxAdapter(
            child: Padding(
              padding: widget.contentPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _buildBlockWidgets(l10n, state),
              ),
            ),
          );

    return CustomScrollView(
      controller: widget.scrollController,
      slivers: [
        ...widget.leadingSlivers,
        bodySliver,
        ...widget.trailingSlivers,
      ],
    );
  }
}
