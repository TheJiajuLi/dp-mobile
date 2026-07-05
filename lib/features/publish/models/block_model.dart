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
}
