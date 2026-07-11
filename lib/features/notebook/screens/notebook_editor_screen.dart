import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/membership_utils.dart';
import '../../../core/widgets/pro_gate.dart';
import '../../../features/auth/auth_service.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../models/notebook_language.dart';
import '../models/notebook_model.dart';
import '../services/notebook_service.dart';
import '../widgets/add_cell_bar.dart';
import '../widgets/keyboard_toolbar.dart';
import '../widgets/language_selector.dart';
import '../widgets/notebook_topbar.dart';
import '../widgets/snippet_bar.dart';

const _primary = Color(0xFF6366F1);

// 单页 CodeMirror 6 编辑器，所有 cell 共用同一个 WebView 实例——不是每个
// cell 各开一个 WebView（那样 N 个 cell 就要重复加载 N 份 esm.sh 模块，
// 内存/性能开销随 cell 数线性增长）。点开某个 cell 时用这份 HTML 起一个
// 全屏编辑页，setCode/setLanguage 灌入内容，编辑页关掉后 WebView 也随之
// 销毁，不会有多个实例同时占着内存。
//
// 快捷片段栏/键盘辅助栏改成 Flutter 侧的 SnippetBar/KeyboardToolbar 之后，
// WebView 内部不再需要自己的 #toolbar——所有插入操作统一走 window.ins()
// 这一个 JS 桥（Flutter 用 evaluateJavascript 调用），不重复维护两套UI。
//
// 深浅主题不是靠 JS 运行时切换，而是 build 时把颜色值插进这份 HTML 里
// 生成两份不同内容——WebView 的 initialData 本来就是一次性灌入，没有
// "已经在跑的 WebView 里切主题"这个需求（切主题会整页重建），没必要
// 用 CSS 变量 + JS toggle 这种更复杂的方案
String _buildEditorHtml({required bool isDark}) {
  final bg = isDark ? '#0A0A1A' : '#FAFAF8';
  final gutterBg = isDark ? '#0A0A1A' : '#FAFAF8';
  final gutterBorder = isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.06)';
  final gutterText = isDark ? 'rgba(255,255,255,0.2)' : 'rgba(0,0,0,0.25)';
  final contentText = isDark ? '#E2E8F0' : '#1A1A1A';
  final tooltipBg = isDark ? '#16162A' : '#FFFFFF';
  final tooltipText = isDark ? 'rgba(255,255,255,0.8)' : 'rgba(0,0,0,0.75)';
  final loadingText = isDark ? 'rgba(255,255,255,0.4)' : 'rgba(0,0,0,0.35)';
  // token 配色——深色是原来那套霓虹色系；浅色换成对应的加深版本，避免
  // 直接照搬深色那套在白底上糊成一片看不清
  final tokKeyword = isDark ? '#818CF8' : '#4F46E5';
  final tokString = isDark ? '#4ADE80' : '#15803D';
  final tokComment = isDark ? '#6B7280' : '#9CA3AF';
  final tokNumber = isDark ? '#F59E0B' : '#B45309';
  final tokFunction = isDark ? '#60A5FA' : '#1D4ED8';
  final tokClassName = isDark ? '#F472B6' : '#BE185D';
  final tokOperator = isDark ? '#C084FC' : '#7E22CE';
  final tokVariableName = isDark ? '#E2E8F0' : '#1F2937';
  final tokTypeName = isDark ? '#34D399' : '#047857';
  final tokBoolNull = isDark ? '#FB923C' : '#C2410C';
  final tokPunctuation = isDark ? 'rgba(255,255,255,0.4)' : 'rgba(0,0,0,0.4)';

  return '''
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport"
  content="width=device-width,
  initial-scale=1.0, maximum-scale=1.0">
<style>
* { box-sizing: border-box; margin: 0; padding: 0; }

body {
  background: $bg;
  font-family: 'JetBrains Mono', 'Fira Code',
    'Cascadia Code', monospace;
  overscroll-behavior: none;
}

.cm-editor {
  height: 100vh;
  font-size: 14px;
  line-height: 1.6;
  padding-bottom: 16px;
}

.cm-editor.cm-focused {
  outline: none;
}

.cm-scroller {
  overflow: auto;
  -webkit-overflow-scrolling: touch;
}

.cm-editor .cm-content {
  padding: 12px 0;
  caret-color: #6366F1;
  color: $contentText;
}

.cm-editor .cm-activeLine {
  background: rgba(99,102,241,0.08) !important;
}

.cm-editor .cm-gutters {
  background: $gutterBg;
  border-right: 1px solid $gutterBorder;
  color: $gutterText;
  min-width: 40px;
}

.cm-editor .cm-activeLineGutter {
  background: rgba(99,102,241,0.12);
  color: #6366F1;
}

.cm-editor .cm-selectionBackground {
  background: rgba(99,102,241,0.25) !important;
}

.cm-editor .cm-matchingBracket {
  background: rgba(99,102,241,0.3);
  border: 1px solid #6366F1;
  border-radius: 2px;
}

.cm-tooltip-autocomplete {
  background: $tooltipBg !important;
  border: 1px solid rgba(99,102,241,0.3) !important;
  border-radius: 8px !important;
  box-shadow: 0 8px 24px rgba(0,0,0,0.4) !important;
  font-size: 13px !important;
}

.cm-tooltip-autocomplete > ul > li {
  padding: 5px 12px !important;
  color: $tooltipText !important;
}

.cm-tooltip-autocomplete > ul > li[aria-selected] {
  background: rgba(99,102,241,0.3) !important;
  color: #fff !important;
}

.cm-searchMatch {
  background: rgba(245,158,11,0.3);
  border-radius: 2px;
}

.tok-keyword    { color: $tokKeyword; font-weight: 500; }
.tok-string     { color: $tokString; }
.tok-comment    { color: $tokComment; font-style: italic; }
.tok-number     { color: $tokNumber; }
.tok-function   { color: $tokFunction; }
.tok-className  { color: $tokClassName; }
.tok-operator   { color: $tokOperator; }
.tok-variableName { color: $tokVariableName; }
.tok-typeName   { color: $tokTypeName; }
.tok-bool       { color: $tokBoolNull; }
.tok-null       { color: $tokBoolNull; }
.tok-regexp     { color: $tokString; }
.tok-punctuation { color: $tokPunctuation; }

#loading {
  position: fixed;
  inset: 0;
  background: $bg;
  display: flex;
  align-items: center;
  justify-content: center;
  color: $loadingText;
  font-size: 13px;
  z-index: 200;
}
</style>
</head>
<body>
<div id="editor"></div>
<div id="loading">正在加载编辑器…</div>

<script type="module">
import {EditorView, keymap, lineNumbers,
  highlightActiveLineGutter,
  highlightActiveLine, drawSelection,
  dropCursor, rectangularSelection,
  crosshairCursor, highlightSpecialChars}
  from 'https://esm.sh/@codemirror/view@6';
import {EditorState, Compartment}
  from 'https://esm.sh/@codemirror/state@6';
import {defaultKeymap, historyKeymap, history,
  indentWithTab, cursorLineUp, cursorLineDown}
  from 'https://esm.sh/@codemirror/commands@6';
import {python}
  from 'https://esm.sh/@codemirror/lang-python@6';
import {javascript}
  from 'https://esm.sh/@codemirror/lang-javascript@6';
import {sql}
  from 'https://esm.sh/@codemirror/lang-sql@6';
import {markdown}
  from 'https://esm.sh/@codemirror/lang-markdown@6';
import {autocompletion, completionKeymap,
  closeBrackets, closeBracketsKeymap}
  from 'https://esm.sh/@codemirror/autocomplete@6';
import {foldGutter, foldKeymap,
  indentOnInput, syntaxHighlighting,
  defaultHighlightStyle, bracketMatching,
  StreamLanguage}
  from 'https://esm.sh/@codemirror/language@6';
import {lintKeymap}
  from 'https://esm.sh/@codemirror/lint@6';
import {classHighlighter}
  from 'https://esm.sh/@lezer/highlight@1';
// R/Julia 官方没有 @codemirror/lang-* 包，用 CodeMirror 团队自己维护的
// legacy-modes（CodeMirror 5 时代模式的移植版）通过 StreamLanguage 接入，
// 不是拿一个不知道谁维护的三方包赌
import {r as rMode}
  from 'https://esm.sh/@codemirror/legacy-modes@6/mode/r';
import {julia as juliaMode}
  from 'https://esm.sh/@codemirror/legacy-modes@6/mode/julia';

// 语言切换器
const langConf = new Compartment();

// Python关键字自动补全
const pythonCompletions = [
  'import','from','as','def','class',
  'return','if','elif','else','for',
  'while','try','except','finally',
  'with','lambda','yield','pass',
  'break','continue','True','False',
  'None','and','or','not','in','is',
  'print','len','range','list','dict',
  'set','tuple','str','int','float',
  'bool','type','input','open','sum',
  'max','min','sorted','enumerate',
  'zip','map','filter','isinstance',
  'hasattr','getattr','setattr',
  'super','self','cls',
].map(label => ({label, type: 'keyword'}));

function pythonCompletion(context) {
  const word = context.matchBefore(/\\w*/);
  if (!word || (word.from == word.to &&
      !context.explicit)) return null;
  return {
    from: word.from,
    options: pythonCompletions,
  };
}

const extensions = [
  lineNumbers(),
  highlightActiveLineGutter(),
  highlightSpecialChars(),
  history(),
  foldGutter(),
  drawSelection(),
  dropCursor(),
  EditorState.allowMultipleSelections.of(true),
  indentOnInput(),
  syntaxHighlighting(defaultHighlightStyle),
  syntaxHighlighting(classHighlighter),
  bracketMatching(),
  closeBrackets(),
  autocompletion({
    override: [pythonCompletion],
    activateOnTyping: true,
  }),
  rectangularSelection(),
  crosshairCursor(),
  highlightActiveLine(),
  keymap.of([
    ...closeBracketsKeymap,
    ...defaultKeymap,
    ...historyKeymap,
    ...foldKeymap,
    ...completionKeymap,
    ...lintKeymap,
    indentWithTab,
  ]),
  langConf.of(python()),
  EditorView.updateListener.of(v => {
    if (v.docChanged) {
      const content = v.state.doc.toString();
      if (window.flutter_inappwebview) {
        window.flutter_inappwebview
          .callHandler('onContentChange', content);
      }
    }
  }),
];

const view = new EditorView({
  state: EditorState.create({
    doc: '',
    extensions,
  }),
  parent: document.getElementById('editor'),
});

window.setCode = (code) => {
  view.dispatch({
    changes: {
      from: 0,
      to: view.state.doc.length,
      insert: code,
    }
  });
};

window.getCode = () =>
  view.state.doc.toString();

window.setLanguage = (lang) => {
  const langMap = {
    python: python(),
    javascript: javascript(),
    sql: sql(),
    markdown: markdown(),
    r: StreamLanguage.define(rMode),
    julia: StreamLanguage.define(juliaMode),
  };
  view.dispatch({
    effects: langConf.reconfigure(
      langMap[lang] || python())
  });
};

window.focusEditor = () => view.focus();

// 键盘辅助栏的上下方向键——按行移动光标，不是移动选区
window.moveCursor = (dir) => {
  const cmd = dir < 0 ? cursorLineUp : cursorLineDown;
  cmd(view);
  view.focus();
};

// 工具栏插入字符——括号/引号类是"包住选区"，其余是纯文本插入
window.ins = (text) => {
  const sel = view.state.selection.main;
  const pairs = {
    '()': ['(', ')'],
    '[]': ['[', ']'],
    '{}': ['{', '}'],
    "''": ["'", "'"],
    '""': ['"', '"'],
  };
  if (pairs[text]) {
    const [l, r] = pairs[text];
    const selected = view.state.sliceDoc(
      sel.from, sel.to);
    view.dispatch({
      changes: {
        from: sel.from, to: sel.to,
        insert: l + selected + r,
      },
      selection: {
        anchor: sel.from + 1,
        head: sel.to + 1,
      }
    });
  } else {
    view.dispatch({
      changes: {
        from: sel.from, to: sel.to,
        insert: text,
      },
      selection: {
        anchor: sel.from + text.length
      }
    });
  }
  view.focus();
};

const loadingEl = document.getElementById('loading');
setTimeout(() => {
  if (loadingEl) loadingEl.remove();
  if (window.flutter_inappwebview) {
    window.flutter_inappwebview
      .callHandler('editorReady');
  }
}, 300);
</script>
</body>
</html>
''';
}

// cell 输出的渲染逻辑跟 cell 列表页/单 cell 全屏编辑页共用，提成顶层函数
// 而不是 State 的方法，两边都能调
Widget buildCellOutput(BuildContext context, String output, String? type) {
  switch (type) {
    case 'latex':
      final tex = output
          .replaceAll(r'$$', '')
          .replaceAll(r'\[', '')
          .replaceAll(r'\]', '')
          .trim();
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Math.tex(
          tex,
          textStyle: const TextStyle(fontSize: 16),
          onErrorFallback: (err) => Text(
            output,
            style: const TextStyle(color: Colors.red, fontSize: 12),
          ),
        ),
      );
    case 'markdown':
      return MarkdownBody(data: output);
    case 'info':
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7E6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          output,
          style: const TextStyle(fontSize: 13, color: Color(0xFFD97706)),
        ),
      );
    case 'error':
      return Container(
        padding: const EdgeInsets.only(left: 8),
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: Color(0xFFFCA5A5), width: 2)),
        ),
        child: SelectableText(
          output,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: Color(0xFFDC2626),
            height: 1.5,
          ),
        ),
      );
    case 'image':
      try {
        final base64Data = output.contains(',') ? output.split(',').last : output;
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(base64Decode(base64Data), fit: BoxFit.contain),
        );
      } catch (e) {
        return Text(
          AppLocalizations.of(context)!.chartRenderFailedWithReason('$e'),
          style: const TextStyle(color: Colors.red),
        );
      }
    case 'html':
      return SizedBox(
        height: 200,
        child: InAppWebView(
          initialData: InAppWebViewInitialData(
            data:
                '''
<html>
<head>
<style>
body{font-family:monospace;font-size:12px;margin:0}
table{border-collapse:collapse;width:100%}
th,td{border:1px solid #e5e5e5;padding:4px 8px;text-align:left}
th{background:#f5f5f5;font-weight:600}
</style>
</head>
<body>$output</body>
</html>
              ''',
          ),
        ),
      );
    default:
      return SelectableText(
        output,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.6,
          color: Theme.of(context).textTheme.bodyLarge?.color,
        ),
      );
  }
}

class NotebookEditorScreen extends ConsumerStatefulWidget {
  final String nbId;
  const NotebookEditorScreen({super.key, required this.nbId});
  @override
  ConsumerState<NotebookEditorScreen> createState() => _EditorState();
}

class _EditorState extends ConsumerState<NotebookEditorScreen> {
  Notebook? _nb;
  NotebookService? _svc;
  Timer? _saveTimer;
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String?> _outputs = {};
  final Map<String, String?> _outputTypes = {};
  final Map<String, bool> _running = {};
  final ScrollController _scrollCtrl = ScrollController();

  InAppWebViewController? _webCtrl;
  bool _webReady = false;
  // 每个 cell 最多同时有一次运行在等结果，key 是 cell.id
  final Map<String, Completer<String>> _pendingRuns = {};

  // 复用 Web 端已有的 compiler.js（Pyodide 基础设施），不重新造轮子
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

// 测试函数是否可用
window.testReady = () => {
  return typeof window.runCode === 'function' ? 'ok' : 'fail';
};

// 通知 Flutter 就绪
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final user = ref.read(currentUserProvider);
    _svc = NotebookService(user?.id ?? 'guest');
    final nb = await _svc!.load(widget.nbId);
    if (nb != null) {
      setState(() {
        _nb = nb;
      });
      for (final cell in nb.cells) {
        _controllers[cell.id] = TextEditingController(text: cell.code);
        _outputs[cell.id] = cell.output;
        _outputTypes[cell.id] = cell.outputType;
        _running[cell.id] = false;
      }
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), () {
      if (_nb != null) _svc!.save(_nb!);
    });
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // 打开 CodeMirror 6 全屏编辑页。所有 cell 共用同一份编辑器 HTML，编辑页
  // 关掉时 WebView 也随之销毁——不会同时有多个 WebView 实例常驻。运行
  // 走的还是现有 _runCell（Pyodide 隐藏 WebView 那条链路），不是另起一套。
  // 返回值非 null 时说明用户在编辑页里点了"+代码/文本/LaTeX"，弹回来
  // 之后接着帮它新建一个 cell 并滚过去，不用用户自己再点一次
  Future<void> _openCellEditor(NotebookCell cell) async {
    final ctrl =
        _controllers[cell.id] ??
        (_controllers[cell.id] = TextEditingController(text: cell.code));
    final addType = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _CodeEditorPage(
          initialCode: cell.code,
          language: cell.type,
          notebookTitle: _nb?.name ?? 'Notebook',
          initialOutput: _outputs[cell.id],
          initialOutputType: _outputTypes[cell.id],
          onContentChanged: (code) {
            cell.code = code;
            ctrl.text = code;
            _scheduleSave();
          },
          onLanguageChanged: (lang) {
            setState(() => cell.type = lang.cmKey);
            _scheduleSave();
          },
          onRun: (code) async {
            cell.code = code;
            ctrl.text = code;
            await _runCell(cell);
            return (_outputs[cell.id], _outputTypes[cell.id]);
          },
        ),
      ),
    );
    if (addType != null) _addCell(addType);
  }

  // 统一更新单个 cell 的输出：同步进内存态 map（驱动 UI）和 cell 字段（用于持久化）。
  // 加 mounted 守卫——cell 执行途中用户可能已经退出这个页面
  void _setOutput(NotebookCell cell, String? output, String? outputType) {
    if (!mounted) return;
    setState(() {
      _outputs[cell.id] = output;
      _outputTypes[cell.id] = outputType;
      cell.output = output;
      cell.outputType = outputType;
    });
  }

  void _addCell(String type) {
    if (_nb == null) return;
    final cell = NotebookCell(
      id: 'cell_${DateTime.now().millisecondsSinceEpoch}',
      type: type,
      code: '',
    );
    final ctrl = TextEditingController();
    setState(() {
      _nb!.cells.add(cell);
      _controllers[cell.id] = ctrl;
      _outputs[cell.id] = null;
      _outputTypes[cell.id] = null;
      _running[cell.id] = false;
    });
    _scheduleSave();
    // 滚动到底部
    Future.delayed(const Duration(milliseconds: 100), () {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _deleteCell(String cellId) {
    if (_nb == null) return;
    _controllers[cellId]?.dispose();
    _controllers.remove(cellId);
    _outputs.remove(cellId);
    _outputTypes.remove(cellId);
    _running.remove(cellId);
    setState(() => _nb!.cells.removeWhere((c) => c.id == cellId));
    _scheduleSave();
  }

  // SQL cell 自动包装成 Python，通过 sqlite3 执行；如果前面的 cell 已经产出了
  // 一个叫 df 的 DataFrame，顺手建成临时表，方便直接写 SQL 查询它
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

  Future<void> _runCell(NotebookCell cell) async {
    switch (cell.type) {
      case 'python':
      case 'sql':
        await _runWithPyodide(cell);
        break;
      case 'javascript':
        await _runJavaScript(cell);
        break;
      case 'latex':
        _setOutput(cell, cell.code, 'latex');
        break;
      case 'markdown':
        _setOutput(cell, cell.code, 'markdown');
        break;
      case 'r':
      case 'julia':
        _setOutput(
          cell,
          AppLocalizations.of(
            context,
          )!.langSupportComingSoon(cell.type.toUpperCase()),
          'info',
        );
        break;
      default:
        _setOutput(
          cell,
          AppLocalizations.of(context)!.unsupportedCellType,
          'info',
        );
    }
    _scheduleSave();
  }

  Future<void> _runWithPyodide(NotebookCell cell) async {
    final l10n = AppLocalizations.of(context)!;
    if (_webCtrl == null) {
      _showSnack(l10n.envInitializing);
      return;
    }

    // compiler.js 可能还没加载完（首次要拉 Pyodide），耐心等最多 60 秒，
    // 而不是直接判失败——这是之前"运行完成（无输出）"的根因之一
    if (!_webReady) {
      _setOutput(cell, l10n.pythonEnvLoading, 'info');
      for (var i = 0; i < 60; i++) {
        await Future.delayed(const Duration(seconds: 1));
        if (_webReady) break;
      }
      if (!mounted) return;
      if (!_webReady) {
        _setOutput(cell, l10n.loadTimeoutRestart, 'error');
        return;
      }
    }

    // 预扫描 input() 调用，运行前一次性弹框收集，不做运行时阻塞
    // （Pyodide 跑在 WebView 主线程，Atomics.wait 那套同步阻塞方案在这里用不了）
    final inputCount = _countInputCalls(cell.code);
    debugPrint(
      '[Notebook] cell ${cell.id} inputCount=$inputCount code="${cell.code}"',
    );
    var userInputs = <String>[];
    if (inputCount > 0) {
      debugPrint('[Notebook] calling _collectInputs...');
      final inputs = await _collectInputs(cell.code, inputCount);
      debugPrint(
        '[Notebook] _collectInputs returned: $inputs (mounted=$mounted)',
      );
      if (!mounted || inputs == null) return; // 用户取消
      userInputs = inputs;
    }

    if (!mounted) return;
    setState(() => _running[cell.id] = true);

    final isSql = cell.type == 'sql';
    var effectiveCode = isSql ? _wrapSql(cell.code) : cell.code;

    // 后面 evaluateJavascript 的 async 回调没法安全地在事后再取 l10n（这时
    // widget 可能已经被销毁），提前把这几条要塞进 JS 字符串的翻译值取出来
    final compilerNotReadyMsg = l10n.compilerNotReady;
    final execTimeoutMsg = l10n.execTimeout;

    if (userInputs.isNotEmpty) {
      // 把 input() 换成从预收集队列里取值的 mock；用完立刻还原，
      // 否则会一直污染 Pyodide 的全局解释器状态，影响后面其它 cell 的 input()。
      //
      // 不走 js.window——Pyodide 沙箱里没有 window（不是浏览器主文档环境），
      // 也拿不到 pyodide.globals.set，因为我们只从 compiler.js 导入了黑盒的
      // compile()/runCode()，手上没有它内部那个 pyodide 实例的引用。
      // 直接把输入值当 Python list 字面量写进生成的源码里最简单可靠，
      // JSON 数组语法本身就是合法的 Python list 字面量，不需要任何桥接。
      final indentedCode = effectiveCode
          .split('\n')
          .map((l) => '    $l')
          .join('\n');
      effectiveCode =
          '''
import builtins
_input_queue = ${jsonEncode(userInputs)}
_orig_input = builtins.input
def _mock_input(prompt=''):
    val = _input_queue.pop(0) if _input_queue else ''
    print(f"{prompt}{val}")
    return val
builtins.input = _mock_input
try:
$indentedCode
finally:
    builtins.input = _orig_input
''';
    }

    try {
      // 用 JavaScriptHandler 双向通信，比 evaluateJavascript 的返回值更可靠
      // （evaluateJavascript 在不同平台/版本下对返回值的类型编组不一致）
      final completer = Completer<String>();
      _pendingRuns[cell.id] = completer;

      await _webCtrl!.evaluateJavascript(
        source:
            '''
(async () => {
  try {
    if (typeof window.runCode !== 'function') {
      window.flutter_inappwebview.callHandler(
        'onRunResult', ${jsonEncode(cell.id)},
        JSON.stringify([{type:'error', content:${jsonEncode(compilerNotReadyMsg)}}])
      );
      return;
    }
    const outputs = await window.runCode(${jsonEncode(effectiveCode)}, "python");
    window.flutter_inappwebview.callHandler(
      'onRunResult', ${jsonEncode(cell.id)}, outputs
    );
  } catch(e) {
    window.flutter_inappwebview.callHandler(
      'onRunResult', ${jsonEncode(cell.id)},
      JSON.stringify([{type:'error', content: String(e)}])
    );
  }
})();
''',
      );

      // pandas/matplotlib 这类重量级包 Pyodide 是首次 import 才会懒加载，
      // 冷启动经常超过之前的 30 秒——不是这次UI重写引入的问题，是这个阈值
      // 对重包冷加载本来就偏紧，调宽到 90 秒
      final raw = await completer.future.timeout(
        const Duration(seconds: 90),
        onTimeout: () => jsonEncode([
          {'type': 'error', 'content': execTimeoutMsg},
        ]),
      );

      debugPrint('[Notebook] raw output: $raw');

      if (!mounted) return;

      dynamic parsed;
      try {
        parsed = jsonDecode(raw);
      } catch (_) {
        // 不是合法 JSON，直接当纯文本显示
        _setOutput(cell, raw, 'text');
        return;
      }

      final outputs = parsed is List ? parsed : [parsed];
      String? foundOutput;
      String? foundType;
      for (final out in outputs) {
        if (out is! Map) continue;
        final type = out['type'] as String? ?? 'text';
        final content = out['content'] as String? ?? '';
        // 跳过调试信息和空文本
        if (['viz-suggestion', 'missing-package', 'debug'].contains(type)) {
          continue;
        }
        if (type == 'text' && content.trim().isEmpty) continue;
        foundOutput = content;
        foundType = type;
        break;
      }
      _setOutput(
        cell,
        foundOutput ?? l10n.runCompleteNoOutputChecked,
        foundType ?? 'text',
      );
    } catch (e) {
      _setOutput(cell, l10n.runErrorWithReason('$e'), 'error');
    } finally {
      _pendingRuns.remove(cell.id);
      if (mounted) setState(() => _running[cell.id] = false);
      _scheduleSave();
    }
  }

  // 统计 input() 调用次数（简单正则，不是真正的 Python 解析——字符串/注释里
  // 出现的 "input(" 也会被计入，属于已知限制）
  int _countInputCalls(String code) {
    final regex = RegExp(r'\binput\s*\(');
    return regex.allMatches(code).length;
  }

  // 预收集用户输入：运行前一次性弹框问完，而不是运行时暂停等待
  Future<List<String>?> _collectInputs(String code, int count) async {
    final l10n = AppLocalizations.of(context)!;
    // 尽量提取 input() 里的提示文字，提取不到就用默认占位
    final prompts = <String>[];
    final regex = RegExp("input\\s*\\(\\s*['\"]?(.*?)['\"]?\\s*\\)");
    for (final m in regex.allMatches(code)) {
      prompts.add(m.group(1)?.trim() ?? l10n.inputPromptDefault);
    }
    while (prompts.length < count) {
      prompts.add(l10n.inputPromptDefault);
    }

    final controllers = List.generate(count, (_) => TextEditingController());
    // 显式给每个输入框绑定自己的 FocusNode——不传的话 Flutter 会在弹窗因键盘
    // 弹出触发的 MediaQuery 变化而重建时自动创建/回收 FocusNode，容易跟弹窗
    // 自身的卸载顺序对不上，炸出 "_dependents.isEmpty" 这个断言
    final focusNodes = List.generate(count, (_) => FocusNode());

    final result = await showDialog<List<String>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(
          l10n.codeNeedsInput,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.fillAllInputsFirst,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 12),
              ...List.generate(
                count,
                (i) => Padding(
                  key: ValueKey('input_field_$i'),
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: controllers[i],
                    focusNode: focusNodes[i],
                    decoration: InputDecoration(
                      labelText: prompts[i].isEmpty
                          ? l10n.inputFieldLabel(i + 1)
                          : prompts[i],
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              l10n.cancel,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () =>
                Navigator.pop(ctx, controllers.map((c) => c.text).toList()),
            child: Text(l10n.run, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    for (final c in controllers) {
      c.dispose();
    }
    for (final f in focusNodes) {
      f.dispose();
    }
    return result;
  }

  // JavaScript 直接在承载 Pyodide 的隐藏 WebView 里 eval
  Future<void> _runJavaScript(NotebookCell cell) async {
    final l10n = AppLocalizations.of(context)!;
    if (_webCtrl == null) {
      _showSnack(l10n.envInitializing);
      return;
    }
    if (!mounted) return;
    setState(() => _running[cell.id] = true);
    try {
      // 捕获 console.log 输出，返回值统一走 JSON.stringify，避免不同平台
      // evaluateJavascript 对返回对象的处理不一致
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
    ${cell.code}
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
        _setOutput(cell, l10n.runCompleteNoOutput, 'text');
        return;
      }
      final map = jsonDecode(result.toString()) as Map;
      if (map['ok'] == true) {
        _setOutput(
          cell,
          (map['output'] as String?) ?? l10n.runCompleteNoOutput,
          'text',
        );
      } else {
        _setOutput(
          cell,
          map['error']?.toString() ?? l10n.unknownError,
          'error',
        );
      }
    } catch (e) {
      _setOutput(cell, e.toString(), 'error');
    } finally {
      if (mounted) setState(() => _running[cell.id] = false);
      _scheduleSave();
    }
  }

  Future<void> _runAll() async {
    if (_nb == null) return;
    // 顺序执行：SQL cell 依赖前面 cell 产出的 df，并发跑会互相踩
    for (final cell in _nb!.cells) {
      await _runCell(cell);
    }
  }

  Future<void> _openFileImport() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'ipynb',
        'py',
        'r',
        'sql',
        'md',
        'tex',
        'csv',
        'xlsx',
        'json',
        'xml',
      ],
    );
    if (result == null || !mounted) return;
    final file = result.files.first;
    final ext = file.extension?.toLowerCase() ?? '';
    final bytes = file.bytes;
    if (bytes == null) return;

    if (ext == 'ipynb') {
      final content = utf8.decode(bytes);
      final imported = NotebookService.fromIpynb(content, file.name);
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.importJupyterNotebook),
          content: Text(l10n.foundCellsImportConfirm(imported.cells.length)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.cancel),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _primary),
              onPressed: () {
                Navigator.pop(ctx);
                if (_nb == null) return;
                setState(() {
                  _nb!.cells.addAll(imported.cells);
                  for (final c in imported.cells) {
                    _controllers[c.id] = TextEditingController(text: c.code);
                    _outputs[c.id] = c.output;
                    _outputTypes[c.id] = c.outputType;
                    _running[c.id] = false;
                  }
                });
                _scheduleSave();
              },
              child: Text(
                l10n.import,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
    } else if (['csv', 'xlsx', 'json', 'xml'].contains(ext)) {
      await _importDataFile(file.name, bytes, ext);
    } else {
      final content = utf8.decode(bytes);
      final langMap = {
        'py': 'python',
        'r': 'r',
        'sql': 'sql',
        'md': 'markdown',
        'tex': 'latex',
      };
      final lang = langMap[ext] ?? 'python';

      if (_nb == null) return;
      final cell = NotebookCell(
        id: 'cell_${DateTime.now().millisecondsSinceEpoch}',
        type: lang,
        code: content,
      );
      final ctrl = TextEditingController(text: content);
      setState(() {
        _nb!.cells.add(cell);
        _controllers[cell.id] = ctrl;
        _outputs[cell.id] = null;
        _outputTypes[cell.id] = null;
        _running[cell.id] = false;
      });
      _scheduleSave();
    }
  }

  // 数据文件上传到后端 COS，并插入对应的读取代码
  Future<void> _importDataFile(
    String filename,
    Uint8List bytes,
    String ext,
  ) async {
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: filename,
          contentType: DioMediaType('application', ext),
        ),
      });

      final l10n = AppLocalizations.of(context)!;
      final api = ref.read(apiClientProvider);
      final res = await api.post('/auth/files/upload', data: formData);
      if (!res.success) {
        _showSnack(l10n.uploadFailedWithReason('${res.message}'));
        return;
      }

      final varName = filename
          .replaceAll(RegExp(r'\.[^.]+$'), '')
          .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');

      final importCode = ext == 'csv'
          ? 'import pandas as pd\n$varName = pd.read_csv("$filename")\nprint($varName.shape)\n$varName.head()'
          : ext == 'xlsx'
          ? 'import pandas as pd\n$varName = pd.read_excel("$filename")\nprint($varName.shape)\n$varName.head()'
          : ext == 'json'
          ? 'import pandas as pd, json\n$varName = pd.read_json("$filename")\nprint($varName.shape)\n$varName.head()'
          : 'import pandas as pd\n$varName = pd.read_xml("$filename")\nprint($varName.shape)';

      if (_nb == null) return;
      final cell = NotebookCell(
        id: 'cell_${DateTime.now().millisecondsSinceEpoch}',
        type: 'python',
        code: importCode,
      );
      final ctrl = TextEditingController(text: importCode);
      setState(() {
        _nb!.cells.add(cell);
        _controllers[cell.id] = ctrl;
        _outputs[cell.id] = null;
        _outputTypes[cell.id] = null;
        _running[cell.id] = false;
      });
      _scheduleSave();

      _showSnack(l10n.fileImportedTapToRun(filename));
    } catch (e) {
      if (!mounted) return;
      _showSnack(AppLocalizations.of(context)!.uploadFailedWithReason('$e'));
    }
  }

  Future<void> _exportIpynb() async {
    if (_nb == null) return;
    final ipynb = NotebookService.toIpynb(_nb!);
    final path = await FilePicker.platform.saveFile(
      fileName: '${_nb!.name}.ipynb',
      bytes: Uint8List.fromList(utf8.encode(ipynb)),
    );
    if (path != null && mounted) {
      _showSnack(AppLocalizations.of(context)!.exportedToPath(path));
    }
  }

  void _clearOutputs() {
    if (_nb == null) return;
    setState(() {
      for (final cell in _nb!.cells) {
        cell.output = null;
        cell.outputType = null;
        _outputs[cell.id] = null;
        _outputTypes[cell.id] = null;
      }
    });
    _scheduleSave();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    for (final c in _controllers.values) {
      c.dispose();
    }
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // 顶部栏/底部工具栏之前写死用 cardColor（浅色下是纯白），中间 Cell
    // 列表画布走的是 Scaffold 自己的 scaffoldBackgroundColor（浅色下是
    // 偏灰的 #F7F7FB）——两个颜色不一样，顶栏/底栏跟画布之间有一条不易
    // 察觉但确实存在的接缝，暗色下更明显。跟论坛主页那次一样，统一改用
    // scaffoldBackgroundColor，不再另起一个颜色
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                // 顶部栏
                Container(
                  color: bg,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          if (_nb != null) _svc!.save(_nb!);
                          Navigator.pop(context);
                        },
                        child: Row(
                          children: [
                            const Icon(
                              Icons.arrow_back_ios,
                              size: 16,
                              color: _primary,
                            ),
                            Text(
                              l10n.back,
                              style: const TextStyle(
                                fontSize: 13,
                                color: _primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _nb?.name ?? 'Notebook',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      ProGate(
                        check: MembershipUtils.canRunNotebook,
                        featureName: 'Notebook 运行',
                        child: GestureDetector(
                          onTap: _runAll,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.play_arrow,
                                  color: Colors.white,
                                  size: 15,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  l10n.runAll,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: Icon(
                          Icons.more_vert,
                          color: Colors.grey[600],
                          size: 20,
                        ),
                        itemBuilder: (ctx) => [
                          PopupMenuItem(
                            value: 'export',
                            child: Row(
                              children: [
                                const Icon(Icons.download, size: 18),
                                const SizedBox(width: 8),
                                Text(l10n.exportIpynb),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'clear',
                            child: Row(
                              children: [
                                const Icon(Icons.delete_outline, size: 18),
                                const SizedBox(width: 8),
                                Text(l10n.clearOutputs),
                              ],
                            ),
                          ),
                        ],
                        onSelected: (value) {
                          if (value == 'export') {
                            _exportIpynb();
                          } else if (value == 'clear') {
                            _clearOutputs();
                          }
                        },
                      ),
                    ],
                  ),
                ),

                // Cell列表
                Expanded(
                  child: _nb == null
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.all(12),
                          itemCount: _nb!.cells.length,
                          itemBuilder: (ctx, i) =>
                              _buildCell(_nb!.cells[i], i + 1),
                        ),
                ),

                // 底部工具栏
                Container(
                  color: bg,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final t in [
                          ('Python', Icons.code, 'python'),
                          ('SQL', Icons.storage, 'sql'),
                          ('JS', Icons.javascript, 'javascript'),
                          ('LaTeX', Icons.functions, 'latex'),
                          ('Markdown', Icons.text_fields, 'markdown'),
                          ('R', Icons.bar_chart, 'r'),
                          ('Julia', Icons.change_history, 'julia'),
                        ])
                          _ToolBtn(
                            label: t.$1,
                            icon: t.$2,
                            onTap: () => _addCell(t.$3),
                          ),
                        _ToolBtn(
                          label: l10n.import,
                          icon: Icons.upload_file,
                          onTap: _openFileImport,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 隐藏的 WebView，承载 Pyodide/compiler.js，Python、SQL、JavaScript 都走它。
          // 挪到屏幕外而不是用 Opacity(0) 藏起来——平台视图（原生 WebView）不走
          // Flutter 自己的合成管线，Opacity/裁剪类 widget 包住它会导致触摸命中
          // 测试异常，实测表现是吞掉了下层 ListView/横向工具栏的滚动手势
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
              initialSettings: InAppWebViewSettings(
                allowsInlineMediaPlayback: true,
                mediaPlaybackRequiresUserGesture: false,
                javaScriptEnabled: true,
                allowUniversalAccessFromFileURLs: true,
                allowFileAccessFromFileURLs: true,
              ),
              onWebViewCreated: (ctrl) {
                _webCtrl = ctrl;
                // 单个持久 handler，按 cellId（第一个参数）分发给对应的 Completer，
                // 不用每次运行都注册一个新的一次性 handler
                ctrl.addJavaScriptHandler(
                  handlerName: 'onRunResult',
                  callback: (args) {
                    if (args.isEmpty) return;
                    final cellId = args[0].toString();
                    final result = args.length > 1 ? args[1].toString() : '[]';
                    _pendingRuns.remove(cellId)?.complete(result);
                  },
                );
                ctrl.addJavaScriptHandler(
                  handlerName: 'compilerReady',
                  callback: (args) async {
                    // 验证 runCode 是否真的可用
                    final test = await ctrl.evaluateJavascript(
                      source: 'typeof window.runCode',
                    );
                    debugPrint('[WebView] runCode type: $test');

                    if (!mounted) return;
                    setState(() => _webReady = true);
                    debugPrint('[Notebook] ✅ Pyodide就绪');
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCell(NotebookCell cell, int index) {
    final ctrl =
        _controllers[cell.id] ??
        (_controllers[cell.id] = TextEditingController(text: cell.code));
    final isRunning = _running[cell.id] ?? false;
    final output = _outputs[cell.id];
    final outputType = _outputTypes[cell.id];
    final hasOutput = output != null;
    final isError = outputType == 'error';
    final isSuccess = hasOutput && !isError;

    final badgeColor =
        {
          'python': _primary,
          'sql': const Color(0xFF0EA5E9),
          'javascript': const Color(0xFFF59E0B),
          'r': const Color(0xFF2563EB),
          'julia': const Color(0xFF9333EA),
          'latex': const Color(0xFFC026D3),
          'markdown': const Color(0xFF16A34A),
          'html': const Color(0xFFD97706),
        }[cell.type] ??
        _primary;

    final badgeLabel =
        {
          'python': 'Python',
          'sql': 'SQL',
          'javascript': 'JavaScript',
          'r': 'R',
          'julia': 'Julia',
          'latex': 'LaTeX',
          'markdown': 'Markdown',
          'html': 'HTML',
        }[cell.type] ??
        cell.type;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isRunning
              ? _primary
              : isError
              ? const Color(0xFFDC2626)
              : isSuccess
              ? const Color(0xFF16A34A)
              : Theme.of(context).dividerColor,
          width: isRunning ? 1.5 : 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cell头部
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: isRunning
                        ? _primary.withValues(alpha: 0.1)
                        : Theme.of(context).inputDecorationTheme.fillColor,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: isRunning
                      ? const Padding(
                          padding: EdgeInsets.all(5),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _primary,
                          ),
                        )
                      : Center(
                          child: Text(
                            '$index',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(
                                context,
                              ).textTheme.bodyLarge?.color,
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      badgeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: badgeColor,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                // 运行按钮——Notebook 运行代码是 Pro 权益（跟会员页
                // subscription_screen.dart 列出的权益一致）
                ProGate(
                  check: MembershipUtils.canRunNotebook,
                  featureName: 'Notebook 运行',
                  child: GestureDetector(
                    onTap: isRunning
                        ? null
                        : () {
                            final code = ctrl.text;
                            cell.code = code;
                            _runCell(cell);
                          },
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: _primary,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: const Icon(
                        Icons.play_arrow,
                        color: Colors.white,
                        size: 17,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // 删除按钮
                GestureDetector(
                  onTap: () => _deleteCell(cell.id),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Theme.of(context).inputDecorationTheme.fillColor,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(Icons.close, color: Colors.grey[500], size: 15),
                  ),
                ),
              ],
            ),
          ),

          // 代码输入区
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextField(
              controller: ctrl,
              readOnly: true,
              showCursor: false,
              onTap: () => _openCellEditor(cell),
              maxLines: null,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.6,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText:
                    {
                      'python': AppLocalizations.of(context)!.pythonCodeHint,
                      'sql': AppLocalizations.of(context)!.sqlQueryHint,
                      'javascript': AppLocalizations.of(context)!.jsCodeHint,
                      'r': AppLocalizations.of(context)!.rCodeHint,
                      'julia': AppLocalizations.of(context)!.juliaCodeHint,
                      'latex': AppLocalizations.of(context)!.latexFormulaHint,
                      'markdown': AppLocalizations.of(
                        context,
                      )!.markdownTextHint,
                      'html': AppLocalizations.of(context)!.htmlContentHint,
                    }[cell.type] ??
                    AppLocalizations.of(context)!.genericCodeHint,
                hintStyle: TextStyle(
                  color: Colors.grey[300],
                  fontSize: 13,
                  fontFamily: 'monospace',
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),

          // 输出区
          if (output != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(12),
                ),
                border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: _buildOutput(output, outputType),
            ),
        ],
      ),
    );
  }

  Widget _buildOutput(String output, String? type) => buildCellOutput(context, output, type);
}

// CodeMirror 6 全屏编辑页——所有 cell 打开编辑时复用这一个 widget/WebView，
// 不是每个 cell 各自常驻一个 WebView 实例。进页面时 setCode/setLanguage
// 灌入内容，每次改动通过 onContentChanged 实时同步回 cell，关闭页面时
// WebView 随路由一起销毁。语言选择器/快捷片段/键盘辅助栏只在"代码"类
// cell（python/r/julia/sql）出现——latex/markdown/html 不是这几种语言的
// 变体，没有对应的 NotebookLanguage 值，onLanguageChanged 为 null
class _CodeEditorPage extends StatefulWidget {
  final String initialCode;
  final String language;
  final String notebookTitle;
  final String? initialOutput;
  final String? initialOutputType;
  final ValueChanged<String> onContentChanged;
  final ValueChanged<NotebookLanguage>? onLanguageChanged;
  final Future<(String?, String?)> Function(String code) onRun;

  const _CodeEditorPage({
    required this.initialCode,
    required this.language,
    required this.notebookTitle,
    required this.initialOutput,
    required this.initialOutputType,
    required this.onContentChanged,
    required this.onLanguageChanged,
    required this.onRun,
  });

  @override
  State<_CodeEditorPage> createState() => _CodeEditorPageState();
}

class _CodeEditorPageState extends State<_CodeEditorPage> {
  InAppWebViewController? _webCtrl;
  bool _ready = false;
  bool _timedOut = false;
  bool _running = false;
  Timer? _timeoutTimer;
  late NotebookLanguage? _lang = notebookLanguageFromCellType(widget.language);
  late String? _output = widget.initialOutput;
  late String? _outputType = widget.initialOutputType;

  @override
  void initState() {
    super.initState();
    _armTimeout();
  }

  void _armTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 12), () {
      if (mounted && !_ready) setState(() => _timedOut = true);
    });
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  void _insert(String code) {
    _webCtrl?.evaluateJavascript(source: 'window.ins(${jsonEncode(code)})');
  }

  void _moveCursor(int dir) {
    _webCtrl?.evaluateJavascript(source: 'window.moveCursor($dir)');
  }

  void _onLanguageSelected(NotebookLanguage lang) {
    setState(() => _lang = lang);
    _webCtrl?.evaluateJavascript(
      source: 'window.setLanguage(${jsonEncode(lang.cmKey)})',
    );
    widget.onLanguageChanged?.call(lang);
  }

  Future<void> _save() async {
    final code = await _webCtrl?.evaluateJavascript(source: 'window.getCode()');
    widget.onContentChanged((code as String?) ?? '');
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已保存'), duration: Duration(seconds: 1)));
  }

  Future<void> _run() async {
    final code = await _webCtrl?.evaluateJavascript(source: 'window.getCode()');
    final codeStr = (code as String?) ?? '';
    widget.onContentChanged(codeStr);
    setState(() => _running = true);
    final (output, outputType) = await widget.onRun(codeStr);
    if (!mounted) return;
    setState(() {
      _running = false;
      _output = output;
      _outputType = outputType;
    });
  }

  Future<void> _addCell(String type) async {
    if (!mounted) return;
    Navigator.of(context).pop(type);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0A0A1A) : const Color(0xFFFAFAF8);
    final lang = _lang;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            NotebookTopBar(
              title: widget.notebookTitle,
              isRunning: _running,
              onBack: () => Navigator.pop(context),
              onSave: _save,
              onRunAll: _run,
            ),
            if (lang != null)
              LanguageSelector(current: lang, onChanged: _onLanguageSelected),
            Expanded(
              child: Stack(
                children: [
                  InAppWebView(
                    initialData: InAppWebViewInitialData(
                      data: _buildEditorHtml(isDark: isDark),
                      baseUrl: WebUri('https://dreamingpolar.com'),
                    ),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      allowUniversalAccessFromFileURLs: true,
                      allowFileAccessFromFileURLs: true,
                      allowsInlineMediaPlayback: true,
                      mediaPlaybackRequiresUserGesture: false,
                    ),
                    onWebViewCreated: (ctrl) {
                      _webCtrl = ctrl;
                      ctrl.addJavaScriptHandler(
                        handlerName: 'onContentChange',
                        callback: (args) {
                          widget.onContentChanged(
                            args.isNotEmpty ? (args[0] as String? ?? '') : '',
                          );
                          return null;
                        },
                      );
                      ctrl.addJavaScriptHandler(
                        handlerName: 'editorReady',
                        callback: (args) {
                          _timeoutTimer?.cancel();
                          if (!mounted) return null;
                          setState(() {
                            _ready = true;
                            _timedOut = false;
                          });
                          ctrl.evaluateJavascript(
                            source:
                                'window.setLanguage(${jsonEncode(lang?.cmKey ?? widget.language)})',
                          );
                          ctrl.evaluateJavascript(
                            source:
                                'window.setCode(${jsonEncode(widget.initialCode)})',
                          );
                          return null;
                        },
                      );
                    },
                  ),
                  if (!_ready)
                    Container(
                      color: bg,
                      alignment: Alignment.center,
                      child: _timedOut
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.wifi_off,
                                  color: isDark ? Colors.white38 : Colors.black26,
                                  size: 32,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  '加载较慢，请检查网络',
                                  style: TextStyle(
                                    color: isDark ? Colors.white54 : Colors.black45,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextButton(
                                  onPressed: () {
                                    setState(() => _timedOut = false);
                                    _armTimeout();
                                    _webCtrl?.reload();
                                  },
                                  child: const Text('重试'),
                                ),
                              ],
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(color: _primary),
                                const SizedBox(height: 12),
                                Text(
                                  '正在加载编辑器…',
                                  style: TextStyle(
                                    color: isDark ? Colors.white54 : Colors.black45,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                    ),
                ],
              ),
            ),
            if (_output != null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 140),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : const Color(0xFFF0FDF4),
                    border: Border(
                      top: BorderSide(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : const Color(0xFFE5E5E5),
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'OUTPUT',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: .08,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.3)
                                : const Color(0xFFAAAAAA),
                          ),
                        ),
                        const SizedBox(height: 6),
                        buildCellOutput(context, _output!, _outputType),
                      ],
                    ),
                  ),
                ),
              ),
            if (lang != null)
              SnippetBar(language: lang, onInsert: _insert),
            KeyboardToolbar(
              onInsert: _insert,
              onMoveUp: () => _moveCursor(-1),
              onMoveDown: () => _moveCursor(1),
            ),
            AddCellBar(
              onAddCode: () => _addCell(widget.language),
              onAddText: () => _addCell('markdown'),
              onAddLatex: () => _addCell('latex'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _ToolBtn({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Theme.of(context).inputDecorationTheme.fillColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: _primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
        ],
      ),
    ),
  );
}
