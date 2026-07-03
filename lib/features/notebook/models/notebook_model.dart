class NotebookCell {
  final String id;
  final String type; // python / r / latex / markdown / html
  String code;
  String? output;
  String? outputType; // text / error / image / latex / html
  bool isRunning;

  NotebookCell({
    required this.id,
    required this.type,
    this.code = '',
    this.output,
    this.outputType,
    this.isRunning = false,
  });

  factory NotebookCell.fromJson(Map<String, dynamic> json) => NotebookCell(
    id: json['id'] ?? '',
    type: json['type'] ?? 'python',
    code: json['code'] ?? '',
    output: json['output'],
    outputType: json['outputType'],
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'type': type, 'code': code,
    'output': output, 'outputType': outputType,
  };
}

class Notebook {
  final String id;
  String name;
  final String lang; // python / latex / mixed
  List<NotebookCell> cells;
  final int createdAt;
  int updatedAt;

  Notebook({
    required this.id, required this.name, required this.lang,
    required this.cells, required this.createdAt, required this.updatedAt,
  });

  String get filename {
    if (name.contains('.')) return name;
    final ext = {'python': '.py', 'latex': '.tex', 'mixed': '.ipynb'}[lang] ?? '.ipynb';
    return name + ext;
  }

  factory Notebook.fromJson(Map<String, dynamic> json) => Notebook(
    id: json['id'] ?? '',
    name: json['name'] ?? '',
    lang: json['lang'] ?? 'python',
    cells: (json['cells'] as List? ?? []).map((c) => NotebookCell.fromJson(c)).toList(),
    createdAt: json['createdAt'] ?? 0,
    updatedAt: json['updatedAt'] ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'lang': lang,
    'cells': cells.map((c) => c.toJson()).toList(),
    'createdAt': createdAt, 'updatedAt': updatedAt,
  };
}
