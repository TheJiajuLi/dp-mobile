import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/profile_refresh_signal.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/utils/pro_access.dart';
import '../../auth/auth_service.dart';
import '../models/block_model.dart';
import '../widgets/block_card.dart';
import '../widgets/column_picker_sheet.dart';
import '../widgets/cover_picker_sheet.dart';
import '../widgets/formatting_toolbar.dart';
import '../widgets/preview_drawer.dart';
import '../widgets/publish_meta_sheet.dart';
import '../widgets/publish_toolbar.dart';
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

  final List<EditorBlock> _blocks = [];
  final List<String> _tags = [];
  // 本次编辑会话里新上传到 COS 的文件 id（封面/正文图片/视频/音频/文件）。
  // 退出时如果没保存草稿/发布，就把这些还没跟文章绑定的孤儿文件删掉；
  // 保存/发布成功后清空（文件已绑定文章，不该再删）。只追踪本次新上传的，
  // 编辑模式下不碰文章原有的文件
  final List<String> _uploadedFileIds = [];
  bool _saving = false;
  bool _generatingSummary = false;
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
  // 底部工具栏"Tt"按钮收起/展开格式工具栏（粗体/颜色那行）用——默认展开，
  // 跟以前一样一聚焦文字/标题block就直接看得到
  bool _formatBarExpanded = true;

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

  // 空白引导区——"今日灵感"随机显示一条，点刷新换下一条（顺序轮换，
  // 不是真随机，保证点了刷新一定会换到不一样的一条，不会连着点两次
  // 还是同一句）
  int _inspirationIndex = 0;
  static const _inspirations = [
    '试着用一张图解释一个复杂概念，往往比千字更有力。',
    '你最近解决了什么有趣的问题？把过程写下来，它比答案更有价值。',
    '把你今天读到的一篇论文，用5句话讲给普通人听。',
    '有没有一个大家都误解的事情，你正好知道真相？',
    '写一段你最喜欢的代码，解释为什么它让你着迷。',
    '今天发生了什么让你觉得"这很有意思"的事？',
    '选一个领域，用数据说话，不用观点。',
  ];

  void _nextInspiration() {
    setState(
      () => _inspirationIndex = (_inspirationIndex + 1) % _inspirations.length,
    );
  }

  Future<void> _askXmeng() async {
    if (_titleCtrl.text.isNotEmpty ||
        _blocks.any((b) => b.content.isNotEmpty)) {
      await _aiSuggestTitles();
      return;
    }

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
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Color(0xFFEEF0FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome, color: _primary, size: 32),
            ),
            const SizedBox(height: 12),
            const Text(
              '我是小梦，来帮你开始',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              '先告诉我你想写什么方向？',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  [
                    '数据分析',
                    '机器学习',
                    'Python编程',
                    '数学公式',
                    '可视化',
                    '论文笔记',
                    '个人总结',
                    '读书笔记',
                  ].map((topic) {
                    return GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        _addBlock(BlockType.text);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Row(
                              children: [
                                const Icon(
                                  Icons.auto_awesome,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 8),
                                Expanded(child: Text('开始写$topic吧！有问题随时叫我')),
                              ],
                            ),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F5F7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          topic,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF1C1C1E),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
            ),
          ],
        ),
      ),
    );
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('小梦开小差了，请重试')));
      }
    }
  }

  // 复用 notebook_editor_screen.dart 里已经跑通的那套 Pyodide 引擎——同一个
  // compiler.js，同一个隐藏 WebView 承载方式。之前给的方案是"每个 block
  // 自己注册一个 onRunResult_<blockId> handler"，实测 Notebook 那边用的其实
  // 是"整个页面共用一个 onRunResult handler，靠传回来的 block id 在
  // _pendingRuns 这个 Map 里路由结果"，更简单也是已经验证过能用的写法，
  // 这里直接照抄这套，不重新发明一遍
  InAppWebViewController? _webCtrl;
  bool _webReady = false;
  final Map<String, Completer<String>> _pendingRuns = {};

  static const _compilerHtml = '''
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width">
</head>
<body>
<script type="module">
import { compile } from
  'https://dreamingpolar.com/components/compiler/compiler.js';

window.runCode = async (code, lang) => {
  try {
    const outputs = await compile(code, lang);
    return JSON.stringify(outputs);
  } catch(e) {
    return JSON.stringify([{
      type: 'error',
      content: String(e)
    }]);
  }
};

setTimeout(() => {
  if (window.flutter_inappwebview) {
    window.flutter_inappwebview.callHandler('compilerReady');
  }
}, 1000);
</script>
</body>
</html>
''';

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('加载失败：${res.message}')));
    }
    setState(() => _loadingExisting = false);
  }

  // Notebook 里用来把 SQL cell 包成 Python 通过 sqlite3 跑的同一个包装法——
  // compiler.js 的 compile() 实际只吃 python，SQL 这个"语言"是客户端自己
  // 文本拼出来的 python 脚本，不是 compile() 真的认识一个叫 sql 的语言
  String _wrapSql(String sql) =>
      '''
import sqlite3, pandas as pd, io
conn = sqlite3.connect(':memory:')
try:
    df.to_sql('df', conn, if_exists='replace', index=False)
except Exception:
    pass
result = pd.read_sql_query("""$sql""", conn)
conn.close()
result
''';

  // 统一入口，BlockCard 不用关心 Pyodide 还没就绪、SQL 要不要包装这些
  // 细节，只管拿到一份 List<{type, content}> 结果。javascript 走的是
  // 完全不同的直接 evaluateJavascript 分支（跟 Notebook 一致），不经过
  // compiler.js/Pyodide——那只是个 Python 运行时，不是多语言沙箱
  Future<List<Map<String, dynamic>>> _runBlockCode(
    String blockId,
    String code,
    String language,
  ) async {
    if (language == 'html' || language == 'markdown') {
      return [
        {
          'type': 'info',
          'content': AppLocalizations.of(context)!.unsupportedCellType,
        },
      ];
    }
    if (language == 'javascript') {
      return _runJavaScriptBlock(code);
    }

    if (_webCtrl == null) {
      return [
        {
          'type': 'error',
          'content': AppLocalizations.of(context)!.envInitializing,
        },
      ];
    }
    // compiler.js 首次要拉 Pyodide，可能需要几秒到十几秒——耐心等最多
    // 60 秒，而不是直接判失败，这是 Notebook 那边"运行完成（无输出）"
    // 假阳性问题的根因之一，不能在这里重蹈覆辙
    if (!_webReady) {
      for (var i = 0; i < 60; i++) {
        await Future.delayed(const Duration(seconds: 1));
        if (_webReady) break;
      }
      if (!mounted) return [];
      if (!_webReady) {
        return [
          {
            'type': 'error',
            'content': AppLocalizations.of(context)!.loadTimeoutRestart,
          },
        ];
      }
    }

    final effectiveCode = language == 'sql' ? _wrapSql(code) : code;

    try {
      final completer = Completer<String>();
      _pendingRuns[blockId] = completer;

      await _webCtrl!.evaluateJavascript(
        source:
            '''
(async () => {
  try {
    if (typeof window.runCode !== 'function') {
      window.flutter_inappwebview.callHandler(
        'onRunResult', ${jsonEncode(blockId)},
        JSON.stringify([{type:'error', content:'compiler not ready'}])
      );
      return;
    }
    const outputs = await window.runCode(${jsonEncode(effectiveCode)}, "python");
    window.flutter_inappwebview.callHandler(
      'onRunResult', ${jsonEncode(blockId)}, outputs
    );
  } catch(e) {
    window.flutter_inappwebview.callHandler(
      'onRunResult', ${jsonEncode(blockId)},
      JSON.stringify([{type:'error', content: String(e)}])
    );
  }
})();
''',
      );

      final raw = await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => jsonEncode([
          {
            'type': 'error',
            'content': mounted
                ? AppLocalizations.of(context)!.execTimeout
                : 'timeout',
          },
        ]),
      );

      dynamic parsed;
      try {
        parsed = jsonDecode(raw);
      } catch (_) {
        return [
          {'type': 'text', 'content': raw},
        ];
      }
      final outputs = parsed is List ? parsed : [parsed];
      return outputs
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    } finally {
      _pendingRuns.remove(blockId);
    }
  }

  // 跟 Notebook _runJavaScript 同款：捕获 console.log 输出，返回值统一走
  // JSON.stringify，避免不同平台 evaluateJavascript 对返回对象编组不一致
  Future<List<Map<String, dynamic>>> _runJavaScriptBlock(String code) async {
    if (_webCtrl == null) {
      return [
        {
          'type': 'error',
          'content': AppLocalizations.of(context)!.envInitializing,
        },
      ];
    }
    try {
      final wrappedCode =
          '''
(function() {
  const logs = [];
  const _log = console.log;
  console.log = (...args) => {
    logs.push(args.map(a =>
      typeof a === 'object' ? JSON.stringify(a) : String(a)
    ).join(' '));
    _log(...args);
  };
  try {
    $code
    console.log = _log;
    return JSON.stringify({ok: true, output: logs.join('\\n')});
  } catch(e) {
    console.log = _log;
    return JSON.stringify({ok: false, error: e.message});
  }
})()
''';
      final result = await _webCtrl!.evaluateJavascript(source: wrappedCode);
      if (result == null) {
        return [
          {'type': 'text', 'content': ''},
        ];
      }
      final map = jsonDecode(result.toString()) as Map;
      if (map['ok'] == true) {
        return [
          {'type': 'text', 'content': (map['output'] as String?) ?? ''},
        ];
      }
      return [
        {
          'type': 'error',
          'content': map['error']?.toString() ?? 'unknown error',
        },
      ];
    } catch (e) {
      return [
        {'type': 'error', 'content': '$e'},
      ];
    }
  }

  String _uid() =>
      'block_${DateTime.now().millisecondsSinceEpoch}_${_blocks.length}';

  void _addBlock(BlockType type) {
    final newBlock = EditorBlock(
      id: _uid(),
      type: type,
      language: type == BlockType.code ? 'python' : null,
    );
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.importSuccessMessage(count, platformName)),
        duration: const Duration(seconds: 4),
        backgroundColor: const Color(0xFF16A34A),
      ),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.pleaseEnterNoteTitle)));
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
      final payload = {
        'title': _titleCtrl.text.trim(),
        'summary': _summaryCtrl.text.trim(),
        'cover_image': _coverImageUrl ?? '',
        'tags': _tags,
        'blocks': blocksJson,
        'status': status,
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.publishSuccessMessage),
              backgroundColor: const Color(0xFF16A34A),
            ),
          );
          // 发现页不再是独立Tab，内容合并进了首页，发布成功后跳回首页
          context.go('/home');
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.draftSavedMessage)));
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.saveFailedWithReason('${res.message}'))),
        );
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
        backgroundColor: isDarkMode
            ? Theme.of(context).scaffoldBackgroundColor
            : _bg,
        endDrawer: PreviewDrawer(
          title: _titleCtrl.text,
          summary: _summaryCtrl.text,
          tags: _tags,
          blocks: _blocks,
          coverImageUrl: _coverImageUrl,
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
                          ? _buildEmptyState(l10n, isDarkMode, metaSection)
                          : ReorderableListView.builder(
                              scrollController: _scrollCtrl,
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                              // 摘要/更多设置卡当列表的header——随内容一起滚走，
                              // 不再固定占位在顶部
                              header: Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: metaSection,
                              ),
                              itemCount: _blocks.length,
                              onReorder: _onReorder,
                              // 拖拽只从 BlockCard 里那个手柄图标触发（见
                              // ReorderableDragStartListener），关掉默认的
                              // "长按列表项任意位置拖拽"——不然长按 block 里的
                              // 文字/代码输入框想选中文本时会跟这个默认拖拽
                              // 手势抢
                              buildDefaultDragHandles: false,
                              itemBuilder: (ctx, i) => BlockCard(
                                key: ValueKey(_blocks[i].id),
                                block: _blocks[i],
                                index: i,
                                total: _blocks.length,
                                membership: membership,
                                onRunCode: _runBlockCode,
                                onDelete: () => _deleteBlock(_blocks[i].id),
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
                                // 非文字block（图片/代码/公式等）自己也要设成
                                // _focusedBlockId——这样它自己的chrome（移动/
                                // 删除/拖拽）才能借同一个"当前激活block"的判断
                                // 亮出来。格式工具栏不会因此误显示：
                                // BlockFormattingToolbar 自己的 _applicable
                                // 只认 text/heading，块类型一对不上就还是收着
                                onNonTextTap: () => setState(
                                  () => _focusedBlockId = _blocks[i].id,
                                ),
                                onFileUploaded: (id) =>
                                    _uploadedFileIds.add(id),
                              ),
                            ),
                    ),
                  ),
                  // "添加内容块"——放在列表下方常驻（不跟着滚动进 Reorderable
                  // 列表里，那样会跟拖拽排序的下标数学搅在一起），打开紧凑的
                  // 4列 Block 选择器，跟顶栏那排图标是两个不同入口：图标行是
                  // "直接加"，这个是给已经滚到底部、不想再滚回顶栏的场景用
                  if (_blocks.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: GestureDetector(
                        onTap: () => showBlockPickerSheet(
                          context,
                          l10n: l10n,
                          isDarkMode: isDarkMode,
                          onPick: _addBlock,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isDarkMode
                                  ? Colors.white.withValues(alpha: 0.1)
                                  : const Color(0xFFDDDDF0),
                              width: 0.5,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add,
                                size: 16,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(width: 6),
                              Text(
                                l10n.addContentBlockLabel,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[400],
                                ),
                              ),
                            ],
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
                  ),
                  PublishBottomToolbar(
                    l10n: l10n,
                    isDarkMode: isDarkMode,
                    blocks: _blocks,
                    activeToolbarType: _activeToolbarType,
                    onAddBlock: _addBlock,
                    onImport: _openImportBrowser,
                    // 有正在编辑的文字/标题block时，"Tt"按钮改成收起/展开
                    // 格式工具栏；没有的话传null，按钮退回老行为（新建
                    // 文字block）
                    onToggleFormatBar:
                        _focusedBlock != null &&
                            (_focusedBlock!.type == BlockType.text ||
                                _focusedBlock!.type == BlockType.heading)
                        ? () => setState(
                            () => _formatBarExpanded = !_formatBarExpanded,
                          )
                        : null,
                  ),
                ],
              ),
            ),
            // 隐藏的 WebView，承载 Pyodide/compiler.js——跟 Notebook 编辑器
            // 那边一样放到屏幕外、给一个 1x1 的极小尺寸，不能用 Offstage/
            // 0 尺寸，部分平台下 WebView 尺寸为 0 时不会正常初始化
            Positioned(
              left: -9999,
              top: -9999,
              width: 1,
              height: 1,
              child: InAppWebView(
                initialData: InAppWebViewInitialData(
                  data: _compilerHtml,
                  baseUrl: WebUri('https://dreamingpolar.com'),
                ),
                onWebViewCreated: (ctrl) {
                  _webCtrl = ctrl;
                  ctrl.addJavaScriptHandler(
                    handlerName: 'compilerReady',
                    callback: (args) {
                      if (mounted) setState(() => _webReady = true);
                      debugPrint('[Publish] Pyodide就绪');
                    },
                  );
                  ctrl.addJavaScriptHandler(
                    handlerName: 'onRunResult',
                    callback: (args) {
                      final blockId = args.isNotEmpty ? args[0].toString() : '';
                      final result = args.length > 1
                          ? args[1].toString()
                          : '[]';
                      _pendingRuns[blockId]?.complete(result);
                    },
                  );
                },
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  allowsInlineMediaPlayback: true,
                  mediaPlaybackRequiresUserGesture: false,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 一个 block 都没有时的引导区——不是一片空白，而是问候语+快速开始+
  // 今日灵感，让用户一打开就知道从哪下手，不会有"不知道写什么"的
  // 空白焦虑。加了第一个 block 之后就自动切回正常的 block 列表
  Widget _buildEmptyState(
    AppLocalizations l10n,
    bool isDarkMode,
    Widget metaSection,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          metaSection,
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
                          _inspirations[_inspirationIndex],
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
                    onTap: _nextInspiration,
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('先写点内容，小梦才能帮你生成摘要')));
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 18,
                    color: Colors.white,
                  ),
                  SizedBox(width: 8),
                  Text('摘要已生成'),
                ],
              ),
              backgroundColor: Color(0xFF16A34A),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('小梦开小差了，请重试')));
      }
    } finally {
      if (mounted) setState(() => _generatingSummary = false);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _summaryCtrl.dispose();
    _scrollCtrl.dispose();
    for (final b in _blocks) {
      b.focusNode.dispose();
    }
    super.dispose();
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
