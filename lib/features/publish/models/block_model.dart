import 'package:flutter/widgets.dart';

enum BlockType {
  text,
  heading,
  code,
  latex,
  image,
  file,
  audio,
  video,
  link,
  callout,
  // 存原始 Markdown（加粗/列表/小节标题等），编辑器 MarkdownBody 渲染、阅读端
  // 同样用 flutter_markdown 渲染——文字块只认行内公式、不认 Markdown 语法，
  // 小梦生成的含 ** / ## / - 这类内容要走这个块，不然会显示成生的 ** 符号
  markdown,
  // 参考文献块——content 存一个 JSON 数组（每条 {author,title,journal,year,
  // url,doi}），整块=一篇文章的完整参考文献列表。阅读端文末按 GB/T 样式
  // 编号展示、doi/url 可点。见 shared/utils/reference_format.dart
  reference,
}

// 实测确认（2026-07-05）：POST /auth/tutorials 的 blocks 字段要传原始数组，
// 不是字符串——传 jsonEncode(blocks) 得到的字符串会被后端静默丢弃，创建
// 和读取接口拿到的都是 blocks: []，连最简单的一个 text block 都不例外。
// 后端本身不校验/过滤 block 的 type 或字段，任何形状的对象都能原样存取，
// 所以 file/audio/video/link 这些阅读端（tutorial_detail_screen.dart）
// 之前没见过的类型也能正常写入——但必须同步给阅读端加上对应的渲染分支，
// 否则发布出去的内容里这几种 block 读者那边等于是空的
class EditorBlock {
  final String id;
  final BlockType type;
  String content;
  String? language; // code 用
  int? headingLevel; // heading 用 2/3/4
  String? imageUrl;
  String? caption;
  String? fileName;
  int? fileSize;
  String? fileType;
  String? linkTitle;
  String? linkUrl;
  String? variant; // callout: tip/warning/info
  bool isExecutable;
  // 数据集代码块——由 Notebook 导入数据的 cell 发布而来，content 里内嵌了
  // base64 数据 + pd.read_* 还原代码。阅读页进页时会静默执行这类 block 把
  // df 注入内核，读者不用手动先跑数据集就能运行下方用到 df 的代码
  bool isDataset;
  // latex block 公式自动编号——true（默认）时参与"文档内第 n 个公式"顺序编号、
  // 右侧显示 (n)；作者可逐条关闭。只对 BlockType.latex 有意义
  bool autoNumber;
  String? outputContent;
  String? outputType; // text/image/error
  // 文字格式——只在 text/heading block 上有意义。这里没有做到"选中一段
  // 文字单独加粗"的真富文本（那需要给 content 换成 spans/delta 结构 +
  // 阅读端同步换渲染方式，是另一个量级的活），是整块 block 一起套用同一
  // 份格式，跟 headingLevel 是同一个"整块生效"的语义，不是逐字符的
  bool isBold;
  bool isItalic;
  bool isUnderline;
  bool isStrike;
  int? textColorValue; // ARGB int，null=用主题默认文字色
  int? highlightColorValue; // ARGB int，null=不高亮
  String? fontFamily; // null/''=系统默认苹方，'serif'，'monospace'
  int fontSizeStep; // 0小/1中/2大/3特大
  int lineHeightStep; // 0紧凑/1标准/2宽松
  // 新建block之后自动跳光标要用——block_card.dart把这个传给对应输入框的
  // TextFormField.focusNode，_PublishScreenState._addBlock()在下一帧调
  // requestFocus()。EditorBlock被删除时要记得在_deleteBlock()里dispose，
  // 整个页面dispose()时也要把还剩的都清一遍，不然每次新建/删除block都在
  // 泄漏一个FocusNode
  final FocusNode focusNode = FocusNode();

  EditorBlock({
    required this.id,
    required this.type,
    this.content = '',
    this.language = 'python',
    this.headingLevel = 2,
    this.imageUrl,
    this.caption,
    this.fileName,
    this.fileSize,
    this.fileType,
    this.linkTitle,
    this.linkUrl,
    this.variant = 'info',
    this.isExecutable = false,
    this.isDataset = false,
    this.autoNumber = true,
    this.outputContent,
    this.outputType,
    this.isBold = false,
    this.isItalic = false,
    this.isUnderline = false,
    this.isStrike = false,
    this.textColorValue,
    this.highlightColorValue,
    this.fontFamily,
    this.fontSizeStep = 1,
    this.lineHeightStep = 1,
  });

  // 跟 tutorial_detail_screen.dart 的渲染字段一一对应：heading 用 level
  // 不是 headingLevel，code 用 executable 不是 isExecutable
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'content': content,
    // 只在关闭时才写（默认 true，省字段；旧数据无此字段 fromJson 也默认 true）
    if (type == BlockType.latex && !autoNumber) 'autoNumber': false,
    if (type == BlockType.code) 'language': language,
    if (type == BlockType.code) 'executable': isExecutable,
    if (type == BlockType.code && isDataset) 'isDataset': true,
    if (type == BlockType.heading) 'level': headingLevel,
    if (type == BlockType.image) 'imageUrl': imageUrl,
    if (type == BlockType.image) 'caption': caption,
    if (type == BlockType.file ||
        type == BlockType.audio ||
        type == BlockType.video) ...{
      'fileName': fileName,
      'fileSize': fileSize,
      if (type == BlockType.file) 'fileType': fileType,
    },
    if (type == BlockType.link) ...{'linkTitle': linkTitle, 'linkUrl': linkUrl},
    if (type == BlockType.callout) 'variant': variant,
    if (type == BlockType.text || type == BlockType.heading) ...{
      if (isBold) 'bold': true,
      if (isItalic) 'italic': true,
      if (isUnderline) 'underline': true,
      if (isStrike) 'strike': true,
      if (textColorValue != null) 'textColor': textColorValue,
      if (highlightColorValue != null) 'highlightColor': highlightColorValue,
      if (fontFamily != null && fontFamily!.isNotEmpty)
        'fontFamily': fontFamily,
      if (fontSizeStep != 1) 'fontSizeStep': fontSizeStep,
      if (lineHeightStep != 1) 'lineHeightStep': lineHeightStep,
    },
  };

  // 编辑已发布/草稿内容时把后端返回的 block 数组读回可编辑的 EditorBlock
  // 列表——跟 toJson 是一对反函数，字段名要对得上（heading 用 level 不是
  // headingLevel，code 用 executable 不是 isExecutable，见 toJson 里的注释）
  factory EditorBlock.fromJson(Map<String, dynamic> j) {
    final type = BlockType.values.firstWhere(
      (t) => t.name == j['type'],
      orElse: () => BlockType.text,
    );
    return EditorBlock(
      id:
          j['id']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      type: type,
      content: j['content']?.toString() ?? '',
      language:
          j['language']?.toString() ??
          (type == BlockType.code ? 'python' : null),
      headingLevel: (j['level'] as num?)?.toInt() ?? 2,
      imageUrl: j['imageUrl']?.toString(),
      caption: j['caption']?.toString(),
      fileName: j['fileName']?.toString(),
      fileSize: (j['fileSize'] as num?)?.toInt(),
      fileType: j['fileType']?.toString(),
      linkTitle: j['linkTitle']?.toString(),
      linkUrl: j['linkUrl']?.toString(),
      variant: j['variant']?.toString() ?? 'info',
      isExecutable: j['executable'] as bool? ?? false,
      // 老文章没有这个字段 → 默认 false，不影响现有内容
      isDataset: j['isDataset'] == true,
      // 旧数据无 autoNumber → 默认 true（向后兼容，老公式一样自动编号）
      autoNumber: j['autoNumber'] as bool? ?? true,
      isBold: j['bold'] == true,
      isItalic: j['italic'] == true,
      isUnderline: j['underline'] == true,
      isStrike: j['strike'] == true,
      textColorValue: (j['textColor'] as num?)?.toInt(),
      highlightColorValue: (j['highlightColor'] as num?)?.toInt(),
      fontFamily: j['fontFamily']?.toString(),
      fontSizeStep: (j['fontSizeStep'] as num?)?.toInt() ?? 1,
      lineHeightStep: (j['lineHeightStep'] as num?)?.toInt() ?? 1,
    );
  }
}

// 发布页底部状态栏、预览抽屉都要一份"多少字/多少分钟"的粗略估算，抽成
// 共用函数，不要两处各写一份容易慢慢跑偏。纯预览用的粗略估算，不追求
// 精确：正文类 block 按字符数算字数，图片/代码/文件/音频/视频这些
// "要花时间看"的 block 每个再加 0.5 分钟
(int chars, int minutes) computeBlockStats(List<EditorBlock> blocks) {
  var chars = 0;
  var heavyBlocks = 0;
  for (final b in blocks) {
    switch (b.type) {
      case BlockType.text:
      case BlockType.heading:
      case BlockType.code:
      case BlockType.latex:
      case BlockType.callout:
      case BlockType.markdown:
        chars += b.content.length;
        if (b.type == BlockType.code || b.type == BlockType.latex) {
          heavyBlocks++;
        }
        break;
      case BlockType.image:
      case BlockType.file:
      case BlockType.audio:
      case BlockType.video:
      case BlockType.link:
      // 参考文献块 content 是 JSON，不当正文字数算，按"要花时间看"的重块 +0.5min
      case BlockType.reference:
        heavyBlocks++;
        break;
    }
  }
  final minutes = ((chars / 200) + heavyBlocks * 0.5).ceil().clamp(1, 999);
  return (chars, minutes);
}
