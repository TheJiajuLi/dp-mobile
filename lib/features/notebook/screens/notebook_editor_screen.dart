import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../publish/models/block_model.dart';
import '../../../features/auth/auth_service.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/services/pyodide_engine.dart';
import '../../../shared/utils/code_highlight.dart';
import '../../../shared/utils/pro_access.dart';
import '../../../shared/widgets/app_toast.dart';
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
  // 内核状态：有 cell 正在跑 = 运行中(橙点)，否则就绪(绿点)。顶栏状态灯用
  bool _kernelBusy = false;
  final TextEditingController _titleCtrl = TextEditingController();

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
        _controllers[cell.id] = _makeController(cell);
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

  // 全站统一的浮动圆角胶囊提示（绿勾/红叹号 + 柔和阴影），替代原来那条
  // 铺满全宽的深色 SnackBar——导出 ipynb 成功、保存、导入、内核重置等都走它。
  // 默认 ok=true（成功/中性），报错/警告场景传 ok:false
  void _showSnack(String msg, {bool ok = true}) {
    if (!mounted) return;
    showAppToast(context, msg, ok: ok);
  }

  // markdown/latex/image 走普通渲染，其余（python/sql/js/r…）都当代码看
  bool _isCodeType(String type) =>
      type != 'markdown' && type != 'latex' && type != 'image';

  // 代码类 cell 用带语法高亮的 HighlightingCodeController（跟发布页
  // block_card 一套），markdown/latex/image 用普通 controller
  TextEditingController _makeController(NotebookCell cell) =>
      _isCodeType(cell.type)
      ? HighlightingCodeController(text: cell.code, language: cell.type)
      : TextEditingController(text: cell.code);

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
    final ctrl = _makeController(cell);
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

  // 切换代码 cell 的语言（点语言 pill 弹选择器后回调）——只改类型，代码内容
  // 不动，切完清掉旧输出（换了语言旧结果就不作数了）
  void _changeCellLanguage(NotebookCell cell, String type) {
    if (cell.type == type) return;
    setState(() {
      cell.type = type;
      cell.output = null;
      cell.outputType = null;
      _outputs[cell.id] = null;
      _outputTypes[cell.id] = null;
      // 高亮控制器跟着换语言（普通字段赋值、不 notify，靠这次 setState 重绘）
      final ctrl = _controllers[cell.id];
      if (ctrl is HighlightingCodeController) ctrl.language = type;
    });
    _scheduleSave();
  }

  // 空白 cell 按 Delete 删除本 cell，并把焦点移到上一个 cell（没有上一个就
  // 不聚焦）。只剩一个空 cell 时删了就直接空，不补默认 cell——跟发布页一致
  void _deleteCellFromBackspace(int index) {
    if (_nb == null || index < 0 || index >= _nb!.cells.length) return;
    final id = _nb!.cells[index].id;
    final prevIndex = index - 1;
    _deleteCell(id);
    if (prevIndex >= 0 && prevIndex < (_nb?.cells.length ?? 0)) {
      _activateCell(prevIndex);
    }
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
    // 只有真正下内核跑的（python/sql/js）才点亮"运行中"状态灯；latex/
    // markdown 只是本地渲染，不算内核忙
    final usesKernel =
        cell.type == 'python' ||
        cell.type == 'sql' ||
        cell.type == 'javascript';
    if (usesKernel && mounted) setState(() => _kernelBusy = true);
    try {
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
    } finally {
      if (usesKernel && mounted) setState(() => _kernelBusy = false);
    }
    _scheduleSave();
  }

  Future<void> _runWithPyodide(NotebookCell cell) async {
    final l10n = AppLocalizations.of(context)!;
    final engine = ref.read(pyodideEngineProvider);

    // compiler.js 可能还没加载完（首次要拉 Pyodide）——App 启动时已经在
    // 全局预热了，正常情况下点运行时早就绪了；PyodideEngine.run() 内部
    // 自己有最多 60 秒的就绪等待兜底，这里不用再重复一遍轮询
    if (!engine.webReady) {
      _setOutput(cell, l10n.pythonEnvLoading, 'info');
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
      // pandas/matplotlib 这类重量级包 Pyodide 是首次 import 才会懒加载，
      // 冷启动经常超过引擎默认的 30 秒，这里按 Notebook 一贯的阈值传 90 秒
      final outputs = await engine.run(
        cell.id,
        effectiveCode,
        'python',
        l10n,
        timeout: const Duration(seconds: 90),
      );

      if (!mounted) return;

      String? foundOutput;
      String? foundType;
      for (final out in outputs) {
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

  // JavaScript 直接在全局共享的 Pyodide 隐藏 WebView 里 eval
  Future<void> _runJavaScript(NotebookCell cell) async {
    final l10n = AppLocalizations.of(context)!;
    if (!mounted) return;
    setState(() => _running[cell.id] = true);
    try {
      final engine = ref.read(pyodideEngineProvider);
      final outputs = await engine.runJavaScript(cell.code);
      if (outputs.isEmpty) {
        _setOutput(cell, l10n.runCompleteNoOutput, 'text');
        return;
      }
      final first = outputs.first;
      _setOutput(
        cell,
        first['content']?.toString() ?? l10n.runCompleteNoOutput,
        first['type']?.toString() ?? 'text',
      );
    } catch (e) {
      _setOutput(cell, e.toString(), 'error');
    } finally {
      if (mounted) setState(() => _running[cell.id] = false);
      _scheduleSave();
    }
  }

  Future<void> _runAll() async {
    if (_nb == null) return;
    // Notebook 编辑器是创作者自己的工作台，运行自己的代码永远不设 Pro 门禁。
    // Pro 门禁只在读者阅读【他人】文章里运行代码时才有（tutorial 阅读态）
    // 顺序执行：SQL cell 依赖前面 cell 产出的 df，并发跑会互相踩
    for (final cell in _nb!.cells) {
      await _runCell(cell);
    }
  }

  void _showResetDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? const Color(0xFF17171F) : Colors.white;
    final ink = isDark ? const Color(0xFFE0E2F0) : const Color(0xFF1A1A1A);
    final muted = isDark ? const Color(0xFF7A80A0) : const Color(0xFF888888);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).padding.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                '重置内核',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: ink,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                '重置后所有变量（df、np 等）将清空。\n需要重新运行代码才能恢复。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: muted, height: 1.6),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(
                          color: isDark
                              ? Colors.white24
                              : const Color(0xFFDDDDDD),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text('取消', style: TextStyle(color: muted)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _resetKernel();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('确认重置'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 重置内核：跑一段清空用户全局变量的 python（Pyodide 是全局共享的持久
  // 解释器，cell 之间变量互通——所以清 globals 就能"清空 df/np 等"），再把
  // 所有 cell 的输出清掉。真正的解释器重载 compiler.js 没暴露 API，这是
  // 现有黑盒能力下的最优做法
  Future<void> _resetKernel() async {
    final l10n = AppLocalizations.of(context)!;
    final engine = ref.read(pyodideEngineProvider);
    // 保留下划线开头的内部变量（含数据集注入的 _xxx_b64），清掉其余用户变量
    const clearGlobals =
        "for _k in [k for k in list(globals().keys()) if not k.startswith('_')]:\n"
        "    try:\n"
        "        del globals()[_k]\n"
        "    except Exception:\n"
        "        pass";
    setState(() => _kernelBusy = true);
    try {
      await engine.run('__reset__', clearGlobals, 'python', l10n);
    } catch (_) {
      // 清理失败也继续把输出清掉
    } finally {
      if (mounted) setState(() => _kernelBusy = false);
    }
    if (!mounted || _nb == null) return;
    setState(() {
      for (final cell in _nb!.cells) {
        cell.output = null;
        cell.outputType = null;
        _outputs[cell.id] = null;
        _outputTypes[cell.id] = null;
      }
    });
    _scheduleSave();
    _showSnack('内核已重置，变量已清空');
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
        'txt',
      ],
      // 双保险：让 picker 直接带回 bytes（部分机型/来源不给 path）
      withData: true,
    );
    if (result == null || !mounted) return;
    final file = result.files.first;
    final ext = file.extension?.toLowerCase() ?? '';
    // bytes 兜底：withData 没带回时，再按 path 直接读文件
    var bytes = file.bytes;
    if (bytes == null && file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (!mounted) return;
    if (bytes == null) {
      _showSnack('无法读取文件，请重试', ok: false);
      return;
    }

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
                    _controllers[c.id] = _makeController(c);
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
    } else if (['csv', 'xlsx', 'json', 'xml', 'txt'].contains(ext)) {
      _importDataFile(file.name, bytes, ext);
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
      final ctrl = _makeController(cell);
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

  int _cellSeq = 0;
  String _newCellId() =>
      'cell_${DateTime.now().microsecondsSinceEpoch}_${_cellSeq++}';

  // 文件名 → 合法的 python 变量名（去扩展名、非法字符转下划线、小写，
  // 数字开头补前缀）
  String _varNameFrom(String filename) {
    var v = filename
        .replaceAll(RegExp(r'\.[^.]+$'), '')
        .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')
        .toLowerCase();
    if (v.isEmpty || RegExp(r'^[0-9]').hasMatch(v)) v = 'df_$v';
    return v;
  }

  // 统一插入一批 cell 并把渲染要用的 controller/focus/output 各表补齐
  // （跟 _addCell 一样，缺了会导致 cell 渲染时取空崩），末尾定位/保存/提示
  void _insertCells(List<NotebookCell> cells, {String? snack}) {
    if (_nb == null || cells.isEmpty) return;
    setState(() {
      for (final cell in cells) {
        _nb!.cells.add(cell);
        _controllers[cell.id] = _makeController(cell);
        _focusNodes[cell.id] = FocusNode();
        _outputs[cell.id] = cell.output;
        _outputTypes[cell.id] = cell.outputType;
        _running[cell.id] = false;
      }
      _activeIndex = _nb!.cells.length - 1;
    });
    _scheduleSave();
    if (snack != null && mounted) _showSnack(snack);
  }

  // 数据文件导入——不再上传 COS 再按路径读（Pyodide 内核里没有那个文件），
  // 改成把文件内容 base64 直接注入生成的代码 cell，运行即在内核里还原成
  // 变量，后续 cell 直接用。CSV 另配一个 Markdown 表格预览 cell
  void _importDataFile(String filename, Uint8List bytes, String ext) {
    switch (ext) {
      case 'csv':
        _importCsv(bytes, filename);
      case 'xlsx':
        _importXlsx(bytes, filename);
      case 'json':
        _importJson(bytes, filename);
      default: // txt / xml
        _importText(bytes, filename);
    }
  }

  void _importCsv(Uint8List bytes, String name) {
    final b64 = base64Encode(bytes);
    final content = utf8.decode(bytes, allowMalformed: true);
    final lines = content
        .split(RegExp(r'\r?\n'))
        .where((l) => l.trim().isNotEmpty)
        .toList();
    final headerLine = lines.isNotEmpty ? lines.first : '';
    final rowCount = (lines.length - 1).clamp(0, 999999);
    final v = _varNameFrom(name);

    final codeCell = NotebookCell(
      id: _newCellId(),
      type: 'python',
      code:
          '# $name · 自动注入 · $rowCount 行\n'
          'import io, base64\n'
          'import pandas as pd\n'
          '_${v}_b64 = "$b64"\n'
          '$v = pd.read_csv(io.StringIO(base64.b64decode(_${v}_b64).decode("utf-8")))\n'
          '$v.head()',
      metadata: {'isDataset': true, 'fileName': name, 'rowCount': rowCount},
    );
    final mdCell = _buildMarkdownTable(name, headerLine, lines, rowCount);
    _insertCells([codeCell, mdCell], snack: '已导入 $name · $rowCount 行');
  }

  void _importXlsx(Uint8List bytes, String name) {
    // 没有引入 excel 解析包，直接把 xlsx 字节 base64 注入，交给内核的
    // pandas.read_excel（需 openpyxl）在运行时解析
    final b64 = base64Encode(bytes);
    final v = _varNameFrom(name);
    final cell = NotebookCell(
      id: _newCellId(),
      type: 'python',
      code:
          '# $name · 自动注入\n'
          'import io, base64\n'
          'import pandas as pd\n'
          '_${v}_b64 = "$b64"\n'
          '$v = pd.read_excel(io.BytesIO(base64.b64decode(_${v}_b64)))\n'
          '$v.head()',
      metadata: {'isDataset': true, 'fileName': name},
    );
    _insertCells([cell], snack: '已导入 $name');
  }

  void _importJson(Uint8List bytes, String name) {
    final b64 = base64Encode(bytes);
    final content = utf8.decode(bytes, allowMalformed: true);
    dynamic parsed;
    try {
      parsed = jsonDecode(content);
    } catch (_) {}
    final isArray = parsed is List;
    final v = _varNameFrom(name);

    final tail = isArray
        ? 'import pandas as pd\ndf_$v = pd.DataFrame($v)\ndf_$v.head()'
        : 'print(type($v))\n$v';
    final cell = NotebookCell(
      id: _newCellId(),
      type: 'python',
      code:
          '# $name · 自动注入\n'
          'import json, base64\n'
          '_${v}_b64 = "$b64"\n'
          '$v = json.loads(base64.b64decode(_${v}_b64).decode("utf-8"))\n'
          '$tail',
      metadata: {'isDataset': true, 'fileName': name},
    );
    _insertCells([cell], snack: '已导入 $name');
  }

  void _importText(Uint8List bytes, String name) {
    final content = utf8.decode(bytes, allowMalformed: true);
    final cell = NotebookCell(
      id: _newCellId(),
      type: 'markdown',
      code: '### 导入自 $name\n\n$content',
    );
    _insertCells([cell], snack: '已导入 $name');
  }

  // CSV 前几行渲染成 Markdown 表格预览 cell（朴素按逗号切，够预览用；真正
  // 解析在内核里由 pandas 做）
  NotebookCell _buildMarkdownTable(
    String name,
    String headerLine,
    List<String> lines,
    int rowCount,
  ) {
    List<String> splitRow(String line) =>
        line.split(',').map((c) => c.trim().replaceAll('"', '')).toList();

    final cols = splitRow(headerLine);
    final sb = StringBuffer()
      ..writeln('### 数据预览：$name')
      ..writeln()
      ..writeln('| ${cols.join(' | ')} |')
      ..writeln('| ${cols.map((_) => '---').join(' | ')} |');
    for (final line in lines.skip(1).take(10)) {
      sb.writeln('| ${splitRow(line).join(' | ')} |');
    }
    if (rowCount > 10) {
      sb
        ..writeln()
        ..writeln('_共 $rowCount 行，仅显示前 10 行_');
    }
    return NotebookCell(
      id: _newCellId(),
      type: 'markdown',
      code: sb.toString(),
    );
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
    // 有没有真的可清的输出——没有的话也给个反馈，不然点了"没反应"
    final hadOutput = _nb!.cells.any((c) => (c.output?.isNotEmpty ?? false));
    setState(() {
      for (final cell in _nb!.cells) {
        cell.output = null;
        cell.outputType = null;
        _outputs[cell.id] = null;
        _outputTypes[cell.id] = null;
      }
    });
    _scheduleSave();
    _showSnack(hadOutput ? '已清空所有输出' : '没有可清空的输出');
  }

  // 顶栏 ⋯ 更多菜单——从系统默认的白色 PopupMenu 换成全站统一的底部弹层
  // （抓手 + 图标方框 + 主/副标题行），跟确认弹层/创作操作弹层同一套语言
  void _showMoreMenu() {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? const Color(0xFF17171F) : Colors.white;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              _moreItem(
                ctx: ctx,
                icon: Icons.download_outlined,
                iconColor: const Color(0xFF6366F1),
                label: l10n.exportIpynb,
                sub: '保存为 Jupyter Notebook 文件',
                onTap: () {
                  Navigator.pop(ctx);
                  _exportIpynb();
                },
              ),
              _moreItem(
                ctx: ctx,
                icon: Icons.cleaning_services_outlined,
                iconColor: const Color(0xFFD97706),
                label: l10n.clearOutputs,
                sub: '移除所有单元格的运行结果',
                onTap: () {
                  Navigator.pop(ctx);
                  _clearOutputs();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _moreItem({
    required BuildContext ctx,
    required IconData icon,
    required Color iconColor,
    required String label,
    required String sub,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    final ink = isDark ? const Color(0xFFF0F2F8) : const Color(0xFF1A1A1A);
    final muted = isDark ? const Color(0xFF7A80A0) : const Color(0xFF888888);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: isDark ? 0.20 : 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 21),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(sub, style: TextStyle(fontSize: 12, color: muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
    // 一键发布为文章是 Pro 权益
    if (!requirePro(context, ref, feature: '一键发布为文章')) return;
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
      _showSnack('Notebook 是空的，没有可发布的内容', ok: false);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 浅色统一首页米白 #FAFAF8（不再偏冷的 #F7F7FB）；深色不变。顶栏/画布/
    // 底部工具栏都用这个 bg，保持一整块不出接缝
    final bg = isDark
        ? Theme.of(context).scaffoldBackgroundColor
        : const Color(0xFFFAFAF8);
    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          // 右下角一团很淡的品牌紫光晕——跟 Notebook 首页 Hero 卡同一个
          // 紫色语言，但这里是浅色语境下的氛围点缀，不是首页那种深色渐变
          // 卡片，alpha 压得很低，卡片间的缝隙、底部工具栏周围若隐若现就够。
          // 放右下角而不是顶部——顶栏底色不透明会直接把光晕挡住
          Positioned(
            right: -80,
            bottom: -60,
            child: IgnorePointer(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _primary.withValues(alpha: isDark ? 0.10 : 0.07),
                      _primary.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
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
                        // 标题(Expanded)和按钮组之间留一段间距——否则标题末字会
                        // 紧贴「全部运行」胶囊、被圆角盖住，看着像被遮挡
                        const SizedBox(width: 10),
                        // 内核状态灯：就绪(绿)/运行中(橙)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _kernelBusy
                                ? const Color(0xFFD97706)
                                : const Color(0xFF16A34A),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _kernelBusy ? '运行中' : '就绪',
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark
                                ? const Color(0xFF7A80A0)
                                : const Color(0xFF999999),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // 重置内核（图标按钮）
                        GestureDetector(
                          onTap: _showResetDialog,
                          behavior: HitTestBehavior.opaque,
                          child: Tooltip(
                            message: '重置内核',
                            child: Padding(
                              padding: const EdgeInsets.all(5),
                              child: Icon(
                                Icons.refresh,
                                size: 17,
                                color: isDark
                                    ? const Color(0xFF7A80A0)
                                    : const Color(0xFF888888),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        // 运行全部：淡紫底纯图标钮（省顶栏横向空间）
                        _topBarChip(
                          isDark: isDark,
                          label: l10n.runAll,
                          icon: Icons.play_arrow_rounded,
                          onTap: _runAll,
                          accent: true,
                          iconOnly: true,
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
                        // 一键发布为文章——跟「全部运行」同款淡紫底紫字胶囊
                        _topBarChip(
                          isDark: isDark,
                          label: l10n.publish,
                          icon: Icons.ios_share,
                          onTap: _publishAsArticle,
                          accent: true,
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.more_vert,
                            color: Colors.grey[600],
                            size: 20,
                          ),
                          onPressed: _showMoreMenu,
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
                            // 默认拖拽会把 cell 裹进一层矩形高亮 Material（灰底+
                            // 阴影），露在卡片圆角之外，就是那圈"灰色 box"。用
                            // 透明、零高度的 proxy 代替，拖起来跟静态卡片一模一样
                            proxyDecorator: (child, index, animation) =>
                                Material(
                                  color: Colors.transparent,
                                  elevation: 0,
                                  child: child,
                                ),
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
                    onImport: _openFileImport,
                  ),
                ],
              ),
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
        (_controllers[cell.id] = _makeController(cell));
    final focus = _focusNodes[cell.id] ?? (_focusNodes[cell.id] = FocusNode());
    return NotebookCellCard(
      // ReorderableListView 要求每个直接子级都带 key（否则断言崩溃）——
      // 用 cell.id 保证拖拽重排/增删时身份稳定
      key: ValueKey(cell.id),
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
        // 自己在编辑器里运行自己的代码，永远不拦 Pro（门禁只在读者阅读态）
        cell.code = ctrl.text;
        _runCell(cell);
      },
      onAddBelow: (type) => _addCell(type, at: index + 1),
      onDelete: () => _deleteCell(cell.id),
      onChangeLanguage: (type) => _changeCellLanguage(cell, type),
      onEmptyBackspace: () => _deleteCellFromBackspace(index),
    );
  }

  // 顶栏按钮——保存是中性灰底，运行全部换成淡紫底+紫字（accent:true），
  // 跟发布按钮的实心紫呼应但更轻，三个按钮形成"灰→浅紫→实紫"的层级
  Widget _topBarChip({
    required bool isDark,
    required String label,
    IconData? icon,
    required VoidCallback onTap,
    bool accent = false,
    // 纯图标模式：不显示文字，收成方形图标钮（用 label 作 Tooltip 做无障碍）
    bool iconOnly = false,
  }) {
    final fg = accent
        ? _primary
        : (isDark ? const Color(0xFF7A80A0) : const Color(0xFF555555));
    final bg = accent
        ? _primary.withValues(alpha: isDark ? 0.16 : 0.1)
        : (isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFF0F0F0));
    final border = accent || isDark
        ? null
        : Border.all(color: const Color(0xFFE5E5E5), width: 0.5);

    if (iconOnly && icon != null) {
      return Tooltip(
        message: label,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              border: border,
            ),
            child: Icon(icon, size: 19, color: fg),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: border,
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: fg,
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
      _controllers[cell.id] = _makeController(cell);
      _focusNodes[cell.id] = FocusNode();
      _outputs[cell.id] = b64;
      _outputTypes[cell.id] = 'image';
      _running[cell.id] = false;
      _activeIndex = _nb!.cells.length - 1;
    });
    _scheduleSave();
  }
}
