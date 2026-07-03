import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/notebook_model.dart';

class NotebookService {
  final String userId;
  NotebookService(this.userId);

  String _key(String k) => '${userId}_$k';

  Future<List<Map<String, dynamic>>> getRecentList() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key('nb_recent'));
    if (raw == null) return [];
    final list = List<Map<String, dynamic>>.from(jsonDecode(raw));

    // 按 name 去重，只保留最靠前（最近更新）的那条；顺便兜底旧数据里
    // 已经攒下的重复项，不用等用户再手动清一遍才干净
    final seenNames = <String>{};
    final deduped = <Map<String, dynamic>>[];
    for (final item in list) {
      final name = item['name'] as String? ?? '';
      if (seenNames.contains(name)) continue;
      seenNames.add(name);
      deduped.add(item);
    }
    return deduped.take(5).toList();
  }

  Future<Notebook> create(String name, String lang) async {
    final id = 'nb_${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final defaultCode = {
      'python': '# 开始你的分析\nimport pandas as pd\nimport matplotlib.pyplot as plt\n',
      'latex': '${r'\text{在这里输入公式：}'}\n${r'f(x) = \int_{-\infty}^{\infty} \hat{f}(\xi) e^{2\pi i \xi x} d\xi'}',
      'mixed': '# 混合模式\n',
    }[lang] ?? '';

    final nb = Notebook(
      id: id, name: name, lang: lang,
      cells: [NotebookCell(
        id: 'cell_${DateTime.now().millisecondsSinceEpoch}',
        type: lang == 'latex' ? 'latex' : 'python',
        code: defaultCode,
      )],
      createdAt: now, updatedAt: now,
    );
    await save(nb);
    return nb;
  }

  Future<void> save(Notebook nb) async {
    final prefs = await SharedPreferences.getInstance();
    nb.updatedAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await prefs.setString(_key('nb_${nb.id}'), jsonEncode(nb.toJson()));
    await _updateRecent(nb);
  }

  Future<Notebook?> load(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key('nb_$id'));
    if (raw == null) return null;
    return Notebook.fromJson(jsonDecode(raw));
  }

  Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key('nb_$id'));
    final recent = await getRecentList();
    final updated = recent.where((r) => r['id'] != id).toList();
    await prefs.setString(_key('nb_recent'), jsonEncode(updated));
  }

  Future<void> _updateRecent(Notebook nb) async {
    final prefs = await SharedPreferences.getInstance();
    final recent = await getRecentList();
    final updated = [
      {'id': nb.id, 'name': nb.name, 'lang': nb.lang,
       'cellCount': nb.cells.length, 'updatedAt': nb.updatedAt},
      ...recent.where((r) => r['id'] != nb.id && r['name'] != nb.name),
    ].take(5).toList();
    await prefs.setString(_key('nb_recent'), jsonEncode(updated));
  }

  // 从 .ipynb 文件导入 Notebook
  static Notebook fromIpynb(String jsonStr, String name) {
    final ipynb = jsonDecode(jsonStr) as Map<String, dynamic>;
    final cells = <NotebookCell>[];

    for (final rawCell in (ipynb['cells'] as List? ?? [])) {
      final cell = rawCell as Map<String, dynamic>;
      final cellType = cell['cell_type'] as String? ?? 'code';

      final sourceRaw = cell['source'];
      final source = sourceRaw is List
          ? sourceRaw.map((e) => e.toString()).join('')
          : sourceRaw?.toString() ?? '';

      String lang;
      if (cellType == 'markdown' || cellType == 'raw') {
        lang = 'markdown';
      } else {
        final metadata = ipynb['metadata'] as Map<String, dynamic>?;
        final kernelspec = metadata?['kernelspec'] as Map<String, dynamic>?;
        lang = kernelspec?['language'] as String? ?? 'python';
      }

      // 读取已有输出
      String? output;
      String? outputType;
      final outputs = cell['outputs'] as List?;
      if (outputs != null && outputs.isNotEmpty) {
        final firstOut = outputs.first as Map<String, dynamic>;
        final outType = firstOut['output_type'];

        if (outType == 'stream') {
          final text = firstOut['text'];
          output = text is List ? text.map((e) => e.toString()).join('') : text.toString();
          outputType = 'text';
        } else if (outType == 'display_data' || outType == 'execute_result') {
          final data = firstOut['data'] as Map<String, dynamic>?;
          if (data?['image/png'] != null) {
            output = 'data:image/png;base64,${data!['image/png']}';
            outputType = 'image';
          } else if (data?['text/html'] != null) {
            final html = data!['text/html'];
            output = html is List ? html.map((e) => e.toString()).join('') : html.toString();
            outputType = 'html';
          } else if (data?['text/plain'] != null) {
            final text = data!['text/plain'];
            output = text is List ? text.map((e) => e.toString()).join('') : text.toString();
            outputType = 'text';
          }
        } else if (outType == 'error') {
          final traceback = firstOut['traceback'] as List?;
          output = traceback?.join('\n') ?? firstOut['ename']?.toString() ?? '';
          outputType = 'error';
        }
      }

      cells.add(NotebookCell(
        id: 'cell_${DateTime.now().millisecondsSinceEpoch}_${cells.length}',
        type: lang,
        code: source,
        output: output,
        outputType: outputType,
      ));
    }

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return Notebook(
      id: 'nb_$now',
      name: name,
      lang: 'mixed',
      cells: cells,
      createdAt: now,
      updatedAt: now,
    );
  }

  // 导出为 .ipynb 格式
  static String toIpynb(Notebook nb) {
    final cells = nb.cells.map((cell) {
      final cellType = (cell.type == 'markdown' || cell.type == 'latex') ? 'markdown' : 'code';
      final source = cell.code.split('\n').map((line) => '$line\n').toList();

      final outputs = <Map<String, dynamic>>[];
      if (cell.output != null) {
        if (cell.outputType == 'image') {
          outputs.add({
            'output_type': 'display_data',
            'data': {
              'image/png': cell.output!.replaceAll('data:image/png;base64,', ''),
              'text/plain': ['<Figure>'],
            },
            'metadata': {},
          });
        } else if (cell.outputType == 'error') {
          outputs.add({
            'output_type': 'error',
            'ename': 'Error',
            'evalue': cell.output!,
            'traceback': [cell.output!],
          });
        } else {
          outputs.add({
            'output_type': 'stream',
            'name': 'stdout',
            'text': cell.output!.split('\n').map((l) => '$l\n').toList(),
          });
        }
      }

      return {
        'cell_type': cellType,
        'source': source,
        'metadata': {},
        if (cellType == 'code') 'outputs': outputs,
        if (cellType == 'code') 'execution_count': null,
      };
    }).toList();

    return jsonEncode({
      'nbformat': 4,
      'nbformat_minor': 5,
      'metadata': {
        'kernelspec': {
          'display_name': 'Python 3',
          'language': 'python',
          'name': 'python3',
        },
        'language_info': {'name': 'python'},
      },
      'cells': cells,
    });
  }
}
