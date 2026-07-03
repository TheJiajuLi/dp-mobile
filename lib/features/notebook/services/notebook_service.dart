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
    return List<Map<String, dynamic>>.from(jsonDecode(raw));
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
      ...recent.where((r) => r['id'] != nb.id),
    ].take(10).toList();
    await prefs.setString(_key('nb_recent'), jsonEncode(updated));
  }
}
