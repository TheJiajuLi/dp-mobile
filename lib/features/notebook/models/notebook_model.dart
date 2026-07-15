// 语言支持一览，目前 NotebookCell.type 仍以 String 存储（见下方字段注释），
// 这个 enum 作为受支持语言的权威列表，供 UI（工具栏/校验）引用。
enum CellLanguage {
  python,
  latex,
  markdown,
  sql,
  javascript,
  r, // 占位，即将支持
  julia, // 占位，即将支持
}

class NotebookCell {
  final String id;
  String type; // python / sql / javascript / latex / markdown / r / julia / html
  String code;
  String? output;
  String? outputType; // text / error / image / latex / html / markdown / info
  bool isRunning;
  // 附加信息——导入数据文件时标记为数据集 cell（{isDataset:true,fileName,
  // rowCount}），供编辑器/阅读端显示「数据集」徽标、绿色就绪提示等
  Map<String, dynamic>? metadata;

  NotebookCell({
    required this.id,
    required this.type,
    this.code = '',
    this.output,
    this.outputType,
    this.isRunning = false,
    this.metadata,
  });

  factory NotebookCell.fromJson(Map<String, dynamic> json) => NotebookCell(
    id: json['id'] ?? '',
    type: json['type'] ?? 'python',
    code: json['code'] ?? '',
    output: json['output'],
    outputType: json['outputType'],
    metadata: json['metadata'] is Map
        ? Map<String, dynamic>.from(json['metadata'] as Map)
        : null,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'type': type, 'code': code,
    'output': output, 'outputType': outputType,
    if (metadata != null) 'metadata': metadata,
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
