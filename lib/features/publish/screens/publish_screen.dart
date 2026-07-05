import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/utils/topic_badge.dart';
import '../../settings/providers/storage_provider.dart';
import '../models/block_model.dart';
import '../widgets/block_card.dart';
import '../widgets/block_picker_sheet.dart';
import '../widgets/preview_drawer.dart';

const _primary = Color(0xFF6366F1);
const _ink = Color(0xFF1A1A1A);
const _bg = Color(0xFFFAFAF8);
const _muted = Color(0xFF999999);

// 底部横排工具栏按这 8 种类型显示快捷图标，跟 CONTEXT.md 原本记录的
// Block 类型列表（文字/代码/LaTeX/引用/图片/视频/音频/链接）一一对应；
// heading/file 这两种类型模型本身还在（已发布内容里可能用到，阅读端要
// 继续认得），只是不再放进这条一眼扫完的快捷栏，通过最后的"更多"按钮
// 打开完整的 BlockPickerSheet 才能加
const _toolbarTypes = [
  BlockType.text,
  BlockType.code,
  BlockType.latex,
  BlockType.callout,
  BlockType.image,
  BlockType.video,
  BlockType.audio,
  BlockType.link,
];

// 专栏——GET /auth/columns 实测 2026-07-05 是 404，后端还没有这个接口，
// 先按给的方案 mock 两条固定数据，等后端接口上线后把这里换成真实请求
class _MockColumn {
  final String id;
  final String name;
  final int articleCount;
  final int subscriberCount;
  final List<Color> gradient;
  final IconData icon;

  const _MockColumn({
    required this.id,
    required this.name,
    required this.articleCount,
    required this.subscriberCount,
    required this.gradient,
    required this.icon,
  });
}

const _mockColumns = [
  _MockColumn(
    id: 'col_cosmos',
    name: '宇宙探索系列',
    articleCount: 12,
    subscriberCount: 128,
    gradient: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
    icon: Icons.rocket_launch_outlined,
  ),
  _MockColumn(
    id: 'col_economy',
    name: '经济观察',
    articleCount: 8,
    subscriberCount: 56,
    gradient: [Color(0xFFF59E0B), Color(0xFFEA580C)],
    icon: Icons.show_chart,
  ),
];

const _seriesTagOptions = ['连载', '独立', '翻译', '深度', '快讯'];

class PublishScreen extends ConsumerStatefulWidget {
  const PublishScreen({super.key});
  @override
  ConsumerState<PublishScreen> createState() => _PublishScreenState();
}

class _PublishScreenState extends ConsumerState<PublishScreen> {
  final _titleCtrl = TextEditingController();
  final _summaryCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  final List<EditorBlock> _blocks = [];
  final List<String> _tags = ['Python', '数据分析'];
  bool _saving = false;
  String? _coverImageUrl;
  // 底部工具栏里"当前选中"的高亮态——没有真的去接每个 block 内部输入框
  // 的 focus 变化（链路太长），退而求其次：跟着"最近一次点了哪个类型的
  // 加内容按钮"走，默认高亮"文字"，跟刚打开发布页时只有一个文字 block
  // 的初始状态对上
  BlockType _activeToolbarType = BlockType.text;

  // 专栏
  String? _selectedColumnId;
  String? _selectedColumnName;

  // 标题植入
  String _subtitle = '';
  String _seriesTag = '';
  String _issueNumber = '';

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
    _blocks.add(EditorBlock(id: _uid(), type: BlockType.text, content: ''));
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
    setState(() {
      _activeToolbarType = type;
      _blocks.add(
        EditorBlock(
          id: _uid(),
          type: type,
          language: type == BlockType.code ? 'python' : null,
        ),
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _deleteBlock(String id) {
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

      final res = await ref
          .read(apiClientProvider)
          .post(
            '/auth/tutorials',
            data: {
              'title': _titleCtrl.text.trim(),
              'summary': _summaryCtrl.text.trim(),
              'cover_image': _coverImageUrl ?? '',
              'tags': _tags,
              'blocks': blocksJson,
              'status': status,
              // 专栏/标题植入这几个字段后端目前没有对应接口/字段（专栏
              // 列表本身就是 mock 的），先按给的方案带上——不确定后端
              // 会不会真的存下来、GET 回来时是否会带回，未经真实回环
              // 验证，跟已经实测确认过的 blocks 必须传原始数组不是一回事
              'column_id': _selectedColumnId,
              'subtitle': _subtitle,
              'series_tag': _seriesTag,
              'issue_number': _issueNumber,
            },
          );

      if (!mounted) return;
      if (res.success) {
        if (status == 'published') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.publishSuccessMessage),
              backgroundColor: const Color(0xFF16A34A),
            ),
          );
          context.go('/community');
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // membership 只有 GET /auth/storage/usage 会返回（currentUserProvider
    // 的 UserModel 上没有这个字段）——用 ref.watch 而不是 read，会员状态
    // 变化时（比如刚升级完）文件/音频/视频 block 的解锁状态能跟着更新
    final storageAsync = ref.watch(storageUsageProvider);
    final membership =
        storageAsync.valueOrNull?['membership'] as String? ?? 'free';
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
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
          // top/bottom 都不在这层留白——顶栏自己用 SafeArea(bottom:false)
          // 包一层让白色背景铺进状态栏那圈安全区，底部工具栏也是同样自己
          // 处理 home indicator 那圈安全区，不然这里统一留白会露出
          // Scaffold 米白色的背景，跟顶栏/工具栏的纯白刀切一样不连贯
          SafeArea(
            top: false,
            bottom: false,
            child: Column(
              children: [
                _buildTopBar(l10n),
                _buildMetaSection(l10n, isDarkMode),
                Expanded(
                  child: ReorderableListView.builder(
                    scrollController: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    itemCount: _blocks.length,
                    onReorder: _onReorder,
                    // 拖拽只从 BlockCard 里那个手柄图标触发（见
                    // ReorderableDragStartListener），关掉默认的"长按
                    // 列表项任意位置拖拽"——不然长按 block 里的文字/代码
                    // 输入框想选中文本时会跟这个默认拖拽手势抢
                    buildDefaultDragHandles: false,
                    itemBuilder: (ctx, i) => BlockCard(
                      key: ValueKey(_blocks[i].id),
                      block: _blocks[i],
                      index: i,
                      total: _blocks.length,
                      membership: membership,
                      onRunCode: _runBlockCode,
                      onDelete: () => _deleteBlock(_blocks[i].id),
                      onMoveUp: i > 0 ? () => _swapBlocks(i, i - 1) : null,
                      onMoveDown: i < _blocks.length - 1
                          ? () => _swapBlocks(i, i + 1)
                          : null,
                      onChanged: () => setState(() {}),
                    ),
                  ),
                ),
                _buildBottomToolbar(l10n, isDarkMode),
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
                    final result = args.length > 1 ? args[1].toString() : '[]';
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
    );
  }

  Widget _buildTopBar(AppLocalizations l10n) {
    return Container(
      color: Theme.of(context).cardColor,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => context.pop(),
                child: const Icon(
                  Icons.close,
                  size: 22,
                  color: Color(0xFF888888),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _titleCtrl,
                  decoration: InputDecoration(
                    filled: false,
                    hintText: l10n.publishTitleHint,
                    hintStyle: const TextStyle(color: Color(0xFFC7C7CC)),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Builder(
                builder: (ctx) => GestureDetector(
                  onTap: () => Scaffold.of(ctx).openEndDrawer(),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      Icons.visibility_outlined,
                      size: 20,
                      color: Color(0xFF888888),
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: _saving ? null : _saveDraft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    l10n.saveDraftAction,
                    style: const TextStyle(fontSize: 13, color: _muted),
                  ),
                ),
              ),
              GestureDetector(
                onTap: _saving ? null : _publish,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: _ink,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          l10n.publish,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 封面 + 摘要 + 标签，固定在 Block 列表上方（不跟着一起滚动）——发布
  // 前一眼就知道这篇要发的是什么，不用滚到最上面确认
  Widget _buildMetaSection(AppLocalizations l10n, bool isDarkMode) {
    final topicRule = matchedTopicRuleFor(_tags);

    return Column(
      children: [
        GestureDetector(
          onTap: _pickCoverImage,
          child: Container(
            height: 140,
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F0F8),
              borderRadius: BorderRadius.circular(14),
              image: _coverImageUrl != null
                  ? DecorationImage(
                      image: NetworkImage(_coverImageUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: Stack(
              children: [
                if (_coverImageUrl == null)
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.camera_alt_outlined,
                          color: (topicRule?.fg ?? _primary).withValues(
                            alpha: 0.55,
                          ),
                          size: 26,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          l10n.coverImageLabel,
                          style: TextStyle(
                            fontSize: 12,
                            color: (topicRule?.fg ?? _primary).withValues(
                              alpha: 0.55,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (topicRule != null)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        topicRule.label,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 10,
                  right: 10,
                  child: GestureDetector(
                    onTap: _pickCoverImage,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.camera_alt,
                            size: 12,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            l10n.changeCoverAction,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // 摘要/标签/加入专栏/标题植入统一装进一张白卡，行与行之间用
        // 0.5px 细线分隔——比之前"零散摆在页面米白底上"更成一体
        Container(
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDarkMode
                  ? Theme.of(context).dividerColor
                  : const Color(0xFFEBEBEB),
              width: 0.5,
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: TextField(
                  controller: _summaryCtrl,
                  decoration: InputDecoration(
                    filled: false,
                    hintText: l10n.addSummaryHint,
                    hintStyle: const TextStyle(
                      color: Color(0xFF888888),
                      fontSize: 13,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF888888),
                  ),
                  maxLines: 2,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              _rowDivider(isDarkMode),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ..._tags.map(
                      (tag) => GestureDetector(
                        onLongPress: () => setState(() => _tags.remove(tag)),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).dividerColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '#$tag',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).textTheme.bodyLarge?.color,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _addTag,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFD1D1D6)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.add, size: 12, color: Colors.grey),
                            const SizedBox(width: 3),
                            Text(
                              l10n.addTagAction,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _rowDivider(isDarkMode),
              _metaEntryRow(
                icon: Icons.view_column_outlined,
                iconBg: const Color(0xFFEEF0FF),
                iconColor: _primary,
                title: l10n.joinColumnAction,
                subtitle: _selectedColumnName ?? l10n.joinColumnSubtitleHint,
                onTap: _showColumnSheet,
              ),
              _rowDivider(isDarkMode),
              _metaEntryRow(
                icon: Icons.sell_outlined,
                iconBg: const Color(0xFFF5F5F5),
                iconColor: const Color(0xFF888888),
                title: l10n.titleInsertionAction,
                subtitle: _seriesTag.isNotEmpty || _subtitle.isNotEmpty
                    ? [
                        if (_seriesTag.isNotEmpty) _seriesTag,
                        if (_subtitle.isNotEmpty) _subtitle,
                      ].join(' · ')
                    : l10n.titleInsertionSubtitleHint,
                onTap: _showTitleInsertionSheet,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _rowDivider(bool isDarkMode) => Divider(
    height: 0.5,
    thickness: 0.5,
    indent: 14,
    endIndent: 14,
    color: isDarkMode
        ? Theme.of(context).dividerColor
        : const Color(0xFFF5F5F5),
  );

  Widget _metaEntryRow({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 15, color: iconColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFBBBBBB),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBBBBBB)),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomToolbar(AppLocalizations l10n, bool isDarkMode) {
    final (words, minutes) = computeBlockStats(_blocks);
    return Container(
      color: Theme.of(context).cardColor,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  ..._toolbarTypes.map(
                    (type) => _toolbarButton(
                      icon: blockTypeIcon(type),
                      tooltip: blockTypeLabel(l10n, type),
                      selected: _activeToolbarType == type,
                      onTap: () => _addBlock(type),
                    ),
                  ),
                  _toolbarButton(
                    icon: Icons.more_horiz,
                    tooltip: l10n.addContentBlockLabel,
                    selected: false,
                    onTap: _showBlockPicker,
                  ),
                ],
              ),
            ),
            Divider(
              height: 0.5,
              thickness: 0.5,
              color: isDarkMode
                  ? Theme.of(context).dividerColor
                  : const Color(0xFFEEEEEE),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                l10n.wordBlocksReadTimeLabel(words, _blocks.length, minutes),
                style: const TextStyle(fontSize: 11, color: Color(0xFFCCCCCC)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolbarButton({
    required IconData icon,
    required String tooltip,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            highlightColor: const Color(0xFFF0F0F0),
            splashColor: Colors.transparent,
            onTap: onTap,
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFF0F0F0) : null,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: const Color(0xFF555555)),
            ),
          ),
        ),
      ),
    );
  }

  void _showBlockPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BlockPickerSheet(
        onSelect: (type) {
          Navigator.pop(ctx);
          _addBlock(type);
        },
      ),
    );
  }

  void _showColumnSheet() {
    final l10n = AppLocalizations.of(context)!;
    String? tempId = _selectedColumnId;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(ctx).cardColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).padding.bottom + 12,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.joinColumnAction,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      l10n.myColumnsLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                ),
                ..._mockColumns.map((col) {
                  final selected = tempId == col.id;
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: GestureDetector(
                      onTap: () => setSheetState(() => tempId = col.id),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFFEEF0FF)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected
                                ? _primary
                                : const Color(0xFFEBEBEB),
                            width: selected ? 1.5 : 0.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: col.gradient),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                col.icon,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    col.name,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    l10n.columnArticlesSubscribers(
                                      col.articleCount,
                                      col.subscriberCount,
                                    ),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF8E8E93),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              selected
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              color: selected
                                  ? _primary
                                  : const Color(0xFFDDDDDD),
                              size: 22,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: GestureDetector(
                    onTap: () => setSheetState(() => tempId = null),
                    child: Row(
                      children: [
                        const Icon(Icons.block, size: 18, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text(
                          l10n.noColumnOption,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.grey,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          tempId == null
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: tempId == null
                              ? _primary
                              : const Color(0xFFDDDDDD),
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.comingSoonStayTuned)),
                    );
                  },
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFD1D1D6)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add, size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          l10n.createColumnAction,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        final chosen = tempId != null
                            ? _mockColumns.firstWhere((c) => c.id == tempId)
                            : null;
                        setState(() {
                          _selectedColumnId = tempId;
                          _selectedColumnName = chosen?.name;
                        });
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _ink,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        l10n.confirmAction,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showTitleInsertionSheet() {
    final l10n = AppLocalizations.of(context)!;
    final subtitleCtrl = TextEditingController(text: _subtitle);
    final issueCtrl = TextEditingController(text: _issueNumber);
    String tempSeriesTag = _seriesTag;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(ctx).cardColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              padding: EdgeInsets.fromLTRB(
                16,
                10,
                16,
                MediaQuery.of(ctx).padding.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.titleInsertionAction,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.subtitleLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: subtitleCtrl,
                      onChanged: (_) => setSheetState(() {}),
                      decoration: InputDecoration(
                        hintText: l10n.subtitleHint,
                        filled: true,
                        fillColor: const Color(0xFFF5F5F5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      l10n.seriesTagLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _seriesTagOptions.map((tag) {
                        final selected = tempSeriesTag == tag;
                        return GestureDetector(
                          onTap: () => setSheetState(
                            () => tempSeriesTag = selected ? '' : tag,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: selected ? _ink : const Color(0xFFF5F5F5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              tag,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: selected
                                    ? Colors.white
                                    : const Color(0xFF555555),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      l10n.issueNumberLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: issueCtrl,
                      onChanged: (_) => setSheetState(() {}),
                      decoration: InputDecoration(
                        hintText: l10n.issueNumberHint,
                        filled: true,
                        fillColor: const Color(0xFFF5F5F5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.previewLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAFAF8),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (tempSeriesTag.isNotEmpty) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _ink,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    tempSeriesTag,
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Expanded(
                                child: Text(
                                  _titleCtrl.text.isEmpty
                                      ? l10n.notePlaceholderTitle
                                      : _titleCtrl.text,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: _ink,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          if (subtitleCtrl.text.isNotEmpty ||
                              issueCtrl.text.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              [
                                if (subtitleCtrl.text.isNotEmpty)
                                  subtitleCtrl.text,
                                if (issueCtrl.text.isNotEmpty) issueCtrl.text,
                              ].join(' · '),
                              style: const TextStyle(
                                fontSize: 12,
                                color: _primary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _subtitle = subtitleCtrl.text.trim();
                            _seriesTag = tempSeriesTag;
                            _issueNumber = issueCtrl.text.trim();
                          });
                          Navigator.pop(ctx);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _ink,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          l10n.done,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
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

  Future<void> _pickCoverImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 600,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: 'cover.jpg',
          contentType: DioMediaType('image', 'jpeg'),
        ),
      });
      final res = await ref
          .read(apiClientProvider)
          .post('/auth/files/upload', data: formData);
      if (!res.success || res.data == null) return;
      final url = (res.data as Map)['url'] as String?;
      if (url != null && mounted) setState(() => _coverImageUrl = url);
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.saveFailedWithReason('$e'))),
        );
      }
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _summaryCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }
}
