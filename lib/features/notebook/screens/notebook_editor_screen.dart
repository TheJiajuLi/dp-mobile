import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/network/api_client.dart';
import '../../publish/models/block_model.dart';
import '../../../features/auth/auth_service.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../models/notebook_model.dart';
import '../services/notebook_service.dart';
import '../widgets/notebook_add_divider.dart';
import '../widgets/notebook_bottom_toolbar.dart';
import '../widgets/notebook_cell_card.dart';

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
  // 原地编辑：每个 cell 一个 FocusNode（按 cell.id），_activeIndex 记当前
  // 选中的 cell 下标（-1=无）。标题也可直接改，单独一个 controller
  final Map<String, FocusNode> _focusNodes = {};
  int _activeIndex = -1;
  final TextEditingController _titleCtrl = TextEditingController();

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
        _focusNodes[cell.id] = FocusNode();
        _outputs[cell.id] = cell.output;
        _outputTypes[cell.id] = cell.outputType;
        _running[cell.id] = false;
      }
      _titleCtrl.text = nb.name;
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

  // at 为 null=追加到末尾；否则插到该下标。新建后自动选中并聚焦，直接原地
  // 编辑（不再跳页）
  void _addCell(String type, {int? at}) {
    if (_nb == null) return;
    final cell = NotebookCell(
      id: 'cell_${DateTime.now().millisecondsSinceEpoch}',
      type: type,
      code: '',
    );
    final ctrl = TextEditingController();
    final focus = FocusNode();
    final index = at ?? _nb!.cells.length;
    setState(() {
      _nb!.cells.insert(index, cell);
      _controllers[cell.id] = ctrl;
      _focusNodes[cell.id] = focus;
      _outputs[cell.id] = null;
      _outputTypes[cell.id] = null;
      _running[cell.id] = false;
      _activeIndex = index;
    });
    _scheduleSave();
    // markdown/latex 是渲染态，新建时直接进编辑态才好打字；代码类也聚焦
    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted) focus.requestFocus();
    });
  }

  void _deleteCell(String cellId) {
    if (_nb == null) return;
    _controllers[cellId]?.dispose();
    _controllers.remove(cellId);
    _focusNodes[cellId]?.dispose();
    _focusNodes.remove(cellId);
    _outputs.remove(cellId);
    _outputTypes.remove(cellId);
    _running.remove(cellId);
    setState(() {
      _nb!.cells.removeWhere((c) => c.id == cellId);
      _activeIndex = -1;
    });
    _scheduleSave();
  }

  // 拖拽重排——ReorderableListView 回调，同步 cell 顺序并保存
  void _onReorder(int oldIndex, int newIndex) {
    if (_nb == null) return;
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final cell = _nb!.cells.removeAt(oldIndex);
      _nb!.cells.insert(newIndex, cell);
      _activeIndex = newIndex;
    });
    _scheduleSave();
  }

  // 选中并聚焦某个 cell——原地编辑的入口，替代原来的跳页
  void _activateCell(int index) {
    if (index < 0 || index >= (_nb?.cells.length ?? 0)) return;
    final id = _nb!.cells[index].id;
    setState(() => _activeIndex = index);
    Future.delayed(const Duration(milliseconds: 60), () {
      if (mounted) _focusNodes[id]?.requestFocus();
    });
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
    for (final f in _focusNodes.values) {
      f.dispose();
    }
    _titleCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // 一键发布为文章——把每个 cell 映射成文章 block，带进发布页（新文章）。
  // markdown→text / latex→latex / 其它(python/sql/js/r/julia/html)→code；
  // 文字输出挂到 code block 的 outputContent，图片输出额外出一个 image
  // block，error 输出不带
  void _publishAsArticle() {
    final nb = _nb;
    if (nb == null) return;
    final blocks = <EditorBlock>[];
    var idc = 0;
    String nid() => 'nb${++idc}_${DateTime.now().microsecondsSinceEpoch}';

    for (final cell in nb.cells) {
      final code = cell.code.trim();
      if (cell.type == 'markdown') {
        if (code.isNotEmpty) {
          blocks.add(
            EditorBlock(id: nid(), type: BlockType.text, content: code),
          );
        }
        continue;
      }
      if (cell.type == 'latex') {
        if (code.isNotEmpty) {
          blocks.add(
            EditorBlock(id: nid(), type: BlockType.latex, content: code),
          );
        }
        continue;
      }
      // 代码 cell
      if (code.isNotEmpty) {
        final runnable =
            cell.type == 'python' ||
            cell.type == 'javascript' ||
            cell.type == 'sql';
        final out = cell.output?.trim() ?? '';
        final hasTextOut =
            out.isNotEmpty &&
            cell.outputType != 'error' &&
            cell.outputType != 'image';
        blocks.add(
          EditorBlock(
            id: nid(),
            type: BlockType.code,
            content: code,
            language: cell.type,
            isExecutable: runnable,
            outputContent: hasTextOut ? cell.output : null,
            outputType: hasTextOut ? cell.outputType : null,
          ),
        );
      }
      // 图片输出 → 额外一个 image block
      if (cell.outputType == 'image' &&
          (cell.output?.trim().isNotEmpty ?? false)) {
        blocks.add(
          EditorBlock(
            id: nid(),
            type: BlockType.image,
            imageUrl: cell.output,
            content: cell.output!,
          ),
        );
      }
    }

    if (blocks.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Notebook 是空的，没有可发布的内容')));
      return;
    }
    context.push('/publish', extra: {'title': nb.name, 'blocks': blocks});
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          // 点空白处收起键盘——之前只包在 Cell 画布(ReorderableListView)
          // 外面一层，ReorderableListView 内部为拖拽排序自带一套手势识别，
          // 会在"空白但仍在列表边界内"的区域抢先吃掉tap，不冒泡到外层。
          // 挪到这里包住整个SafeArea（顶栏+画布+底部工具栏一起），跟其它
          // 17个页面统一用的"包住整页内容"写法一致，不再单独依赖
          // ReorderableListView 自己的手势透传行为
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              FocusScope.of(context).unfocus();
              if (_activeIndex != -1) {
                setState(() => _activeIndex = -1);
              }
            },
            child: SafeArea(
              child: Column(
                children: [
                  // 顶部栏
                  Container(
                    decoration: BoxDecoration(
                      color: bg,
                      border: Border(
                        bottom: BorderSide(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.04)
                              : const Color(0xFFEBEBEB),
                          width: 0.5,
                        ),
                      ),
                    ),
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
                          behavior: HitTestBehavior.opaque,
                          child: Icon(
                            Icons.arrow_back_ios,
                            size: 18,
                            color: isDark
                                ? const Color(0xFF7A80A0)
                                : const Color(0xFF888888),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 标题可直接点击编辑
                        Expanded(
                          child: TextField(
                            controller: _titleCtrl,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? const Color(0xFFE0E2F0)
                                  : const Color(0xFF1A1A1A),
                            ),
                            maxLines: 1,
                            textInputAction: TextInputAction.done,
                            decoration: const InputDecoration.collapsed(
                              hintText: '未命名 Notebook',
                            ),
                            onChanged: (v) {
                              if (_nb != null) {
                                _nb!.name = v;
                                _scheduleSave();
                              }
                            },
                          ),
                        ),
                        // 运行全部：中性灰底
                        _topBarChip(
                          isDark: isDark,
                          label: l10n.runAll,
                          icon: Icons.play_arrow,
                          onTap: _runAll,
                        ),
                        const SizedBox(width: 6),
                        // 保存：同款灰底
                        _topBarChip(
                          isDark: isDark,
                          label: l10n.save,
                          onTap: () {
                            if (_nb != null) _svc!.save(_nb!);
                            _showSnack(l10n.saved);
                          },
                        ),
                        const SizedBox(width: 6),
                        // 一键发布为文章——品牌紫底白字（跟极索「问问小梦」按钮一套）
                        GestureDetector(
                          onTap: _publishAsArticle,
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
                                  Icons.ios_share,
                                  color: Colors.white,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  l10n.publish,
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

                  // Cell 画布——单一滚动、原地编辑，支持拖拽重排；末尾挂一个
                  // 「添加内容块」按钮
                  Expanded(
                    child: _nb == null
                        ? const Center(child: CircularProgressIndicator())
                        : ReorderableListView(
                            scrollController: _scrollCtrl,
                            buildDefaultDragHandles: false,
                            padding: const EdgeInsets.fromLTRB(6, 8, 6, 4),
                            onReorder: _onReorder,
                            footer: NotebookAddDivider(
                              isDark: isDark,
                              onTap: () => _addCell('markdown'),
                            ),
                            children: [
                              for (int i = 0; i < _nb!.cells.length; i++)
                                _buildCellCard(_nb!.cells[i], i),
                            ],
                          ),
                  ),

                  // 底部浮动工具栏
                  NotebookBottomToolbar(
                    isDark: isDark,
                    activeType: _getActiveToolType(),
                    onTap: _onToolbarTap,
                  ),
                ],
              ),
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

  // 单张 Cell 卡片——把状态（controller/focusNode/output/isActive等）
  // 打包成 NotebookCellCard 的参数，具体渲染搬到
  // widgets/notebook_cell_card.dart，这里只做"取状态→传参数→接回调"
  Widget _buildCellCard(NotebookCell cell, int index) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ctrl =
        _controllers[cell.id] ??
        (_controllers[cell.id] = TextEditingController(text: cell.code));
    final focus = _focusNodes[cell.id] ?? (_focusNodes[cell.id] = FocusNode());
    return NotebookCellCard(
      cell: cell,
      index: index,
      isActive: _activeIndex == index,
      isDark: isDark,
      isRunning: _running[cell.id] ?? false,
      controller: ctrl,
      focusNode: focus,
      output: _outputs[cell.id],
      outputType: _outputTypes[cell.id],
      onActivate: () => _activateCell(index),
      onChanged: (v) {
        cell.code = v;
        _scheduleSave();
      },
      onRun: () {
        cell.code = ctrl.text;
        _runCell(cell);
      },
      onAddBelow: (type) => _addCell(type, at: index + 1),
      onDelete: () => _deleteCell(cell.id),
    );
  }

  // 顶栏中性灰底按钮（运行全部/保存）
  Widget _topBarChip({
    required bool isDark,
    required String label,
    IconData? icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFF0F0F0),
          borderRadius: BorderRadius.circular(8),
          border: isDark
              ? null
              : Border.all(color: const Color(0xFFE5E5E5), width: 0.5),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: isDark
                    ? const Color(0xFF7A80A0)
                    : const Color(0xFF555555),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? const Color(0xFF7A80A0)
                    : const Color(0xFF555555),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 底部浮动工具栏当前该高亮哪个类型——按 _activeIndex 对应 cell 的类型算，
  // 依赖 State 字段，留在主文件；具体渲染在 NotebookBottomToolbar
  String? _getActiveToolType() {
    if (_activeIndex < 0 || _activeIndex >= (_nb?.cells.length ?? 0)) {
      return null;
    }
    final t = _nb!.cells[_activeIndex].type;
    return switch (t) {
      'markdown' => 'markdown',
      'latex' => 'latex',
      'sql' => 'sql',
      'image' => 'image',
      'python' || 'javascript' || 'r' || 'julia' || 'html' => 'python',
      _ => null,
    };
  }

  void _onToolbarTap(String type) {
    switch (type) {
      case 'image':
        _addImageCell();
        break;
      case 'more':
        showMoreLanguagesSheet(
          context,
          onPick: _addCell,
          onImport: _openFileImport,
        );
        break;
      default:
        _addCell(type);
    }
  }

  // 图片块：从相册选图，base64 存进 cell.output（outputType=image）
  Future<void> _addImageCell() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null || _nb == null) return;
    final bytes = await picked.readAsBytes();
    final b64 = base64Encode(bytes);
    final cell = NotebookCell(
      id: 'cell_${DateTime.now().millisecondsSinceEpoch}',
      type: 'image',
      code: '',
      output: b64,
      outputType: 'image',
    );
    setState(() {
      _nb!.cells.add(cell);
      _controllers[cell.id] = TextEditingController();
      _focusNodes[cell.id] = FocusNode();
      _outputs[cell.id] = b64;
      _outputTypes[cell.id] = 'image';
      _running[cell.id] = false;
      _activeIndex = _nb!.cells.length - 1;
    });
    _scheduleSave();
  }
}
