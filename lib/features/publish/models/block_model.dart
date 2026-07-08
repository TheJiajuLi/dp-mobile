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
  String? outputContent;
  String? outputType; // text/image/error
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
    this.outputContent,
    this.outputType,
  });

  // 跟 tutorial_detail_screen.dart 的渲染字段一一对应：heading 用 level
  // 不是 headingLevel，code 用 executable 不是 isExecutable
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'content': content,
    if (type == BlockType.code) 'language': language,
    if (type == BlockType.code) 'executable': isExecutable,
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
      id: j['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      type: type,
      content: j['content']?.toString() ?? '',
      language: j['language']?.toString() ?? (type == BlockType.code ? 'python' : null),
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
        heavyBlocks++;
        break;
    }
  }
  final minutes = ((chars / 200) + heavyBlocks * 0.5).ceil().clamp(1, 999);
  return (chars, minutes);
}
