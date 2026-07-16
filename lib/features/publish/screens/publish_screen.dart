import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_client.dart';
import '../../../core/profile_refresh_signal.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/services/pyodide_engine.dart';
import '../../../shared/utils/pro_access.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../auth/auth_service.dart';
import '../models/block_model.dart';
import '../widgets/block_card.dart';
import '../widgets/column_picker_sheet.dart';
import '../widgets/cover_picker_sheet.dart';
import '../widgets/formatting_toolbar.dart';
import '../widgets/preview_drawer.dart';
import '../widgets/publish_meta_sheet.dart';
import '../widgets/publish_toolbar.dart';
import '../widgets/xmeng_write_sheet.dart';
import 'import_browser_screen.dart';

const _primary = Color(0xFF6366F1);
const _ink = Color(0xFF1A1A1A);
const _bg = Color(0xFFFAFAF8);
const _muted = Color(0xFF999999);

class PublishScreen extends ConsumerStatefulWidget {
  // 非空时是"编辑已有教程"——由创作者中心的作品管理页跳转进来（编辑已
  // 发布/草稿内容），会先拉一遍这篇教程的完整数据回填进编辑器，保存时
  // 走 PUT 更新原教程，不是再 POST 建一篇新的
  final String? tutorialId;
  // 从别处（如 Notebook 一键发布）带一批 block 预填进新文章——直接传
  // EditorBlock 对象（不走 JSON：outputContent/outputType 不在 toJson 里，
  // JSON 会丢）。只在新建（tutorialId 为空）时生效，不覆盖编辑已有教程
  final String? initialTitle;
  final List<EditorBlock>? initialBlocks;
  const PublishScreen({
    super.key,
    this.tutorialId,
    this.initialTitle,
    this.initialBlocks,
  });
  @override
  ConsumerState<PublishScreen> createState() => _PublishScreenState();
}

class _PublishScreenState extends ConsumerState<PublishScreen> {
  final _titleCtrl = TextEditingController();
  final _summaryCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  // 「发布前预览」要能从发布按钮里程序化打开右侧预览抽屉，用它拿 Scaffold
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  final List<EditorBlock> _blocks = [];
  final List<String> _tags = [];
  // 本次编辑会话里新上传到 COS 的文件 id（封面/正文图片/视频/音频/文件）。
  // 退出时如果没保存草稿/发布，就把这些还没跟文章绑定的孤儿文件删掉；
  // 保存/发布成功后清空（文件已绑定文章，不该再删）。只追踪本次新上传的，
  // 编辑模式下不碰文章原有的文件
  final List<String> _uploadedFileIds = [];
  bool _saving = false;
  bool _generatingSummary = false;
  // 创作设置（SharedPreferences）——新建代码块默认语言、发布时是否自动生成摘要
  String _defaultCodeLang = 'python';
  bool _autoSummary = false;
  String? _coverImageUrl;
  // 编辑模式下拉取原教程数据期间显示 loading，拉完之前不能让用户看到/
  // 误操作一个空白编辑器
  bool _loadingExisting = false;
  // 创建成功之后记下后端分配的 id，同一次编辑会话里再按"存草稿"就走
  // PUT 更新这一篇，不会每按一次都 POST 出一篇新的重复草稿
  String? _editingTutorialId;
  // 底部工具栏里"当前选中"的高亮态——没有真的去接每个 block 内部输入框
  // 的 focus 变化（链路太长），退而求其次：跟着"最近一次点了哪个类型的
  // 加内容按钮"走，默认高亮"文字"，跟刚打开发布页时只有一个文字 block
  // 的初始状态对上
  BlockType _activeToolbarType = BlockType.text;
  // 格式工具栏（粗体/颜色/字体）要知道"当前在编辑哪个 block"——这个链路
  // 现在真的接上了（BlockCard 的 FocusNode 监听器），上面那条"链路太长"
  // 的注释是旧决定，格式工具栏这个新功能必须要有这份状态才能工作
  String? _focusedBlockId;
  // 辅助栏（字体/颜色那行 BlockFormattingToolbar）开关——默认收起，聚焦
  // 文字/标题 block 后由工具栏右侧独立的「Aa」图标显式点开，不再一聚焦
  // 就自动弹出来占地方
  bool _formatBarExpanded = false;
  // 代码块的语言选择条（CodeLangBar）开关——跟 _formatBarExpanded 完全
  // 同一套路，聚焦代码 block 后由工具栏右侧的语言图标点开
  bool _langBarExpanded = false;
  // 顶部信息区（标题栏+封面/摘要/更多设置）折叠开关——默认展开，露出标题/
  // 发布/摘要那一整块（尖朝上），点它收起成一个朝下的尖把高度让给正文编辑区
  bool _headerExpanded = true;
  // Block 之间的"+"插入分隔条——静止编辑时收起（几乎无间距，减少干扰），
  // 滚动时展开（露出插入点）；滚动停止1.5秒后自动收起，靠 Timer 而不是
  // 裸的 Future.delayed，方便滚动一停又立刻再滚时取消上一个还没触发的
  // 收起动作，不然会出现"手指还在滚，分隔条却被上一次的延时收起了"
  bool _showDividers = false;
  Timer? _hideDividersTimer;

  EditorBlock? get _focusedBlock {
    for (final b in _blocks) {
      if (b.id == _focusedBlockId) return b;
    }
    return null;
  }

  // 专栏
  String? _selectedColumnId;
  String? _selectedColumnName;

  // 标题植入
  String _subtitle = '';
  String _seriesTag = '';
  String _issueNumber = '';

  // 空白引导区——"今日灵感"现在由小梦每 24 小时生成一批（5 条创作话题），
  // 缓存进 SharedPreferences；点刷新强制重新生成。显示时顺序轮换一条，跟
  // 老版"点刷新换一条"的视觉体验一致，只是内容从硬编码改成 AI 动态生成
  int _inspirationIndex = 0;
  List<String> _inspirations = _defaultInspirations();

  // 复用小梦推荐问题的逻辑：给知识创作社区生成 5 个今日创作灵感话题
  static const _inspirationPrompt =
      '为一个数学/编程/数据科学知识创作社区，'
      '生成5个今日创作灵感话题，适合写成知识文章。\n\n'
      '要求：\n'
      '- 每个话题20字以内\n'
      '- 具体有深度，不要泛泛而谈\n'
      '- 涵盖不同领域（数学/Python/ML/统计/算法）\n'
      '- 直接输出5个话题\n'
      '- 每行一个，不要编号\n'
      '- 不要任何其他文字';

  // 离线/失败时的兜底，保证卡片永远有内容可显示
  static List<String> _defaultInspirations() => [
    '贝叶斯定理在医学检验中的应用',
    'Python 数据清洗实战技巧',
    '梯度下降算法直觉理解',
    '信息熵与机器学习的关系',
    '图神经网络入门指南',
  ];

  // 24 小时缓存：没过期直接用缓存，过期/无缓存才调小梦重新生成、写回缓存；
  // 生成失败或离线则回落到 _defaultInspirations，不打断用户
  Future<void> _loadInspirations() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt('inspiration_last_refresh') ?? 0;
    final cached = prefs.getStringList('inspiration_cache');
    final elapsed = DateTime.now().millisecondsSinceEpoch - last;
    if (cached != null && cached.isNotEmpty && elapsed <= 24 * 60 * 60 * 1000) {
      if (mounted) {
        setState(() {
          _inspirations = cached;
          _inspirationIndex = 0;
        });
      }
      return;
    }
    try {
      final res = await ref
          .read(apiClientProvider)
          .post(
            '/auth/xmeng/chat',
            data: {
              'messages': [
                {'role': 'user', 'content': _inspirationPrompt},
              ],
            },
            options: Options(receiveTimeout: const Duration(seconds: 60)),
          );
      if (res.success) {
        final text = (res.data as Map?)?['message'] as String? ?? '';
        // 按行拆、去空、顺手剥掉模型可能自作主张加的编号/项目符号，取前 5 条
        final lines = text
            .split('\n')
            .map(
              (e) =>
                  e.trim().replaceFirst(RegExp(r'^(\d+[.、)]\s*|[-•*]\s*)'), ''),
            )
            .where((e) => e.isNotEmpty)
            .take(5)
            .toList();
        if (lines.isNotEmpty) {
          await prefs.setStringList('inspiration_cache', lines);
          await prefs.setInt(
            'inspiration_last_refresh',
            DateTime.now().millisecondsSinceEpoch,
          );
          if (mounted) {
            setState(() {
              _inspirations = lines;
              _inspirationIndex = 0;
            });
          }
          return;
        }
      }
    } catch (_) {
      // 网络/解析异常都走兜底
    }
    if (mounted) {
      setState(() {
        _inspirations = _defaultInspirations();
        _inspirationIndex = 0;
      });
    }
  }

  // 刷新按钮：清掉时间戳让 24 小时判定必过期，再走一次加载 = 强制重新生成
  Future<void> _refreshInspirations() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('inspiration_last_refresh');
    await _loadInspirations();
  }

  Future<void> _askXmeng() async {
    // 已经有标题/正文了：小梦转去建议标题；空白编辑器才走"帮我写"——对话式
    // 问答生成整篇文章再填入（见 XmengWriteSheet）
    if (_titleCtrl.text.isNotEmpty ||
        _blocks.any((b) => b.content.isNotEmpty)) {
      await _aiSuggestTitles();
      return;
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => XmengWriteSheet(onFill: _fillFromXmeng),
    );
  }

  // 小梦生成的内容填入编辑器：空编辑器（没标题、所有 block 都空）→ 整个替换；
  // 已经有内容 → 追加到后面（不毁掉用户已写的）。XmengBlock 是纯数据规格，
  // 这里才用 _uid() 造成真正带 FocusNode 的 EditorBlock
  void _fillFromXmeng(List<XmengBlock> specs) {
    if (specs.isEmpty) return;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    var i = 0;
    final newBlocks = specs
        .map(
          (s) => EditorBlock(
            id: 'block_${stamp}_${_blocks.length}_${i++}',
            type: s.type,
            content: s.content,
            language: s.language ?? 'python',
            headingLevel: s.headingLevel ?? 2,
          ),
        )
        .toList();

    final editorEmpty =
        _titleCtrl.text.trim().isEmpty &&
        _blocks.every(
          (b) =>
              b.content.trim().isEmpty &&
              (b.imageUrl?.isEmpty ?? true) &&
              b.fileName == null,
        );

    setState(() {
      if (editorEmpty) {
        for (final b in _blocks) {
          b.focusNode.dispose();
        }
        _blocks
          ..clear()
          ..addAll(newBlocks);
      } else {
        _blocks.addAll(newBlocks);
      }
      _activeToolbarType = newBlocks.first.type;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      newBlocks.first.focusNode.requestFocus();
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          editorEmpty ? 0 : _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _aiSuggestTitles() async {
    final content = [
      if (_titleCtrl.text.isNotEmpty) _titleCtrl.text,
      ..._blocks.where((b) => b.content.isNotEmpty).map((b) => b.content),
    ].join('\n');

    try {
      final res = await ref
          .read(apiClientProvider)
          .post('/auth/xmeng/title', data: {'content': content, 'tags': _tags});

      if (!res.success || !mounted) return;

      final titles = List<String>.from(
        (res.data as Map?)?['titles'] as List? ?? [],
      );
      if (titles.isEmpty) return;

      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.auto_awesome, size: 20, color: _primary),
                  SizedBox(width: 8),
                  Text(
                    '小梦为你生成了几个标题',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                '点击即可应用',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 14),
              ...titles.map(
                (t) => GestureDetector(
                  onTap: () {
                    setState(() => _titleCtrl.text = t);
                    Navigator.pop(ctx);
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAFAF8),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE5E5EA)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            t,
                            style: const TextStyle(fontSize: 14, height: 1.4),
                          ),
                        ),
                        const Icon(
                          Icons.north_west,
                          size: 14,
                          color: Colors.grey,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        showAppToast(context, '小梦开小差了，请重试');
      }
    }
  }

  @override
  void initState() {
    super.initState();
    // 不再默认塞一个空文字 block——一打开就是空白容易让人不知道从哪
    // 下手，改成"快速开始"引导区（_buildEmptyState），blocks 真的空的
    // 时候才显示，加了第一个 block 之后就跟正常编辑流程一样了
    if (widget.tutorialId != null) {
      _loadExisting(widget.tutorialId!);
    } else if (widget.initialBlocks != null) {
      // Notebook 一键发布等场景：用带进来的 block 预填新文章
      if (widget.initialTitle != null) _titleCtrl.text = widget.initialTitle!;
      _blocks.addAll(widget.initialBlocks!);
    }
    _loadCreatorSettings();
    _loadInspirations();
  }

  // 读取「创作设置」里的两项偏好并落地：
  //  · creator_ai_code_lang  → 新建代码块的默认语言（AI 生成/解释代码时
  //    block_card 的 prompt 也用 block.language，自动跟着走）
  //  · creator_ai_auto_summary → 发布时摘要为空则自动生成（见 _publish）
  //
  // 注意：不再读 creator_default_block 在进入页面时预置任何块——一进来就
  // 自动塞一个空块（尤其是代码块）会盖住「快速开始」欢迎引导（用户反馈）。
  // 新建文章一律保持空状态，由用户从引导区显式点选类型来加第一个块
  Future<void> _loadCreatorSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _defaultCodeLang = prefs.getString('creator_ai_code_lang') ?? 'python';
    _autoSummary = prefs.getBool('creator_ai_auto_summary') ?? false;
  }

  Future<void> _loadExisting(String id) async {
    setState(() => _loadingExisting = true);
    final res = await ref.read(apiClientProvider).get('/auth/tutorials/$id');
    if (!mounted) return;
    if (res.success && res.data != null) {
      final t = res.data as Map;
      _titleCtrl.text = t['title']?.toString() ?? '';
      _summaryCtrl.text = t['summary']?.toString() ?? '';
      _coverImageUrl = (t['cover_image']?.toString().isNotEmpty ?? false)
          ? t['cover_image'].toString()
          : null;
      _tags
        ..clear()
        ..addAll(((t['tags'] as List?) ?? []).map((e) => e.toString()));
      _blocks
        ..clear()
        ..addAll(
          ((t['blocks'] as List?) ?? []).map(
            (b) => EditorBlock.fromJson(Map<String, dynamic>.from(b as Map)),
          ),
        );
      _editingTutorialId = id;
    } else {
      showAppToast(context, '加载失败：${res.message}');
    }
    setState(() => _loadingExisting = false);
  }

  // 统一入口，BlockCard 不用关心 Pyodide 还没就绪、SQL 要不要包装这些
  // 细节，只管拿到一份 List<{type, content}> 结果。javascript 走的是
  // 完全不同的直接 evaluateJavascript 分支（跟 Notebook 一致），不经过
  // compiler.js/Pyodide——那只是个 Python 运行时，不是多语言沙箱。
  // 实际执行现在全部委托给全局共享的 PyodideEngine（见
  // shared/services/pyodide_engine.dart），不再自己维护一份隐藏
  // WebView/onRunResult 桥接——SQL 包装、60 秒就绪等待、超时兜底这些
  // 细节都在引擎内部，跟 Notebook 是同一份实现，不会跑偏
  Future<List<Map<String, dynamic>>> _runBlockCode(
    String blockId,
    String code,
    String language,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    if (language == 'html' || language == 'markdown') {
      return [
        {'type': 'info', 'content': l10n.unsupportedCellType},
      ];
    }
    final engine = ref.read(pyodideEngineProvider);
    if (language == 'javascript') {
      return engine.runJavaScript(code);
    }
    return engine.run(blockId, code, language, l10n);
  }

  String _uid() =>
      'block_${DateTime.now().millisecondsSinceEpoch}_${_blocks.length}';

  void _addBlock(BlockType type) {
    final newBlock = _createBlock(type);
    if (newBlock == null) return;
    setState(() {
      _activeToolbarType = type;
      _blocks.add(newBlock);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 光标跳到新block——只有text/heading/callout这几种把focusNode接到
      // 了真正的输入框上（block_card.dart），其它类型（图片/代码等）
      // requestFocus 没有对应输入框接收，是个安全的空操作
      newBlock.focusNode.requestFocus();
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  // block之间/最后一个block下方的"+"分隔条插入——跟_addBlock共用同一份
  // Pro权益校验+构造逻辑，区别只是插进指定下标而不是永远追加到末尾，
  // 也不需要_addBlock那段"滚到列表底部"的收尾（插入点本来就在可视区里）
  EditorBlock? _createBlock(BlockType type) {
    // 音频/视频块是 Pro 权益——按设计原则按钮照常显示，点了才校验，
    // 非 Pro 弹会员 Sheet，不新建块
    if ((type == BlockType.audio || type == BlockType.video) &&
        !requirePro(context, ref, feature: '音视频发布')) {
      return null;
    }
    return EditorBlock(
      id: _uid(),
      type: type,
      // 代码块默认语言取「创作设置」里的 AI 默认代码语言
      language: type == BlockType.code ? _defaultCodeLang : null,
    );
  }

  void _insertBlockAt(int index, BlockType type) {
    final newBlock = _createBlock(type);
    if (newBlock == null) return;
    setState(() {
      _activeToolbarType = type;
      _blocks.insert(index, newBlock);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      newBlock.focusNode.requestFocus();
    });
  }

  // EditorBlock.type 是 final 的（构造后不可变），text↔heading 互转只能
  // 换成一个新实例——保留 id/content/格式字段，旧 FocusNode 要先 dispose
  // 掉（不然每转一次泄漏一个），新实例的 FocusNode 立刻要回焦点，不然
  // 用户点了 H1 之后输入框会看起来突然失焦
  void _convertHeading(String blockId, int? headingLevel) {
    final index = _blocks.indexWhere((b) => b.id == blockId);
    if (index == -1) return;
    final old = _blocks[index];
    final replacement = EditorBlock(
      id: old.id,
      type: headingLevel == null ? BlockType.text : BlockType.heading,
      content: old.content,
      headingLevel: headingLevel ?? old.headingLevel,
      isBold: old.isBold,
      isItalic: old.isItalic,
      isUnderline: old.isUnderline,
      isStrike: old.isStrike,
      textColorValue: old.textColorValue,
      highlightColorValue: old.highlightColorValue,
      fontFamily: old.fontFamily,
      fontSizeStep: old.fontSizeStep,
      lineHeightStep: old.lineHeightStep,
    );
    old.focusNode.dispose();
    setState(() {
      _blocks[index] = replacement;
      _focusedBlockId = replacement.id;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      replacement.focusNode.requestFocus();
    });
  }

  // /auth/import/url 和内置浏览器那条路（/auth/import/html）返回的都是
  // 同一套 {title, summary, blocks, cover_image, platform, block_count}
  // 形状，回填编辑器 + 成功提示这部分逻辑两条路完全一样，抽出来共用，
  // 不写两份
  void _applyImportResult(Map<String, dynamic> data) {
    final l10n = AppLocalizations.of(context)!;
    final newBlocks = (data['blocks'] as List? ?? [])
        .map((b) => EditorBlock.fromJson(Map<String, dynamic>.from(b as Map)))
        .toList();

    // _blocks 是 final 的，不能整个重新赋值——旧 block 的 FocusNode
    // 要先 dispose 掉，不然每导入一次泄漏一批
    for (final b in _blocks) {
      b.focusNode.dispose();
    }
    setState(() {
      _titleCtrl.text = data['title']?.toString() ?? _titleCtrl.text;
      _summaryCtrl.text = data['summary']?.toString() ?? _summaryCtrl.text;
      _blocks
        ..clear()
        ..addAll(newBlocks);
      if (data['cover_image'] != null) {
        _coverImageUrl = data['cover_image'].toString();
      }
    });

    final platform = data['platform']?.toString() ?? 'general';
    final platformName = switch (platform) {
      'zhihu' => l10n.importPlatformZhihu,
      'wechat' => l10n.importPlatformWechat,
      'paste' => l10n.importPlatformGeneral,
      _ => l10n.importPlatformGeneral,
    };
    final count = (data['block_count'] as num?)?.toInt() ?? newBlocks.length;

    if (!mounted) return;
    showAppToast(
      context,
      l10n.importSuccessMessage(count, platformName),
      ok: true,
    );
  }

  // 内置浏览器导入——URL 直接抓取在知乎/公众号这类反爬平台经常被 403
  // 拒绝，这是备选方案：用户在内嵌浏览器里自己翻到文章页，把当前页面
  // 已经渲染好的 DOM 发给 /auth/import/html 解析
  Future<void> _openImportBrowser() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const ImportBrowserScreen()),
    );
    if (result != null && mounted) _applyImportResult(result);
  }

  void _deleteBlock(String id) {
    final removed = _blocks.where((b) => b.id == id);
    for (final b in removed) {
      b.focusNode.dispose();
    }
    setState(() => _blocks.removeWhere((b) => b.id == id));
  }

  // 空 block 按 Backspace/Delete 触发——删掉第 i 个 block 并把焦点交回
  // 上一个 block，光标落点交给 Flutter 自己的默认行为（上一个 block 的
  // TextFormField 不受这次删除影响、没有被重建，失焦前的光标位置本来
  // 就还在），不用手动去摆 TextSelection
  void _deleteBlockAndFocusPrevious(int i) {
    if (i < 0 || i >= _blocks.length) return;
    // 上一个 block 优先；删的是第一个就把焦点交给删除后的新首块（还有的话），
    // 只剩这一个空 block 就直接删掉、不补任何东西、焦点自然落空
    final target = i > 0
        ? _blocks[i - 1].focusNode
        : (_blocks.length > 1 ? _blocks[i + 1].focusNode : null);
    _deleteBlock(_blocks[i].id);
    target?.requestFocus();
  }

  // ReorderableListView 的 onReorder 回调里，newIndex 是"还没移除
  // oldIndex 那一项"时的目标下标——往下拖的话要先减 1，不然会多移一格
  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final b = _blocks.removeAt(oldIndex);
      _blocks.insert(newIndex, b);
    });
  }

  // 上下箭头：调用方传的 j 已经是移除 i 之后那份列表里的最终目标下标
  // （相邻交换，i 和 j 本来就只差 1），直接 removeAt+insert，不需要
  // 再调整下标——跟上面 _onReorder 的下标含义不一样，拆开两个函数，
  // 不靠 diff 大小去猜调用方是谁
  void _swapBlocks(int i, int j) {
    setState(() {
      final b = _blocks.removeAt(i);
      _blocks.insert(j, b);
    });
  }

  Future<void> _saveDraft() async => _save('draft');

  Future<void> _publish() async {
    if (_titleCtrl.text.trim().isEmpty) {
      final l10n = AppLocalizations.of(context)!;
      showAppToast(context, l10n.pleaseEnterNoteTitle);
      return;
    }
    // 「创作设置」开了自动摘要、且摘要还空着：发布前先让小梦生成一版。
    // 只对 Pro 用户静默触发——非 Pro 不弹订阅 Sheet 打断发布（摘要本是
    // Pro 权益），直接跳过继续发布
    final isPro = ref.read(currentUserProvider)?.isPro ?? false;
    if (_autoSummary && isPro && _summaryCtrl.text.trim().isEmpty) {
      await _aiGenerateSummary();
      if (!mounted) return;
    }
    // 创作设置「发布前预览」——开启时先弹读者预览抽屉（带"确认发布"），
    // 让作者过一眼再发；关闭时直接发布
    final prefs = await SharedPreferences.getInstance();
    final showPreview = prefs.getBool('creator_show_preview') ?? true;
    if (showPreview) {
      _scaffoldKey.currentState?.openEndDrawer();
    } else {
      await _save('published');
    }
  }

  // 预览抽屉里点"确认发布"——再校验一次标题（可能是从预览眼睛图标进来的、
  // 标题还空着）后真正发布
  Future<void> _doPublish() async {
    if (_titleCtrl.text.trim().isEmpty) {
      final l10n = AppLocalizations.of(context)!;
      showAppToast(context, l10n.pleaseEnterNoteTitle);
      return;
    }
    await _save('published');
  }

  Future<void> _save(String status) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _saving = true);
    try {
      // 实测确认（2026-07-05）：blocks 字段要传原始数组，传
      // jsonEncode(...) 得到的字符串会被后端静默丢弃——创建和读取接口
      // 拿到的都是 blocks: []，连一个最简单的 text block 都不例外
      final blocksJson = _blocks.map((b) => b.toJson()).toList();
      // 读取创作者设置里的转载/评论/下载偏好，随发布/更新一起落库。
      // 都默认 true（允许）——跟后端 allow_repost 默认 1、创作设置的
      // 开关默认态保持一致；编辑已发布文章时同样带上，实现"改了设置后
      // 重新编辑即可对旧文生效"
      final prefs = await SharedPreferences.getInstance();
      final allowRepost = prefs.getBool('creator_allow_repost') ?? true;
      final allowComments = prefs.getBool('creator_allow_comment') ?? true;
      final allowDownload = prefs.getBool('creator_allow_download') ?? true;
      // 创作设置里的"文章默认可见性"——public 公开 / private 仅自己可见，
      // 随发布/更新带上（编辑旧文重新保存即可对旧文生效）
      final visibility = prefs.getString('creator_visibility') ?? 'public';
      final payload = {
        'title': _titleCtrl.text.trim(),
        'summary': _summaryCtrl.text.trim(),
        'cover_image': _coverImageUrl ?? '',
        'tags': _tags,
        'blocks': blocksJson,
        'status': status,
        'visibility': visibility,
        'allowRepost': allowRepost,
        'allowComments': allowComments,
        'allowDownload': allowDownload,
        // subtitle/series_tag/issue_number 这几个字段后端目前没有
        // 对应列（实测确认 2026-07-05），先按给的方案带上——不确定
        // 后端会不会真的存下来、GET 回来时是否会带回，未经真实回环
        // 验证，跟已经实测确认过的 blocks 必须传原始数组不是一回事。
        // column_id 不在这里传——createTutorial 完全不读这个字段
        // （实测确认，专栏系统上线是另一个commit，没有同步给创建
        // 教程这个接口加上），得等教程创建成功拿到真实id后，走
        // POST /auth/columns/:id/articles 另外补一次关联，见下面
        'subtitle': _subtitle,
        'series_tag': _seriesTag,
        'issue_number': _issueNumber,
      };

      // 编辑已有教程走 PUT 更新原记录；新建走 POST。updateTutorial 是
      // "整份覆盖"语义（不传 blocks/tags 就会被清空成默认值），所以两条
      // 路径都必须传完整 payload，不能只传改动的字段
      final res = _editingTutorialId != null
          ? await ref
                .read(apiClientProvider)
                .put('/auth/tutorials/$_editingTutorialId', data: payload)
          : await ref
                .read(apiClientProvider)
                .post('/auth/tutorials', data: payload);

      if (!mounted) return;
      if (res.success) {
        // 保存/发布成功——本次上传的文件已经随 blocks/cover 绑定进文章，
        // 不再是孤儿，退出时不该被清理
        _uploadedFileIds.clear();
        final savedId =
            (res.data as Map?)?['id'] as String? ?? _editingTutorialId;
        if (savedId != null) _editingTutorialId = savedId;
        if (_selectedColumnId != null && savedId != null) {
          await ref
              .read(apiClientProvider)
              .post(
                '/auth/columns/$_selectedColumnId/articles',
                data: {'tutorialId': savedId},
              );
        }
        if (!mounted) return;
        notifyProfileShouldRefresh(ref);
        if (status == 'published') {
          showAppToast(context, l10n.publishSuccessMessage, ok: true);
          // 发现页不再是独立Tab，内容合并进了首页，发布成功后跳回首页
          context.go('/home');
        } else {
          showAppToast(context, l10n.draftSavedMessage, ok: true);
        }
      } else {
        showAppToast(context, l10n.saveFailedWithReason('${res.message}'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // COS 清理：删掉本次上传但还没绑定进文章的孤儿文件（并行，删失败不
  // 阻塞退出）。只删 _uploadedFileIds 里本次新上传的，不碰文章原有文件
  Future<void> _cleanupUnsavedFiles() async {
    if (_uploadedFileIds.isEmpty) return;
    final apiClient = ref.read(apiClientProvider);
    final ids = List<String>.from(_uploadedFileIds);
    _uploadedFileIds.clear();
    await Future.wait(
      ids.map((id) async {
        try {
          await apiClient.delete('/auth/files/$id');
        } catch (_) {
          // 删除失败不影响退出
        }
      }),
    );
  }

  // 退出（X 或系统返回）：完全空白直接退；有内容/有未保存上传就弹三选一
  Future<void> _handleExit() async {
    final hasContent =
        _titleCtrl.text.trim().isNotEmpty ||
        _summaryCtrl.text.trim().isNotEmpty ||
        _blocks.any(
          (b) =>
              b.content.trim().isNotEmpty || (b.imageUrl?.isNotEmpty ?? false),
        );
    if (!hasContent && _uploadedFileIds.isEmpty) {
      if (mounted) context.pop();
      return;
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildExitSheet(ctx, isDark),
    );
    if (!mounted) return;
    if (action == 'draft') {
      await _saveDraft(); // 成功后 _save 内部已清空 _uploadedFileIds
      if (mounted) context.pop();
    } else if (action == 'discard') {
      await _cleanupUnsavedFiles();
      if (mounted) context.pop();
    }
    // cancel / null：继续编辑，不退出
  }

  Widget _buildExitSheet(BuildContext ctx, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF17171F) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 3,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Text(
            '保存这篇文章吗？',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: isDark ? const Color(0xFFF0F2F8) : const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '不保存的话，本次上传的图片等文件会被清除',
            style: TextStyle(fontSize: 13, color: Colors.grey[400]),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx, 'draft'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1A1A),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                '保存草稿',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(ctx, 'discard'),
              style: TextButton.styleFrom(
                backgroundColor: isDark
                    ? const Color(0xFF1A1A2E)
                    : const Color(0xFFF5F5F5),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                '不保存，直接退出',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text(
              '继续编辑',
              style: TextStyle(
                color: Color(0xFF6366F1),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // 实测确认（2026-07-08）GET /auth/me 本来就直接返回 membership，
    // 不用再绕道 GET /auth/storage/usage。用 ref.watch 而不是 read，
    // 会员状态变化时（比如刚升级完）文件/音频/视频 block 的解锁状态、
    // 小梦AI入口能跟着更新
    final membership = ref.watch(currentUserProvider)?.membership ?? 'free';
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    // 摘要/更多设置这张卡之前跟顶栏一样固定在Column里，不跟着列表滚动——
    // 上滑时一直贴在顶部占位置，跟其它block表现不一致。抽成局部变量，
    // 当 ReorderableListView.builder 的 header 传进去，让它变成列表的
    // 第一项，随内容一起滚走；空状态下也塞进同一个 SingleChildScrollView
    // 顶部，两条路径行为保持一致
    final metaSection = PublishMetaSection(
      l10n: l10n,
      isDarkMode: isDarkMode,
      tags: _tags,
      onAddTag: _addTag,
      onRemoveTag: (tag) => setState(() => _tags.remove(tag)),
      coverImageUrl: _coverImageUrl,
      onCoverTap: () => showCoverOptions(
        context,
        onPickGallery: () => pickCoverImage(
          context,
          ref,
          onUploaded: (url, fileId) {
            setState(() => _coverImageUrl = url);
            if (fileId != null) _uploadedFileIds.add(fileId);
          },
        ),
        onAiGenerate: () => aiGenerateCover(
          context,
          ref,
          title: _titleCtrl.text,
          tags: _tags,
          summary: _summaryCtrl.text,
          onCoverSelected: (url, fileId) {
            setState(() => _coverImageUrl = url);
            if (fileId != null) _uploadedFileIds.add(fileId);
          },
        ),
      ),
      summaryController: _summaryCtrl,
      onSummaryChanged: () => setState(() {}),
      generatingSummary: _generatingSummary,
      onAiGenerateSummary: _aiGenerateSummary,
      seriesTag: _seriesTag,
      subtitle: _subtitle,
      onTitleInsertionTap: () => showTitleInsertionSheet(
        context,
        l10n: l10n,
        currentTitle: _titleCtrl.text,
        initialSubtitle: _subtitle,
        initialSeriesTag: _seriesTag,
        initialIssueNumber: _issueNumber,
        onSaved:
            ({required subtitle, required seriesTag, required issueNumber}) =>
                setState(() {
                  _subtitle = subtitle;
                  _seriesTag = seriesTag;
                  _issueNumber = issueNumber;
                }),
      ),
      selectedColumnId: _selectedColumnId,
      selectedColumnName: _selectedColumnName,
      onColumnTap: _showColumnSheet,
      onColumnCancel: () => setState(() {
        _selectedColumnId = null;
        _selectedColumnName = null;
      }),
    );

    if (_loadingExisting) {
      return Scaffold(
        backgroundColor: isDarkMode
            ? Theme.of(context).scaffoldBackgroundColor
            : _bg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return PopScope(
      // 拦截系统返回手势/返回键——统一走 _handleExit（询问保存/清理未保存
      // 的 COS 文件），不让默认返回直接 pop 掉页面丢内容
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleExit();
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: isDarkMode
            ? Theme.of(context).scaffoldBackgroundColor
            : _bg,
        endDrawer: PreviewDrawer(
          title: _titleCtrl.text,
          summary: _summaryCtrl.text,
          tags: _tags,
          blocks: _blocks,
          coverImageUrl: _coverImageUrl,
          onPublish: _saving ? null : _doPublish,
        ),
        body: Stack(
          children: [
            // top/bottom 都不在这层留白——顶栏/底部工具栏自己各用一层
            // SafeArea 处理状态栏/home indicator 那圈安全区。顶栏、工具栏都
            // 不再有自己的一块底色（透明，直接露出 Scaffold 背景），跟正文
            // 是同一块背景——整屏只有元信息卡片和"今日灵感"这类卡片浮在上面
            // 是有边框的"灵动岛"，不会再出现顶栏/工具栏跟正文颜色不一样、
            // 拼出一道横向分割线的"拼接感"
            SafeArea(
              top: false,
              bottom: false,
              child: Column(
                children: [
                  _buildCollapsibleHeader(l10n, isDarkMode, metaSection),
                  Expanded(
                    // 点空白区域（block之间的空隙、列表末尾没有block的地方）
                    // 收起格式工具栏——ReorderableListView本身不认"点了空白"
                    // 这种事，外面套一层不吃手势的GestureDetector，点到
                    // 具体block/输入框时那些控件自己的手势会先响应，不会被
                    // 这层拦截
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _focusedBlockId = null);
                        FocusScope.of(context).unfocus();
                      },
                      behavior: HitTestBehavior.translucent,
                      child: _blocks.isEmpty
                          ? _buildEmptyState(l10n, isDarkMode)
                          // 滚动时展开 block 间的"+"插入条、露出插入点；
                          // 滚动停止1.5秒后自动收起——静止编辑时保持紧凑，
                          // 不干扰阅读/输入
                          : NotificationListener<ScrollNotification>(
                              onNotification: (notification) {
                                if (notification is ScrollStartNotification) {
                                  _hideDividersTimer?.cancel();
                                  if (!_showDividers) {
                                    setState(() => _showDividers = true);
                                  }
                                } else if (notification
                                    is ScrollEndNotification) {
                                  _hideDividersTimer?.cancel();
                                  _hideDividersTimer = Timer(
                                    const Duration(milliseconds: 1500),
                                    () {
                                      if (mounted) {
                                        setState(() => _showDividers = false);
                                      }
                                    },
                                  );
                                }
                                return false;
                              },
                              child: ReorderableListView.builder(
                                scrollController: _scrollCtrl,
                                // 滚动正文时自动收起键盘（跟点空白处一致）
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.onDrag,
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  4,
                                ),
                                // 摘要/更多设置卡不再当列表 header——挪进了顶部
                                // 可折叠的信息区（见 _buildCollapsibleHeader）
                                itemCount: _blocks.length,
                                onReorder: _onReorder,
                                // 默认拖拽代理是个不带圆角的矩形 Material，
                                // 阴影跟卡片本身14px圆角对不上，拖起来卡片
                                // 底下露出一个方形"底座"——换成圆角跟卡片
                                // 一致、背景透明的 Material，阴影贴合卡片轮廓
                                proxyDecorator: (child, index, animation) =>
                                    Material(
                                      color: Colors.transparent,
                                      elevation: 6,
                                      shadowColor: Colors.black.withValues(
                                        alpha: 0.15,
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                      child: child,
                                    ),
                                // 拖拽只从 BlockCard 里那个手柄图标触发（见
                                // ReorderableDragStartListener），关掉默认的
                                // "长按列表项任意位置拖拽"——不然长按 block 里的
                                // 文字/代码输入框想选中文本时会跟这个默认拖拽
                                // 手势抢
                                buildDefaultDragHandles: false,
                                // "+"插入条不作为 ReorderableListView 自己的
                                // list item（那样会跟拖拽排序的下标数学搅在
                                // 一起），而是跟在每个 block 卡片后面一起
                                // 打包进同一个 item——itemCount/下标含义完全
                                // 不变，_onReorder 不用改一行
                                itemBuilder: (ctx, i) => Column(
                                  key: ValueKey(_blocks[i].id),
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    BlockCard(
                                      key: ValueKey('card_${_blocks[i].id}'),
                                      block: _blocks[i],
                                      index: i,
                                      total: _blocks.length,
                                      membership: membership,
                                      onRunCode: _runBlockCode,
                                      onDelete: () =>
                                          _deleteBlock(_blocks[i].id),
                                      // 空 block 按 Delete 任意位置都能删（含首块）——
                                      // 焦点落点交给 _deleteBlockAndFocusPrevious 内部
                                      // 处理（合入 origin/main 的空块删除修复）
                                      onEmptyBackspace: () =>
                                          _deleteBlockAndFocusPrevious(i),
                                      onMoveUp: i > 0
                                          ? () => _swapBlocks(i, i - 1)
                                          : null,
                                      onMoveDown: i < _blocks.length - 1
                                          ? () => _swapBlocks(i, i + 1)
                                          : null,
                                      onChanged: () => setState(() {}),
                                      focusedBlockId: _focusedBlockId,
                                      onFocusGained: () => setState(
                                        () => _focusedBlockId = _blocks[i].id,
                                      ),
                                      // 非文字block（图片/代码/公式等）自己也要
                                      // 设成 _focusedBlockId——这样它自己的
                                      // chrome（移动/删除/拖拽）才能借同一个
                                      // "当前激活block"的判断亮出来。格式工具栏
                                      // 不会因此误显示：BlockFormattingToolbar
                                      // 自己的 _applicable 只认 text/heading，
                                      // 块类型一对不上就还是收着
                                      onNonTextTap: () => setState(
                                        () => _focusedBlockId = _blocks[i].id,
                                      ),
                                      onFileUploaded: (id) =>
                                          _uploadedFileIds.add(id),
                                    ),
                                    _InsertDivider(
                                      key: ValueKey('divider_${_blocks[i].id}'),
                                      show: _showDividers,
                                      isDark: isDarkMode,
                                      onTap: () => showBlockPickerSheet(
                                        context,
                                        l10n: l10n,
                                        isDarkMode: isDarkMode,
                                        onPick: (type) =>
                                            _insertBlockAt(i + 1, type),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                  ),
                  BlockFormattingToolbar(
                    l10n: l10n,
                    isDarkMode: isDarkMode,
                    block: _focusedBlock,
                    expanded: _formatBarExpanded,
                    onChanged: () => setState(() {}),
                    onShowFontSheet: () {
                      final b = _focusedBlock;
                      if (b == null) return;
                      showFontSheet(
                        context,
                        l10n: l10n,
                        isDarkMode: isDarkMode,
                        block: b,
                        onChanged: () => setState(() {}),
                      );
                    },
                    onConvertHeading: (level) {
                      final id = _focusedBlockId;
                      if (id == null) return;
                      _convertHeading(id, level);
                    },
                    // 再点一次已经激活的 H 按钮——收起辅助栏，跟 Tt 一致
                    onCollapse: () =>
                        setState(() => _formatBarExpanded = false),
                  ),
                  // 代码块的语言选择条——跟 BlockFormattingToolbar 并排放在
                  // 工具栏上方，只在聚焦代码 block 且点开时浮出（互斥：aux
                  // 只认文字/标题，这条只认代码）
                  CodeLangBar(
                    isDarkMode: isDarkMode,
                    block: _focusedBlock,
                    expanded: _langBarExpanded,
                    onChanged: () => setState(() {}),
                  ),
                  PublishBottomToolbar(
                    l10n: l10n,
                    isDarkMode: isDarkMode,
                    blocks: _blocks,
                    activeToolbarType: _activeToolbarType,
                    onAddBlock: _addBlock,
                    onImport: _openImportBrowser,
                    // 类型按钮只管新建 block；辅助栏（字体/颜色）由工具栏
                    // 右侧那个独立的「Aa」图标控制——只有聚焦文字/标题
                    // block 时才显示，点它切换辅助栏开关
                    showFormatToggle:
                        _focusedBlock != null &&
                        (_focusedBlock!.type == BlockType.text ||
                            _focusedBlock!.type == BlockType.heading),
                    formatBarExpanded: _formatBarExpanded,
                    onToggleFormatBar: () => setState(
                      () => _formatBarExpanded = !_formatBarExpanded,
                    ),
                    // 代码块 → 语言选择条开关，跟 aux 同一套路
                    showLangToggle:
                        _focusedBlock != null &&
                        _focusedBlock!.type == BlockType.code,
                    langBarExpanded: _langBarExpanded,
                    onToggleLangBar: () =>
                        setState(() => _langBarExpanded = !_langBarExpanded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 顶部信息区（标题栏 + 封面/摘要/更多设置）折叠成一个隐藏式按钮：收起
  // 时只留一个朝下的尖，点它展开整块（尖朝上），再点收起（尖朝下）。把
  // 屏幕高度尽量让给正文编辑区，需要改标题/摘要/发布时再点开
  Widget _buildCollapsibleHeader(
    AppLocalizations l10n,
    bool isDarkMode,
    Widget metaSection,
  ) {
    return SafeArea(
      bottom: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _headerExpanded
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PublishTopBar(
                        l10n: l10n,
                        isDarkMode: isDarkMode,
                        titleController: _titleCtrl,
                        saving: _saving,
                        onTitleChanged: () => setState(() {}),
                        onSaveDraft: _saveDraft,
                        onPublish: _publish,
                        onClose: _handleExit,
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                        child: metaSection,
                      ),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
          // 折叠开关：一个居中的尖，展开时朝上、收起时朝下
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _headerExpanded = !_headerExpanded),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 2),
              alignment: Alignment.center,
              child: Icon(
                _headerExpanded
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                size: 22,
                color: const Color(0xFF999999),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 一个 block 都没有时的引导区——不是一片空白，而是问候语+快速开始+
  // 今日灵感，让用户一打开就知道从哪下手，不会有"不知道写什么"的
  // 空白焦虑。加了第一个 block 之后就自动切回正常的 block 列表
  Widget _buildEmptyState(AppLocalizations l10n, bool isDarkMode) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.emptyStateGreetingTitle,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: isDarkMode ? Colors.white : _ink,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.emptyStateGreetingSubtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: _muted,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.quickStartLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFBBBBBB),
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 8),
                GridView.count(
                  shrinkWrap: true,
                  // GridView 没显式传 padding 时会自动套一层
                  // MediaQuery.of(context).padding（状态栏/home indicator
                  // 安全区）当 SliverPadding——这是专门给"整页根滚动视图"
                  // 设计的默认行为，这里只是嵌在 Column 里的一小块网格，
                  // 不需要，不关掉的话"快速开始"和按钮网格之间会空出一大截
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 2.8,
                  children: [
                    _QuickStartBtn(
                      icon: Icons.text_fields,
                      label: l10n.quickStartWriting,
                      color: _ink,
                      bg: const Color(0xFFF5F5F5),
                      onTap: () => _addBlock(BlockType.text),
                    ),
                    _QuickStartBtn(
                      icon: Icons.code,
                      label: l10n.quickStartCode,
                      color: _primary,
                      bg: const Color(0xFFEEF0FF),
                      onTap: () => _addBlock(BlockType.code),
                    ),
                    _QuickStartBtn(
                      icon: Icons.functions,
                      label: l10n.quickStartLatex,
                      color: const Color(0xFFC026D3),
                      bg: const Color(0xFFFDF0F8),
                      onTap: () => _addBlock(BlockType.latex),
                    ),
                    _QuickStartBtn(
                      icon: Icons.format_quote,
                      label: l10n.quickStartQuote,
                      color: const Color(0xFF2563EB),
                      bg: const Color(0xFFE6F0FF),
                      onTap: () => _addBlock(BlockType.callout),
                    ),
                    _QuickStartBtn(
                      icon: Icons.image_outlined,
                      label: l10n.quickStartImage,
                      color: const Color(0xFF16A34A),
                      bg: const Color(0xFFE8F8F0),
                      onTap: () => _addBlock(BlockType.image),
                    ),
                    _QuickStartBtn(
                      icon: Icons.auto_awesome_outlined,
                      label: l10n.quickStartXiaomeng,
                      color: const Color(0xFFD97706),
                      bg: const Color(0xFFFFF7E6),
                      onTap: _askXmeng,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                // 卡片色跟随主题走，深色模式下不再是刺眼的米白色小方块
                color: isDarkMode
                    ? Theme.of(context).cardColor
                    : const Color(0xFFFAFAF8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDarkMode
                      ? Theme.of(context).dividerColor
                      : const Color(0xFFF0F0F0),
                  width: 0.5,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.lightbulb_outline,
                    size: 16,
                    color: Color(0xFFD97706),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.todaysInspirationLabel,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFFBBBBBB),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _inspirations.isEmpty
                              ? ''
                              : _inspirations[_inspirationIndex.clamp(
                                  0,
                                  _inspirations.length - 1,
                                )],
                          style: TextStyle(
                            fontSize: 13,
                            color: isDarkMode
                                ? const Color(0xFFD1D1D6)
                                : const Color(0xFF555555),
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _refreshInspirations,
                    child: const Icon(
                      Icons.refresh,
                      size: 16,
                      color: Color(0xFFBBBBBB),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 加入专栏——列表选择/新建专栏/创建成功三步都在同一个sheet里，用
  // ColumnPickerSheet 自己的 State 切换，不是三个各自独立的 dialog/sheet
  Future<void> _showColumnSheet() async {
    final result = await showModalBottomSheet<ColumnPickerResult>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => ColumnPickerSheet(initialColumnId: _selectedColumnId),
    );
    if (result == null || !mounted) return;
    setState(() {
      _selectedColumnId = result.columnId;
      _selectedColumnName = result.columnName;
    });
  }

  void _addTag() {
    final l10n = AppLocalizations.of(context)!;
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.addTagAction),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: l10n.tagNameHint,
            prefixText: '#',
          ),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty && _tags.length < 8) {
              setState(() => _tags.add(v.trim()));
            }
            Navigator.pop(ctx);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty && _tags.length < 8) {
                setState(() => _tags.add(ctrl.text.trim()));
              }
              Navigator.pop(ctx);
            },
            child: Text(
              l10n.addTagAction,
              style: const TextStyle(color: _primary),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _aiGenerateSummary() async {
    // 小梦 AI 摘要是 Pro 权益——点了才校验，非 Pro 弹会员 Sheet
    if (!requirePro(context, ref, feature: '小梦 AI 摘要')) return;
    final content = [
      if (_titleCtrl.text.isNotEmpty) '标题：${_titleCtrl.text}',
      ..._blocks
          .where(
            (b) =>
                b.content.isNotEmpty &&
                (b.type == BlockType.text || b.type == BlockType.heading),
          )
          .map((b) => b.content),
    ].join('\n\n');

    if (content.trim().isEmpty) {
      showAppToast(context, '先写点内容，小梦才能帮你生成摘要');
      return;
    }

    setState(() => _generatingSummary = true);
    try {
      final res = await ref
          .read(apiClientProvider)
          .post('/auth/xmeng/summary', data: {'content': content});

      if (res.success && mounted) {
        final summary = (res.data as Map?)?['summary'] as String? ?? '';
        if (summary.isNotEmpty) {
          setState(() => _summaryCtrl.text = summary);
          showAppToast(context, '摘要已生成', ok: true);
        }
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, '小梦开小差了，请重试');
      }
    } finally {
      if (mounted) setState(() => _generatingSummary = false);
    }
  }

  @override
  void dispose() {
    _hideDividersTimer?.cancel();
    _titleCtrl.dispose();
    _summaryCtrl.dispose();
    _scrollCtrl.dispose();
    for (final b in _blocks) {
      b.focusNode.dispose();
    }
    super.dispose();
  }
}

// block 之间/最后一个 block 下方的插入点——静止时收成 4px 的窄缝（几乎
// 无间距，减少干扰），滚动时展开成 28px 露出"+"，两侧细线用同一份中性
// 描边色。show 完全由父级（滚动状态）驱动，这里不自己维护交互态
class _InsertDivider extends StatelessWidget {
  final bool show;
  final bool isDark;
  final VoidCallback onTap;

  const _InsertDivider({
    super.key,
    required this.show,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final lineColor = isDark
        ? const Color(0xFF2A2A3A)
        : const Color(0xFFDDDDE8);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        height: show ? 28 : 4,
        margin: const EdgeInsets.symmetric(horizontal: 14),
        child: show
            ? Row(
                children: [
                  Expanded(child: Container(height: 0.5, color: lineColor)),
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark
                          ? const Color(0xFF1A1A24)
                          : const Color(0xFFF0F0F5),
                      border: Border.all(color: lineColor, width: 0.5),
                    ),
                    child: Icon(
                      Icons.add,
                      size: 14,
                      color: isDark
                          ? const Color(0xFF7A80A0)
                          : const Color(0xFF888888),
                    ),
                  ),
                  Expanded(child: Container(height: 0.5, color: lineColor)),
                ],
              )
            : null,
      ),
    );
  }
}

class _QuickStartBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color bg;
  final VoidCallback onTap;

  const _QuickStartBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.bg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
