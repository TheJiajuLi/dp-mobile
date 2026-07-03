import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:file_picker/file_picker.dart';
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
  final ScrollController _scrollCtrl = ScrollController();

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
      }
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), () {
      if (_nb != null) _svc!.save(_nb!);
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
    setState(() => _nb!.cells.removeWhere((c) => c.id == cellId));
    _scheduleSave();
  }

  // LaTeX cell：点运行就渲染
  void _runLatexCell(NotebookCell cell) {
    final code = _controllers[cell.id]?.text ?? cell.code;
    setState(() {
      cell.code = code;
      cell.output = code;
      cell.outputType = 'latex';
    });
    _scheduleSave();
  }

  // Python/R cell：目前显示提示，后续接 WebView
  void _runCodeCell(NotebookCell cell) {
    setState(() {
      cell.isRunning = true;
    });
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          cell.isRunning = false;
          cell.output = '▶ Python 运行环境加载中，请稍候...\n（完整运行支持将在下个版本上线）';
          cell.outputType = 'text';
        });
      }
    });
    _scheduleSave();
  }

  void _runAll() {
    if (_nb == null) return;
    for (final cell in _nb!.cells) {
      if (cell.type == 'latex') {
        _runLatexCell(cell);
      } else {
        _runCodeCell(cell);
      }
    }
  }

  Future<void> _importFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx', 'json', 'py', 'ipynb', 'tex', 'md', 'html'],
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final ext = file.extension ?? '';
    final name = file.name;

    // 根据文件类型插入对应 cell
    String code = '';
    String type = 'python';
    if (['csv', 'xlsx'].contains(ext)) {
      code = 'import pandas as pd\ndf = pd.read_csv("$name")\nprint(df.shape)\ndf.head()';
      type = 'python';
    } else if (ext == 'json') {
      code = 'import json\nwith open("$name") as f:\n    data = json.load(f)\nprint(data)';
      type = 'python';
    } else if (ext == 'tex') {
      code = file.bytes != null ? utf8.decode(file.bytes!) : '';
      type = 'latex';
    } else if (ext == 'py') {
      code = file.bytes != null ? utf8.decode(file.bytes!) : '';
      type = 'python';
    } else if (ext == 'md') {
      code = file.bytes != null ? utf8.decode(file.bytes!) : '';
      type = 'markdown';
    } else if (ext == 'html') {
      code = file.bytes != null ? utf8.decode(file.bytes!) : '';
      type = 'html';
    }

    if (_nb == null) return;
    final cell = NotebookCell(
      id: 'cell_${DateTime.now().millisecondsSinceEpoch}',
      type: type, code: code);
    final ctrl = TextEditingController(text: code);
    setState(() {
      _nb!.cells.add(cell);
      _controllers[cell.id] = ctrl;
    });
    _scheduleSave();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已导入 $name')));
  }

  Future<void> _exportFile() async {
    if (_nb == null) return;
    // 导出为 .ipynb 格式（JSON），当前仅提示，真正落盘导出下个版本支持
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('导出功能将在下个版本支持，当前内容已自动保存')));
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
      body: SafeArea(child: Column(children: [
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
                ('R', Icons.bar_chart, 'r'),
                ('LaTeX', Icons.functions, 'latex'),
                ('Markdown', Icons.text_fields, 'markdown'),
                ('HTML', Icons.html, 'html'),
              ]) _ToolBtn(
                label: t.$1, icon: t.$2,
                onTap: () => _addCell(t.$3)),
              _ToolBtn(label: '导入', icon: Icons.upload_file, onTap: _importFile),
              _ToolBtn(label: '导出', icon: Icons.download, onTap: _exportFile),
            ]))),
      ])),
    );
  }

  Widget _buildCell(NotebookCell cell, int index) {
    final ctrl = _controllers[cell.id] ??
      (_controllers[cell.id] = TextEditingController(text: cell.code));
    final isRunning = cell.isRunning;
    final hasOutput = cell.output != null;
    final isError = cell.outputType == 'error';
    final isSuccess = hasOutput && !isError;

    final badgeColor = {
      'python': _primary, 'r': const Color(0xFF2563EB),
      'latex': const Color(0xFFC026D3),
      'markdown': const Color(0xFF16A34A),
      'html': const Color(0xFFD97706),
    }[cell.type] ?? _primary;

    final badgeLabel = {
      'python': 'Python', 'r': 'R',
      'latex': 'LaTeX', 'markdown': 'Markdown', 'html': 'HTML',
    }[cell.type] ?? 'Python';

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
                if (cell.type == 'latex') {
                  _runLatexCell(cell);
                } else {
                  _runCodeCell(cell);
                }
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
                'r': '# R 代码...',
                'latex': r'输入 LaTeX 公式...',
                'markdown': '# Markdown 文本...',
                'html': '<p>HTML 内容...</p>',
              }[cell.type] ?? '代码...',
              hintStyle: TextStyle(color: Colors.grey[300],
                fontSize: 13, fontFamily: 'monospace'),
              contentPadding: EdgeInsets.zero),
          )),

        // 输出区
        if (cell.output != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F8F8),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(12)),
              border: Border(top: BorderSide(color: Colors.grey.shade100))),
            child: _buildOutput(cell.output!, cell.outputType)),
      ]));
  }

  Widget _buildOutput(String output, String? type) {
    switch (type) {
      case 'latex':
        // 真正的 LaTeX 渲染
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Math.tex(
            output,
            textStyle: const TextStyle(fontSize: 16),
            onErrorFallback: (err) => Text(output,
              style: const TextStyle(color: Colors.red, fontSize: 12)),
          ));
      case 'error':
        return Container(
          padding: const EdgeInsets.only(left: 8),
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(
              color: Color(0xFFFCA5A5), width: 2))),
          child: Text(output,
            style: const TextStyle(fontFamily: 'monospace',
              fontSize: 12, color: Color(0xFFDC2626), height: 1.5)));
      case 'image':
        if (output.startsWith('data:image')) {
          final b64 = output.split(',').last;
          return Image.memory(base64Decode(b64), fit: BoxFit.contain);
        }
        return Text(output,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12));
      default:
        return Text(output,
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
