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
import '../../../features/auth/auth_service.dart';
import '../models/notebook_model.dart';
import '../services/notebook_service.dart';

const _primary = Color(0xFF6366F1);

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

  // 复用 Web 端已有的 compiler.js（Pyodide 基础设施），不重新造轮子
  static const _compilerHtml = '''
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
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
      content: e.message
    }]);
  }
};

window.flutter_inappwebview.callHandler('compilerReady');
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
      setState(() { _nb = nb; });
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

  // 统一更新单个 cell 的输出：同步进内存态 map（驱动 UI）和 cell 字段（用于持久化）
  void _setOutput(NotebookCell cell, String? output, String? outputType) {
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
      type: type, code: '');
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
      _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
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
  String _wrapSql(String sql) => '''
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
        _setOutput(cell, '⏳ ${cell.type.toUpperCase()} 支持即将上线', 'info');
        break;
      default:
        _setOutput(cell, '暂不支持该类型的运行', 'info');
    }
    _scheduleSave();
  }

  Future<void> _runWithPyodide(NotebookCell cell) async {
    if (_webCtrl == null) {
      _showSnack('运行环境初始化中，请稍候...');
      return;
    }

    // compiler.js 可能还没加载完（首次要拉 Pyodide），耐心等最多 30 秒，
    // 而不是直接判失败——这是之前"运行完成（无输出）"的根因之一
    if (!_webReady) {
      _setOutput(cell, '⏳ Python 环境加载中，请稍候...', 'info');
      var waited = 0;
      while (!_webReady && waited < 30) {
        await Future.delayed(const Duration(seconds: 1));
        waited++;
      }
      if (!mounted) return;
      if (!_webReady) {
        _setOutput(cell, '❌ Python 环境加载超时，请重试', 'error');
        return;
      }
    }

    setState(() => _running[cell.id] = true);

    final isSql = cell.type == 'sql';
    final effectiveCode = isSql ? _wrapSql(cell.code) : cell.code;

    try {
      // jsonEncode 生成一个能安全塞进 JS 的字符串字面量，比手写转义链靠谱
      final rawResult = await _webCtrl!.evaluateJavascript(
        source: '''
(async function() {
  try {
    if (typeof window.runCode !== 'function') {
      return JSON.stringify([{
        type: 'error',
        content: 'compiler未就绪，请重试'
      }]);
    }
    const result = await window.runCode(
      ${jsonEncode(effectiveCode)},
      "python"
    );
    return result;
  } catch(e) {
    return JSON.stringify([{
      type: 'error',
      content: e.message || String(e)
    }]);
  }
})()
''',
      );

      if (rawResult == null || rawResult.toString().trim() == 'null') {
        _setOutput(cell, '运行完成（无输出）', 'text');
        return;
      }

      var resultStr = rawResult.toString();
      // 有的平台会把字符串结果再包一层引号，先剥掉
      if (resultStr.startsWith('"') && resultStr.endsWith('"')) {
        resultStr = jsonDecode(resultStr) as String;
      }

      try {
        final outputs = jsonDecode(resultStr) as List;
        String? foundOutput;
        String? foundType;
        for (final out in outputs) {
          final type = out['type'] as String? ?? 'text';
          final content = out['content'] as String? ?? '';
          // 跳过调试信息
          if (['viz-suggestion', 'missing-package', 'debug'].contains(type)) {
            continue;
          }
          foundOutput = content;
          foundType = type;
          break;
        }
        _setOutput(cell, foundOutput ?? '运行完成（无输出）', foundType ?? 'text');
      } catch (_) {
        // 不是合法 JSON，当纯文本输出，好过直接吞掉
        _setOutput(cell, resultStr, 'text');
      }
    } catch (e) {
      _setOutput(cell, '执行出错：$e', 'error');
    } finally {
      setState(() => _running[cell.id] = false);
      _scheduleSave();
    }
  }

  // JavaScript 直接在承载 Pyodide 的隐藏 WebView 里 eval
  Future<void> _runJavaScript(NotebookCell cell) async {
    if (_webCtrl == null) {
      _showSnack('运行环境初始化中，请稍候...');
      return;
    }
    setState(() => _running[cell.id] = true);
    try {
      // 捕获 console.log 输出，返回值统一走 JSON.stringify，避免不同平台
      // evaluateJavascript 对返回对象的处理不一致
      final wrappedCode = '''
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
        _setOutput(cell, '运行完成（无输出）', 'text');
        return;
      }
      final map = jsonDecode(result.toString()) as Map;
      if (map['ok'] == true) {
        _setOutput(cell, (map['output'] as String?) ?? '运行完成（无输出）', 'text');
      } else {
        _setOutput(cell, map['error']?.toString() ?? '未知错误', 'error');
      }
    } catch (e) {
      _setOutput(cell, e.toString(), 'error');
    } finally {
      setState(() => _running[cell.id] = false);
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
        'ipynb', 'py', 'r', 'sql', 'md', 'tex',
        'csv', 'xlsx', 'json', 'xml',
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
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('导入 Jupyter Notebook'),
          content: Text('发现 ${imported.cells.length} 个 cell，是否导入？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary),
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
              child: const Text('导入', style: TextStyle(color: Colors.white))),
          ],
        ),
      );
    } else if (['csv', 'xlsx', 'json', 'xml'].contains(ext)) {
      await _importDataFile(file.name, bytes, ext);
    } else {
      final content = utf8.decode(bytes);
      final langMap = {
        'py': 'python', 'r': 'r',
        'sql': 'sql', 'md': 'markdown', 'tex': 'latex',
      };
      final lang = langMap[ext] ?? 'python';

      if (_nb == null) return;
      final cell = NotebookCell(
        id: 'cell_${DateTime.now().millisecondsSinceEpoch}',
        type: lang, code: content);
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
  Future<void> _importDataFile(String filename, Uint8List bytes, String ext) async {
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: filename,
          contentType: DioMediaType('application', ext),
        ),
      });

      final api = ref.read(apiClientProvider);
      final res = await api.post('/auth/files/upload', data: formData);
      if (!res.success) {
        _showSnack('上传失败：${res.message}');
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
        type: 'python', code: importCode);
      final ctrl = TextEditingController(text: importCode);
      setState(() {
        _nb!.cells.add(cell);
        _controllers[cell.id] = ctrl;
        _outputs[cell.id] = null;
        _outputTypes[cell.id] = null;
        _running[cell.id] = false;
      });
      _scheduleSave();

      _showSnack('$filename 已导入，点击运行加载数据');
    } catch (e) {
      _showSnack('上传失败：$e');
    }
  }

  Future<void> _exportIpynb() async {
    if (_nb == null) return;
    final ipynb = NotebookService.toIpynb(_nb!);
    final path = await FilePicker.platform.saveFile(
      fileName: '${_nb!.name}.ipynb',
      bytes: Uint8List.fromList(utf8.encode(ipynb)),
    );
    if (path != null) _showSnack('已导出到 $path');
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      body: Stack(children: [
        SafeArea(child: Column(children: [
          // 顶部栏
          Container(color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              GestureDetector(
                onTap: () {
                  if (_nb != null) _svc!.save(_nb!);
                  Navigator.pop(context);
                },
                child: const Row(children: [
                  Icon(Icons.arrow_back_ios, size: 16, color: _primary),
                  Text('返回', style: TextStyle(fontSize: 13, color: _primary)),
                ])),
              const SizedBox(width: 8),
              Expanded(child: Text(_nb?.name ?? 'Notebook',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
              GestureDetector(
                onTap: _runAll,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: _primary,
                    borderRadius: BorderRadius.circular(8)),
                  child: const Row(children: [
                    Icon(Icons.play_arrow, color: Colors.white, size: 15),
                    SizedBox(width: 4),
                    Text('全部运行', style: TextStyle(fontSize: 12,
                      color: Colors.white, fontWeight: FontWeight.w600)),
                  ]))),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: Colors.grey[600], size: 20),
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'export',
                    child: Row(children: [
                      Icon(Icons.download, size: 18),
                      SizedBox(width: 8),
                      Text('导出 .ipynb'),
                    ])),
                  const PopupMenuItem(
                    value: 'clear',
                    child: Row(children: [
                      Icon(Icons.delete_outline, size: 18),
                      SizedBox(width: 8),
                      Text('清空输出'),
                    ])),
                ],
                onSelected: (value) {
                  if (value == 'export') {
                    _exportIpynb();
                  } else if (value == 'clear') {
                    _clearOutputs();
                  }
                },
              ),
            ])),

          // Cell列表
          Expanded(child: _nb == null
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(12),
              itemCount: _nb!.cells.length,
              itemBuilder: (ctx, i) => _buildCell(_nb!.cells[i], i + 1))),

          // 底部工具栏
          Container(color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final t in [
                  ('Python', Icons.code, 'python'),
                  ('SQL', Icons.storage, 'sql'),
                  ('JS', Icons.javascript, 'javascript'),
                  ('LaTeX', Icons.functions, 'latex'),
                  ('Markdown', Icons.text_fields, 'markdown'),
                  ('R', Icons.bar_chart, 'r'),
                  ('Julia', Icons.change_history, 'julia'),
                ]) _ToolBtn(
                  label: t.$1, icon: t.$2,
                  onTap: () => _addCell(t.$3)),
                _ToolBtn(label: '导入', icon: Icons.upload_file, onTap: _openFileImport),
              ]))),
        ])),

        // 隐藏的 WebView，承载 Pyodide/compiler.js，Python、SQL、JavaScript 都走它。
        // 挪到屏幕外而不是用 Opacity(0) 藏起来——平台视图（原生 WebView）不走
        // Flutter 自己的合成管线，Opacity/裁剪类 widget 包住它会导致触摸命中
        // 测试异常，实测表现是吞掉了下层 ListView/横向工具栏的滚动手势
        Positioned(
          left: -9999, top: -9999, width: 1, height: 1,
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
              ctrl.addJavaScriptHandler(
                handlerName: 'compilerReady',
                callback: (args) {
                  setState(() => _webReady = true);
                  debugPrint('[Notebook] Pyodide编译器就绪');
                },
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _buildCell(NotebookCell cell, int index) {
    final ctrl = _controllers[cell.id] ??
      (_controllers[cell.id] = TextEditingController(text: cell.code));
    final isRunning = _running[cell.id] ?? false;
    final output = _outputs[cell.id];
    final outputType = _outputTypes[cell.id];
    final hasOutput = output != null;
    final isError = outputType == 'error';
    final isSuccess = hasOutput && !isError;

    final badgeColor = {
      'python': _primary,
      'sql': const Color(0xFF0EA5E9),
      'javascript': const Color(0xFFF59E0B),
      'r': const Color(0xFF2563EB),
      'julia': const Color(0xFF9333EA),
      'latex': const Color(0xFFC026D3),
      'markdown': const Color(0xFF16A34A),
      'html': const Color(0xFFD97706),
    }[cell.type] ?? _primary;

    final badgeLabel = {
      'python': 'Python',
      'sql': 'SQL',
      'javascript': 'JavaScript',
      'r': 'R',
      'julia': 'Julia',
      'latex': 'LaTeX',
      'markdown': 'Markdown',
      'html': 'HTML',
    }[cell.type] ?? cell.type;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isRunning ? _primary
            : isError ? const Color(0xFFDC2626)
            : isSuccess ? const Color(0xFF16A34A)
            : Colors.grey.shade200,
          width: isRunning ? 1.5 : 0.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Cell头部
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
          child: Row(children: [
            Container(width: 24, height: 24,
              decoration: BoxDecoration(
                color: isRunning ? _primary.withValues(alpha: 0.1) : Colors.grey[200],
                borderRadius: BorderRadius.circular(5)),
              child: isRunning
                ? const Padding(padding: EdgeInsets.all(5),
                    child: CircularProgressIndicator(strokeWidth: 2, color: _primary))
                : Center(child: Text('$index',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)))),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(5)),
              child: Text(badgeLabel,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                  color: badgeColor))),
            const Spacer(),
            // 运行按钮
            GestureDetector(
              onTap: isRunning ? null : () {
                final code = ctrl.text;
                cell.code = code;
                _runCell(cell);
              },
              child: Container(width: 30, height: 30,
                decoration: BoxDecoration(color: _primary,
                  borderRadius: BorderRadius.circular(7)),
                child: const Icon(Icons.play_arrow, color: Colors.white, size: 17))),
            const SizedBox(width: 6),
            // 删除按钮
            GestureDetector(
              onTap: () => _deleteCell(cell.id),
              child: Container(width: 30, height: 30,
                decoration: BoxDecoration(color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(7)),
                child: Icon(Icons.close, color: Colors.grey[500], size: 15))),
          ])),

        // 代码输入区
        Padding(
          padding: const EdgeInsets.all(10),
          child: TextField(
            controller: ctrl,
            onChanged: (val) {
              cell.code = val;
              _scheduleSave();
            },
            maxLines: null,
            style: const TextStyle(
              fontFamily: 'monospace', fontSize: 13, height: 1.6,
              color: Color(0xFF1C1C1E)),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: {
                'python': '# Python 代码...',
                'sql': '-- SQL 查询...',
                'javascript': '// JavaScript 代码...',
                'r': '# R 代码...',
                'julia': '# Julia 代码...',
                'latex': r'输入 LaTeX 公式...',
                'markdown': '# Markdown 文本...',
                'html': '<p>HTML 内容...</p>',
              }[cell.type] ?? '代码...',
              hintStyle: TextStyle(color: Colors.grey[300],
                fontSize: 13, fontFamily: 'monospace'),
              contentPadding: EdgeInsets.zero),
          )),

        // 输出区
        if (output != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F8F8),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(12)),
              border: Border(top: BorderSide(color: Colors.grey.shade100))),
            child: _buildOutput(output, outputType)),
      ]));
  }

  Widget _buildOutput(String output, String? type) {
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
            onErrorFallback: (err) => Text(output,
              style: const TextStyle(color: Colors.red, fontSize: 12)),
          ));
      case 'markdown':
        return MarkdownBody(data: output);
      case 'info':
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7E6),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(output,
            style: const TextStyle(fontSize: 13, color: Color(0xFFD97706))));
      case 'error':
        return Container(
          padding: const EdgeInsets.only(left: 8),
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(
              color: Color(0xFFFCA5A5), width: 2))),
          child: SelectableText(output,
            style: const TextStyle(fontFamily: 'monospace',
              fontSize: 12, color: Color(0xFFDC2626), height: 1.5)));
      case 'image':
        try {
          final base64Data = output.contains(',') ? output.split(',').last : output;
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(base64Decode(base64Data), fit: BoxFit.contain));
        } catch (e) {
          return Text('图表渲染失败：$e', style: const TextStyle(color: Colors.red));
        }
      case 'html':
        return SizedBox(
          height: 200,
          child: InAppWebView(
            initialData: InAppWebViewInitialData(
              data: '''
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
        return SelectableText(output,
          style: const TextStyle(fontFamily: 'monospace',
            fontSize: 12, height: 1.6, color: Color(0xFF1C1C1E)));
    }
  }
}

class _ToolBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _ToolBtn({required this.label, required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200)),
      child: Row(children: [
        Icon(icon, size: 14, color: _primary),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12,
          fontWeight: FontWeight.w500, color: Color(0xFF1C1C1E))),
      ])));
}
