import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/utils/block_text_style.dart';
import '../../../shared/utils/pro_access.dart';
import '../../../shared/utils/code_highlight.dart';
import '../../../shared/utils/premium_button.dart';
import '../../../shared/widgets/tutorial_block_renderer.dart'
    show inlineLatexText;
import '../models/block_model.dart';
import 'block_picker_sheet.dart';

const _primary = Color(0xFF6366F1);

// code block 的语言下拉里特意不放 latex——LaTeX 已经是独立的 block 类型，
// 跟聊天那边"用独立 type='latex' 而不是 type='code'+metadata.language"
// 是同一个道理，两条路径都能表示公式只会互相打架
// 代码块语言下拉的候选项。导入的代码块 language 可能是 'text'/'jsx'/'tsx'/
// 'bash'/'json'/'yaml'/'ts' 等各种值，不在这个列表里时 DropdownButton 的
// value 找不到对应 item 会直接 assert 崩溃——列表要尽量全，value 处再做
// 一层 fallback 兜底（见 _safeLanguage）
const _codeLanguages = [
  'python',
  'javascript',
  'typescript',
  'jsx',
  'tsx',
  'sql',
  'html',
  'css',
  'json',
  'yaml',
  'bash',
  'shell',
  'markdown',
  'dart',
  'java',
  'kotlin',
  'swift',
  'rust',
  'go',
  'r',
  'cpp',
  'c',
  'plaintext',
];

// 语言下拉里显示成首字母大写（python → Python），value 仍用小写原值，
// 不影响 _codeLanguages 匹配
String _capLang(String l) =>
    l.isEmpty ? l : l[0].toUpperCase() + l.substring(1);

String _formatSize(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
}

class BlockCard extends ConsumerStatefulWidget {
  final EditorBlock block;
  final int index;
  final int total;
  // 实测确认：currentUserProvider 的 UserModel 上没有 membership 字段，
  // 会员等级只有 GET /auth/storage/usage 会返回。这个值改成由父级
  // PublishScreen 用 ref.watch(storageUsageProvider) 拿到之后往下传，
  // 而不是在这里自己 ref.read——storageUsageProvider 是 autoDispose 的
  // FutureProvider，没有人在 watch 的话这里读到的会是还没算完的
  // AsyncLoading，永远兜底成 free，付费用户也会被误判成免费版
  final String membership;
  // 真正跑代码的入口，由 PublishScreen 统一持有隐藏 WebView/Pyodide 引擎并
  // 实现；这里不需要知道 WebView 是否就绪、SQL 要不要包装这些细节，调用
  // 一次拿到一份 [{type, content}, ...] 结果就行——环境还没就绪时会在
  // PublishScreen 那边等最多60秒，不是立刻失败
  final Future<List<Map<String, dynamic>>> Function(
    String blockId,
    String code,
    String language,
  )
  onRunCode;
  final VoidCallback onDelete;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onChanged;
  // 文字/标题 block 获得焦点时通知 PublishScreen——底部格式工具栏（粗体/
  // 颜色/字体等）只在"当前正在编辑哪个 block"明确的时候才有意义，这个
  // 状态本来就该由父级持有，不是 BlockCard 自己的事
  final VoidCallback? onFocusGained;
  // 文字/标题输入框失焦（收起键盘/切到别的控件）时通知父级清掉
  // focusedBlockId——不然格式工具栏只会越绑越"新"，永远不会真正收起
  final VoidCallback? onFocusLost;
  // 非文字类block（图片/代码/公式等）点击时通知父级——这些block不适用
  // 格式工具栏，点了应该让工具栏收起，不是继续绑在上一个文字block上
  final VoidCallback? onNonTextTap;
  // 父级当前"激活"的是哪个block——卡片自己的chrome（拖拽手柄/AI按钮/
  // 移动/删除/边框）只在这个block是激活态时才显示，平时收起来减少噪音
  final String? focusedBlockId;
  // 每次上传文件成功（图片/视频/音频/文件）把后端返回的 file id 报给
  // PublishScreen 收集，退出未保存时用来清理 COS 里这些孤儿文件
  final void Function(String fileId)? onFileUploaded;

  const BlockCard({
    super.key,
    required this.block,
    required this.index,
    required this.total,
    required this.membership,
    required this.onRunCode,
    required this.onDelete,
    this.onMoveUp,
    this.onMoveDown,
    required this.onChanged,
    this.onFocusGained,
    this.onFocusLost,
    this.onNonTextTap,
    this.focusedBlockId,
    this.onFileUploaded,
  });

  @override
  ConsumerState<BlockCard> createState() => _BlockCardState();
}

class _BlockCardState extends ConsumerState<BlockCard> {
  bool _running = false;
  bool _focused = false;
  bool _polishing = false;
  // 文字 block 用的是 TextFormField(initialValue: ...)，不是受控的
  // controller——小梦优化后台把 widget.block.content 改掉再 setState 是
  // 不会自动反映到输入框上的（initialValue 只在第一次创建时读一次）。
  // 靠这个计数器换 key 强制 TextFormField 整个重建，才能捡到新的
  // initialValue；只在"应用优化结果"时才 +1，正常打字不碰它，
  // 不会打断输入焦点/光标位置
  int _textRevision = 0;
  // 代码块专用——用能实时按 token 上色的 controller 替代默认的
  // TextFormField(initialValue: ...)，编辑态才能跟阅读态一样有语法高亮
  late final HighlightingCodeController _codeCtrl = HighlightingCodeController(
    text: widget.block.content,
    language: widget.block.language ?? 'python',
  );

  @override
  void initState() {
    super.initState();
    // 用 FocusNode 监听而不是 TextFormField.onTap——_addBlock() 新建
    // block 后是程序调用 focusNode.requestFocus()，不会触发用户点击
    // 手势的 onTap，底部格式工具栏得靠这个监听器才能知道新 block 也
    // "获得了焦点"
    widget.block.focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (widget.block.focusNode.hasFocus) {
      widget.onFocusGained?.call();
    } else {
      widget.onFocusLost?.call();
    }
  }

  bool get _isActive => widget.block.id == widget.focusedBlockId;

  @override
  void dispose() {
    widget.block.focusNode.removeListener(_handleFocusChange);
    _codeCtrl.dispose();
    super.dispose();
  }

  // LaTeX 的"用自然语言生成公式"不需要已有内容，其余几种都需要已有内容才
  // 有得优化/解释——不然点开菜单里全是点了也没反应的选项
  bool get _showsAiButton {
    const aiTypes = {
      BlockType.text,
      BlockType.heading,
      BlockType.callout,
      BlockType.code,
      BlockType.latex,
    };
    if (!aiTypes.contains(widget.block.type)) return false;
    if (widget.block.type == BlockType.latex) return true;
    return widget.block.content.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 代码块整张卡片直接用深底——不再是白卡片里再套一个深色小块（白框
    // 套深块两层嵌套很割裂），整块深色跟里面的代码区连成一体。代码块的
    // 深底+细描边不受激活态影响，一直保持（不然代码区没了容器背景，字
    // 直接糊在页面背景上，比"吵"更难看）
    final isCode = widget.block.type == BlockType.code;
    // 未激活时卡片完全透明、无边框，跟页面融为一体；激活时才浮出白色/
    // 深色卡片背景+细描边——减少同屏一堆边框叠边框的视觉噪音，只有正在
    // 编辑的那一个 block 需要被"框"出来
    return GestureDetector(
      // 非文字/标题类block自己没有走 onFocusGained 那条路（它们的
      // FocusNode 没接到真正的输入框上，或者内部输入框跟格式工具栏无关，
      // 比如代码/公式源码框），点了要主动告诉父级——translucent 不会
      // 拦下内部各自的手势（图片点击换图/代码框输入等照常工作）
      behavior: HitTestBehavior.translucent,
      onTap: () {
        if (widget.block.type != BlockType.text &&
            widget.block.type != BlockType.heading) {
          widget.onNonTextTap?.call();
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isCode
              ? const Color(0xFF1A1A1A)
              : (_isActive ? Theme.of(context).cardColor : Colors.transparent),
          borderRadius: BorderRadius.circular(14),
          border: isCode
              ? Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 0.5,
                )
              : (_isActive
                    ? Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : const Color(0xFFEBEBEB),
                        width: 0.5,
                      )
                    : null),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 类型图标+类型名一行，操作按钮放在同一行右侧——拖拽手柄/AI入口/
            // 移动/删除只在这个block激活时才显示，平时收起来减少噪音
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 0),
              child: Row(
                children: [
                  Icon(
                    blockTypeIcon(widget.block.type),
                    size: 14,
                    color: const Color(0xFF999999),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    blockTypeLabel(l10n, widget.block.type),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF999999),
                    ),
                  ),
                  const Spacer(),
                  // AI入口/上移/下移/删除/拖拽手柄——只在这个block是当前
                  // 激活的那一个时才显示，没激活时收起来，同屏不再是一堆
                  // block各自顶着一整排图标的噪音感
                  if (_isActive) ...[
                    if (_showsAiButton)
                      _polishing
                          ? const Padding(
                              padding: EdgeInsets.all(4),
                              child: SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: _primary,
                                ),
                              ),
                            )
                          : GestureDetector(
                              onTap: _showAiMenu,
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  Icons.auto_awesome_outlined,
                                  size: 15,
                                  color: Colors.grey.shade400,
                                ),
                              ),
                            ),
                    if (widget.onMoveUp != null)
                      GestureDetector(
                        onTap: widget.onMoveUp,
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.arrow_upward,
                            size: 16,
                            color: Color(0xFFBBBBBB),
                          ),
                        ),
                      ),
                    if (widget.onMoveDown != null)
                      GestureDetector(
                        onTap: widget.onMoveDown,
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.arrow_downward,
                            size: 16,
                            color: Color(0xFFBBBBBB),
                          ),
                        ),
                      ),
                    GestureDetector(
                      onTap: widget.onDelete,
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color: Color(0xFFBBBBBB),
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    // 光一个 Icon 摆在那不会自己变成拖拽热区——
                    // ReorderableListView 默认是"长按列表项里任意没被别的
                    // 手势抢走的地方"才能拖，跟"按住这个把手图标就立刻能拖"
                    // 的直觉不一样。用 ReorderableDragStartListener 把拖拽
                    // 手势精确绑定在这一个图标上，摁下就能拖，不用长按，
                    // 也不会跟这一行其它按钮/下面的输入框抢手势
                    ReorderableDragStartListener(
                      index: widget.index,
                      child: const Icon(
                        Icons.drag_handle,
                        size: 18,
                        color: Color(0xFFDDDDDD),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              // 代码块铺满整张深色卡片，其它类型保持原来的四周留白
              padding: isCode
                  ? const EdgeInsets.fromLTRB(0, 4, 0, 0)
                  : const EdgeInsets.fromLTRB(10, 6, 10, 10),
              child: _buildContent(l10n),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(AppLocalizations l10n) {
    switch (widget.block.type) {
      case BlockType.text:
        return _buildTextBlock(l10n);
      case BlockType.heading:
        return _buildHeadingBlock(l10n);
      case BlockType.code:
        return _buildCodeBlock(l10n);
      case BlockType.latex:
        return _buildLatexBlock(l10n);
      case BlockType.image:
        return _buildImageBlock(l10n);
      case BlockType.file:
        return _buildFileBlock(l10n);
      case BlockType.audio:
        return _buildAudioBlock(l10n);
      case BlockType.video:
        return _buildVideoBlock(l10n);
      case BlockType.link:
        return _buildLinkBlock(l10n);
      case BlockType.callout:
        return _buildCalloutBlock(l10n);
    }
  }

  static final _inlineLatexPattern = RegExp(r'\$[^$\n]+\$');

  Widget _buildTextBlock(AppLocalizations l10n) {
    final style = applyBlockTextFormat(
      TextStyle(
        fontSize: 14,
        height: 1.7,
        color: Theme.of(context).textTheme.bodyLarge?.color,
      ),
      isBold: widget.block.isBold,
      isItalic: widget.block.isItalic,
      isUnderline: widget.block.isUnderline,
      isStrike: widget.block.isStrike,
      textColorValue: widget.block.textColorValue,
      highlightColorValue: widget.block.highlightColorValue,
      fontFamily: widget.block.fontFamily,
      fontSizeStep: widget.block.fontSizeStep,
      lineHeightStep: widget.block.lineHeightStep,
    );

    // 含 $...$ 的文字段——没聚焦时渲染成真正的公式（跟阅读页
    // inlineLatexText 同一份逻辑），不然编辑器里永远只能看到原始
    // $公式$ 源码，写完公式也不知道对不对。一点上去切回原始
    // TextFormField 改源码，光标一收起（onEditingComplete）就切回渲染态。
    // 没有公式的普通段落不受影响，还是原来那个一直可编辑的 TextFormField
    final hasInlineLatex = _inlineLatexPattern.hasMatch(widget.block.content);
    if (!_focused && hasInlineLatex) {
      return GestureDetector(
        onTap: () {
          setState(() => _focused = true);
          widget.block.focusNode.requestFocus();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: inlineLatexText(widget.block.content, style),
        ),
      );
    }

    return TextFormField(
      key: ValueKey('text_${widget.block.id}_$_textRevision'),
      focusNode: widget.block.focusNode,
      initialValue: widget.block.content.isNotEmpty
          ? widget.block.content
          : null,
      decoration: InputDecoration(
        filled: false,
        hintText: l10n.textBlockHint,
        hintStyle: const TextStyle(color: Color(0xFFC7C7CC)),
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
      ),
      style: style,
      maxLines: null,
      onChanged: (v) {
        widget.block.content = v;
        widget.onChanged();
      },
      onTap: () => setState(() => _focused = true),
      onEditingComplete: () => setState(() => _focused = false),
    );
  }

  void _showAiMenu() {
    switch (widget.block.type) {
      case BlockType.text:
      case BlockType.heading:
      case BlockType.callout:
        _showTextAiMenu();
      case BlockType.code:
        _showCodeAiMenu();
      case BlockType.latex:
        _showLatexAiMenu();
      default:
        break;
    }
  }

  void _showTextAiMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Row(
              children: [
                Icon(Icons.auto_awesome, size: 18, color: _primary),
                SizedBox(width: 8),
                Text(
                  '小梦优化',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...[
              ('vivid', Icons.diamond_outlined, '优化文字', '让表达更生动流畅'),
              ('concise', Icons.content_cut, '精简浓缩', '删掉废话，留下精华'),
              ('formal', Icons.description_outlined, '正式化', '适合学术/报告风格'),
            ].map(
              (item) => ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    item.$2,
                    size: 17,
                    color: const Color(0xFF555555),
                  ),
                ),
                title: Text(
                  item.$3,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(item.$4, style: const TextStyle(fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _polishBlock(item.$1);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _polishBlock(String style) async {
    final original = widget.block.content;
    if (original.isEmpty) return;

    setState(() => _polishing = true);

    try {
      final res = await ref
          .read(apiClientProvider)
          .post('/auth/xmeng/polish', data: {'text': original, 'style': style});

      if (res.success && mounted) {
        final result = (res.data as Map?)?['result'] as String? ?? '';
        if (result.isNotEmpty) {
          showDialog(
            context: context,
            builder: (dCtx) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.auto_awesome, size: 18, color: _primary),
                  SizedBox(width: 8),
                  Text('小梦的修改'),
                ],
              ),
              content: SingleChildScrollView(
                child: Text(
                  result,
                  style: const TextStyle(fontSize: 14, height: 1.6),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dCtx),
                  child: const Text(
                    '不用了',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      widget.block.content = result;
                      _textRevision++;
                    });
                    widget.onChanged();
                    Navigator.pop(dCtx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    '应用',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('小梦开小差了，请重试')));
      }
    } finally {
      if (mounted) setState(() => _polishing = false);
    }
  }

  void _showCodeAiMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF0FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_outlined,
                    size: 14,
                    color: _primary,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  '小梦代码助手',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...[
              ('explain', Icons.menu_book_outlined, '解释代码', '用简单语言解释这段代码'),
              ('optimize', Icons.speed_outlined, '优化代码', '提升可读性和性能'),
              ('comment', Icons.comment_outlined, '添加注释', '为每行添加中文注释'),
              ('bug', Icons.bug_report_outlined, '查找问题', '检查潜在的bug'),
            ].map(
              (item) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    item.$2,
                    size: 17,
                    color: const Color(0xFF555555),
                  ),
                ),
                title: Text(
                  item.$3,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(item.$4, style: const TextStyle(fontSize: 12)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _assistCode(item.$1);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _assistCode(String action) async {
    final code = widget.block.content;
    if (code.isEmpty) return;

    final prompts = {
      'explain':
          '请用简洁的中文解释以下代码的功能和逻辑，分点说明：\n\n'
          '```${widget.block.language}\n$code\n```',
      'optimize':
          '请优化以下代码，提升可读性和性能，直接输出优化后的完整代码：\n\n'
          '```${widget.block.language}\n$code\n```',
      'comment':
          '为以下代码每行添加简洁的中文注释，直接输出带注释的完整代码：\n\n'
          '```${widget.block.language}\n$code\n```',
      'bug':
          '检查以下代码中可能存在的bug或问题，列出问题和修改建议：\n\n'
          '```${widget.block.language}\n$code\n```',
    };

    setState(() {
      widget.block.outputContent = '小梦分析中...';
      widget.block.outputType = 'info';
    });
    widget.onChanged();

    try {
      final res = await ref
          .read(apiClientProvider)
          .post(
            '/auth/xmeng/chat',
            data: {
              'messages': [
                {'role': 'user', 'content': prompts[action] ?? ''},
              ],
            },
            options: Options(receiveTimeout: const Duration(seconds: 60)),
          );

      setState(() {
        widget.block.outputContent = null;
        widget.block.outputType = null;
      });

      if (!res.success || !mounted) return;
      final result = (res.data as Map?)?['message'] as String? ?? '';
      if (result.isEmpty) return;

      if (action == 'optimize' || action == 'comment') {
        // 优化/注释这两种是"替换代码"操作，弹确认框而不是直接覆盖，避免
        // 一言不合就把用户已经写好的代码冲掉
        showDialog(
          context: context,
          builder: (dCtx) => AlertDialog(
            title: const Text('小梦的建议'),
            content: SingleChildScrollView(
              child: Text(
                result,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dCtx),
                child: const Text('关闭', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: () {
                  final codeMatch = RegExp(
                    r'```\w*\n?([\s\S]*?)```',
                  ).firstMatch(result);
                  final extracted = codeMatch?.group(1)?.trim() ?? result;
                  setState(() {
                    widget.block.content = extracted;
                    _codeCtrl.text = extracted;
                  });
                  widget.onChanged();
                  Navigator.pop(dCtx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('应用', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      } else {
        // 解释/查找问题：直接当作一次"运行输出"展示在代码块下方
        setState(() {
          widget.block.outputContent = result;
          widget.block.outputType = 'text';
        });
        widget.onChanged();
      }
    } catch (e) {
      setState(() {
        widget.block.outputContent = null;
        widget.block.outputType = null;
      });
      widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('小梦开小差了，请重试')));
      }
    }
  }

  void _showLatexAiMenu() {
    final promptCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF0FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_outlined,
                      size: 14,
                      color: _primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '小梦公式助手',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (widget.block.content.isNotEmpty)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.menu_book_outlined,
                      size: 17,
                      color: Color(0xFF555555),
                    ),
                  ),
                  title: const Text(
                    '解释这个公式',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  subtitle: const Text(
                    '用通俗语言解释公式含义',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _explainLatex();
                  },
                ),
              const Text(
                '用自然语言描述公式',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: promptCtrl,
                decoration: InputDecoration(
                  hintText: '如：泊松分布的概率质量函数',
                  hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
                  filled: true,
                  fillColor: Colors.grey[50],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _primary),
                  ),
                ),
                style: const TextStyle(fontSize: 13),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: ['正态分布', '贝叶斯定理', '泰勒展开', '矩阵行列式'].map((t) {
                  return GestureDetector(
                    onTap: () => promptCtrl.text = t,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        t,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF555555),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final desc = promptCtrl.text.trim();
                    if (desc.isEmpty) return;
                    Navigator.pop(ctx);
                    await _generateLatex(desc);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A1A),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    '生成 LaTeX',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _explainLatex() async {
    final formula = widget.block.content;
    setState(() {
      widget.block.outputContent = '小梦解释中...';
      widget.block.outputType = 'info';
    });
    widget.onChanged();

    try {
      final res = await ref
          .read(apiClientProvider)
          .post(
            '/auth/xmeng/chat',
            data: {
              'messages': [
                {
                  'role': 'user',
                  'content': '请用通俗语言解释以下LaTeX公式的数学含义：\n\n$formula',
                },
              ],
            },
            options: Options(receiveTimeout: const Duration(seconds: 60)),
          );

      if (!mounted) return;
      setState(() {
        widget.block.outputContent = res.success
            ? ((res.data as Map?)?['message'] as String? ?? '')
            : null;
        widget.block.outputType = 'text';
      });
      widget.onChanged();
    } catch (e) {
      setState(() {
        widget.block.outputContent = null;
        widget.block.outputType = null;
      });
      widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('小梦开小差了，请重试')));
      }
    }
  }

  Future<void> _generateLatex(String description) async {
    try {
      final res = await ref
          .read(apiClientProvider)
          .post(
            '/auth/xmeng/chat',
            data: {
              'messages': [
                {
                  'role': 'user',
                  'content':
                      '请把以下数学概念转换为LaTeX公式代码，只输出LaTeX代码本身，不要解释，不要markdown代码块：\n\n$description',
                },
              ],
            },
            options: Options(receiveTimeout: const Duration(seconds: 60)),
          );

      if (!res.success || !mounted) return;
      final latex = (res.data as Map?)?['message'] as String? ?? '';
      if (latex.isNotEmpty) {
        setState(() {
          widget.block.content = latex.trim();
          _textRevision++;
        });
        widget.onChanged();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('生成失败，请重试')));
      }
    }
  }

  Widget _buildHeadingBlock(AppLocalizations l10n) => TextFormField(
    key: ValueKey('heading_${widget.block.id}_$_textRevision'),
    focusNode: widget.block.focusNode,
    initialValue: widget.block.content.isNotEmpty ? widget.block.content : null,
    decoration: InputDecoration(
      filled: false,
      hintText: l10n.headingBlockHint(widget.block.headingLevel ?? 2),
      hintStyle: const TextStyle(color: Color(0xFFC7C7CC)),
      border: InputBorder.none,
      isDense: true,
      contentPadding: EdgeInsets.zero,
    ),
    style: applyBlockTextFormat(
      TextStyle(
        fontSize: widget.block.headingLevel == 2
            ? 20
            : widget.block.headingLevel == 3
            ? 17
            : 15,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).textTheme.bodyLarge?.color,
      ),
      isBold: widget.block.isBold,
      isItalic: widget.block.isItalic,
      isUnderline: widget.block.isUnderline,
      isStrike: widget.block.isStrike,
      textColorValue: widget.block.textColorValue,
      highlightColorValue: widget.block.highlightColorValue,
      fontFamily: widget.block.fontFamily,
      fontSizeStep: widget.block.fontSizeStep,
      lineHeightStep: widget.block.lineHeightStep,
    ),
    maxLines: 1,
    onChanged: (v) {
      widget.block.content = v;
      widget.onChanged();
    },
    onTap: () => setState(() => _focused = true),
    onEditingComplete: () => setState(() => _focused = false),
  );

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: widget.block.content));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已复制代码')));
  }

  // 外面套一层 ClipRRect 统一裁出四角圆角——header/body/output 内部各自
  // 保持矩形不用再各管一次"只圆某几个角"，没有输出内容时底部也不会再
  // 露出一条直角硬边（之前那条 0.5px 分隔线本身是矩形，紧贴在只做了
  // topLeft/topRight 圆角的 body 下面，视觉上整个代码块的下半截是方的）
  Widget _buildCodeBlock(AppLocalizations l10n) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0xFF1A1A1A),
            child: Row(
              children: [
                // 单个状态圆点，替代原来的 macOS 三色点，视觉更克制
                Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: _primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                DropdownButton<String>(
                  // language 不在候选列表里（导入的代码块常给 text/jsx/ts 等）
                  // 就降级到 python，不然 DropdownButton value 匹配不到 item
                  // 会 assert 崩溃
                  value: _codeLanguages.contains(widget.block.language)
                      ? widget.block.language
                      : 'python',
                  dropdownColor: const Color(0xFF1A1A1A),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFE5E7EB),
                  ),
                  icon: const Icon(
                    Icons.keyboard_arrow_down,
                    size: 16,
                    color: Color(0xFF888888),
                  ),
                  underline: const SizedBox(),
                  isDense: true,
                  items: _codeLanguages
                      .map(
                        (l) => DropdownMenuItem(
                          value: l,
                          child: Text(
                            _capLang(l),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFFE5E7EB),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      widget.block.language = v;
                      _codeCtrl.language = v;
                    });
                  },
                ),
                const Spacer(),
                // 运行按钮——深色底 + 细描边 + 空心播放，不再是亮紫实心胶囊
                PressableScale(
                  onTap: _running ? null : _runCode,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2E),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_running)
                          const SizedBox(
                            width: 11,
                            height: 11,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Color(0xFF9B98FF),
                            ),
                          )
                        else
                          const Icon(
                            Icons.play_arrow_outlined,
                            size: 15,
                            color: Color(0xFF9B98FF),
                          ),
                        const SizedBox(width: 4),
                        Text(
                          _running ? l10n.runningLabel : l10n.runAction,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFFE5E7EB),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // 复制代码
                GestureDetector(
                  onTap: _copyCode,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.copy_outlined,
                      size: 15,
                      color: Color(0xFF888888),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            color: const Color(0xFF1A1A1A),
            padding: const EdgeInsets.all(10),
            child: TextFormField(
              controller: _codeCtrl,
              decoration: InputDecoration(
                filled: false,
                hintText: l10n.codeBlockHint,
                hintStyle: const TextStyle(
                  color: Color(0xFF64748B),
                  fontFamily: 'monospace',
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Color(0xFFA8B4C8),
                height: 1.6,
              ),
              maxLines: null,
              onChanged: (v) {
                widget.block.content = v;
                widget.onChanged();
              },
            ),
          ),
          _buildOutput(),
        ],
      ),
    );
  }

  Widget _buildOutput() {
    final content = widget.block.outputContent;
    if (content == null) {
      return Container(height: 0.5, color: const Color(0xFF1E293B));
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Container(
        key: ValueKey('${widget.block.id}-$content'),
        width: double.infinity,
        constraints: const BoxConstraints(maxHeight: 300),
        color: const Color(0xFF111111),
        // html 输出自己就是一个内部可滚动的 WebView，外面不能再套一层
        // SingleChildScrollView——两层滚动区域叠在一起，手势会被内层
        // WebView 吃掉，外层永远收不到
        child: widget.block.outputType == 'html'
            ? SizedBox(
                height: 200,
                child: _renderOutput(content, widget.block.outputType),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(10),
                child: _renderOutput(content, widget.block.outputType),
              ),
      ),
    );
  }

  Widget _renderOutput(String content, String? type) {
    switch (type) {
      case 'image':
        // matplotlib 图表：compiler.js 吐回来的是 base64 图片
        try {
          final base64Data = content.contains(',')
              ? content.split(',').last
              : content;
          return ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.memory(base64Decode(base64Data), fit: BoxFit.contain),
          );
        } catch (e) {
          return Text(
            '图表渲染失败：$e',
            style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 12),
          );
        }

      case 'html':
        // DataFrame 表格这类 HTML 输出
        return InAppWebView(
          initialData: InAppWebViewInitialData(
            data:
                '''
<html>
<head>
<style>
body{font-family:monospace;font-size:11px;margin:0;background:#0a0f1a;color:#e2e8f0}
table{border-collapse:collapse;width:100%}
th,td{border:1px solid #1e293b;padding:4px 8px;text-align:left}
th{background:#1e293b;color:#94a3b8}
</style>
</head>
<body>$content</body>
</html>
''',
          ),
        );

      case 'error':
        return Text(
          content,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: Color(0xFFFCA5A5),
            height: 1.6,
          ),
        );

      case 'info':
        return Text(
          content,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: Color(0xFF94A3B8),
            height: 1.6,
          ),
        );

      default:
        return Text(
          content,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: Color(0xFF4EC9B0),
            height: 1.6,
          ),
        );
    }
  }

  Future<void> _runCode() async {
    setState(() => _running = true);
    List<Map<String, dynamic>> outputs;
    try {
      outputs = await widget.onRunCode(
        widget.block.id,
        widget.block.content,
        widget.block.language ?? 'python',
      );
    } finally {
      if (mounted) setState(() => _running = false);
    }
    if (!mounted) return;

    // 跟 Notebook 同一套过滤规则：调试信息/空文本不展示，取第一条真正
    // 有内容的输出
    String? foundContent;
    String? foundType;
    for (final out in outputs) {
      final type = out['type'] as String? ?? 'text';
      final content = out['content'] as String? ?? '';
      if (['viz-suggestion', 'missing-package', 'debug'].contains(type)) {
        continue;
      }
      if (type == 'text' && content.trim().isEmpty) continue;
      foundContent = content;
      foundType = type;
      break;
    }
    setState(() {
      widget.block.outputContent =
          foundContent ??
          AppLocalizations.of(context)!.runCompleteNoOutputMessage;
      widget.block.outputType = foundType ?? 'text';
    });
    widget.onChanged();
  }

  // 之前这个 block 无论明暗主题都固定用一套奶油黄配色——浅色主题下还好，
  // 深色主题下就会变成一块突兀的亮黄色，跟截图里反馈的"LaTeX 块色彩
  // 不一致"是同一个问题，这里跟着 Theme.of(context).brightness 走
  Widget _buildLatexBlock(AppLocalizations l10n) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 去掉整块填充底色（原来的琥珀/米色 pill），改成我们标准的"中性圆框"：
    // 透明底 + 一圈中性描边，公式本身用正文色渲染，更克制、更一线
    final border = Theme.of(context).dividerColor;
    final mathColor = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final hintColor = isDark ? Colors.white38 : Colors.black38;
    final inputHintColor = isDark ? Colors.white24 : const Color(0xFFC7C7CC);
    final inputTextColor = isDark ? Colors.white54 : Colors.grey;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 0.8),
      ),
      child: Column(
        children: [
          widget.block.content.isNotEmpty
              // Math.tex 不会自动换行/收缩——公式比卡片宽（长积分式/多项
              // 连乘这类）会顶穿右边界，冒出调试态才看得到的"溢出2.4像素"
              // 黄黑警示条。套一层横向 SingleChildScrollView，宽公式改成
              // 左右滑动，不是硬挤爆
              ? SizedBox(
                  width: double.infinity,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Math.tex(
                      widget.block.content.replaceAll(r'$$', '').trim(),
                      textStyle: TextStyle(fontSize: 16, color: mathColor),
                      onErrorFallback: (err) => Text(
                        widget.block.content,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  ),
                )
              : Text(l10n.latexBlockHint, style: TextStyle(color: hintColor)),
          const SizedBox(height: 8),
          TextFormField(
            key: ValueKey('latex_${widget.block.id}_$_textRevision'),
            initialValue: widget.block.content.isNotEmpty
                ? widget.block.content
                : null,
            decoration: InputDecoration(
              filled: false,
              hintText: l10n.latexBlockHint,
              hintStyle: TextStyle(
                fontFamily: 'monospace',
                color: inputHintColor,
                fontSize: 12,
              ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: inputTextColor,
            ),
            onChanged: (v) {
              widget.block.content = v;
              setState(() {});
              widget.onChanged();
            },
          ),
          if (widget.block.outputContent != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.15)
                    : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: border),
              ),
              child: Text(
                widget.block.outputContent!,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: widget.block.outputType == 'info'
                      ? hintColor
                      : (isDark ? Colors.white70 : const Color(0xFF444444)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildImageBlock(AppLocalizations l10n) {
    if (widget.block.imageUrl != null) {
      return Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 80, maxHeight: 400),
              child: Image.network(
                widget.block.imageUrl!,
                fit: BoxFit.cover,
                width: double.infinity,
              ),
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            initialValue: widget.block.caption,
            decoration: InputDecoration(
              filled: false,
              hintText: l10n.imageCaptionHint,
              hintStyle: const TextStyle(
                color: Color(0xFFC7C7CC),
                fontSize: 12,
              ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            style: const TextStyle(fontSize: 12, color: Colors.grey),
            onChanged: (v) {
              widget.block.caption = v;
              widget.onChanged();
            },
          ),
        ],
      );
    }
    // 之前不管明暗主题固定一块浅灰色方块，深色卡片里像是插错了一张白色
    // 便签纸；改成主题感知的虚线"上传区"——虚线边框是这类空态在一线
    // 产品里（Notion/Linear 等）的通用语言，一眼就能认出"这里可以点击/
    // 拖拽上传"，图标也换成跟品牌色一致的圆形色块，不再是孤零零一个灰图标
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final zoneBg = isDark
        ? Theme.of(context).cardColor
        : const Color(0xFFFAFAFA);
    final dashColor = isDark ? Colors.white24 : const Color(0xFFD1D1D6);
    final iconChipBg = isDark
        ? _primary.withValues(alpha: 0.18)
        : const Color(0xFFEEF0FF);
    final hintColor = isDark ? Colors.white54 : const Color(0xFF999999);
    final subHintColor = isDark ? Colors.white30 : const Color(0xFFC7C7CC);

    return GestureDetector(
      onTap: _pickImage,
      child: CustomPaint(
        painter: _DashedRRectPainter(color: dashColor, radius: 12),
        child: Container(
          height: 140,
          width: double.infinity,
          decoration: BoxDecoration(
            color: zoneBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconChipBg,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add_photo_alternate_outlined,
                  color: _primary,
                  size: 22,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                l10n.tapToUploadLabel,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: hintColor,
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  l10n.imageSizeHint,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.5,
                    color: subHintColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: file.name,
          contentType: DioMediaType('image', 'jpeg'),
        ),
      });
      final res = await ref
          .read(apiClientProvider)
          .post('/auth/files/upload', data: formData);
      if (!res.success || res.data == null) return;
      final url = (res.data as Map)['url'] as String?;
      final uploadedId = (res.data as Map)['id'] as String?;
      if (uploadedId != null) widget.onFileUploaded?.call(uploadedId);
      if (url != null && mounted) {
        setState(() => widget.block.imageUrl = url);
        widget.onChanged();
      }
    } catch (e) {
      debugPrint('[image] 上传失败: $e');
    }
  }

  Widget _buildFileBlock(AppLocalizations l10n) {
    final isPro = widget.membership != 'free';

    if (!isPro) {
      return _membershipLockNotice(l10n.fileBlockMembershipLock);
    }

    if (widget.block.fileName != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFBFDBFE)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.insert_drive_file,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.block.fileName!,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1D4ED8),
                    ),
                  ),
                  if (widget.block.fileSize != null)
                    Text(
                      _formatSize(widget.block.fileSize!),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF60A5FA),
                      ),
                    ),
                ],
              ),
            ),
            Tooltip(
              message: l10n.downloadFileTooltip,
              child: const Icon(
                Icons.download_outlined,
                color: Color(0xFF2563EB),
                size: 18,
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: _pickFile,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F7),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE5E5EA)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.upload_file_outlined,
              color: Color(0xFFC7C7CC),
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              l10n.uploadFileLabel,
              style: const TextStyle(fontSize: 13, color: Color(0xFFC7C7CC)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'csv',
        'xlsx',
        'xls',
        'json',
        'xml',
        'pdf',
        'txt',
        'py',
        'ipynb',
      ],
    );
    if (result == null) return;
    final file = result.files.first;
    final bytes = file.bytes ?? await File(file.path!).readAsBytes();

    final maxSize = widget.membership == 'pro_max'
        ? 50 * 1024 * 1024
        : 5 * 1024 * 1024;
    if (bytes.length > maxSize) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.fileSizeExceedsLimit(
                widget.membership == 'pro_max' ? '50MB' : '5MB',
              ),
            ),
          ),
        );
      }
      return;
    }

    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: file.name,
          contentType: DioMediaType('application', 'octet-stream'),
        ),
      });
      final res = await ref
          .read(apiClientProvider)
          .post('/auth/files/upload', data: formData);
      if (!res.success || res.data == null) return;
      final url = (res.data as Map)['url'] as String?;
      final uploadedId = (res.data as Map)['id'] as String?;
      if (uploadedId != null) widget.onFileUploaded?.call(uploadedId);
      if (url != null && mounted) {
        setState(() {
          widget.block.content = url;
          widget.block.fileName = file.name;
          widget.block.fileSize = bytes.length;
          widget.block.fileType = file.extension;
        });
        widget.onChanged();
      }
    } catch (e) {
      debugPrint('[file] 上传失败: $e');
    }
  }

  Widget _buildAudioBlock(AppLocalizations l10n) {
    if (widget.membership == 'free') {
      return _membershipLockNotice(
        l10n.audioBlockMembershipLock,
        color: const Color(0xFFA855F7),
      );
    }

    if (widget.block.fileName != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFDF4FF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE9D5FF)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: Color(0xFFA855F7),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.block.fileName!,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF6B21A8),
                    ),
                  ),
                  Text(
                    l10n.tapToPlayLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFA855F7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: _pickAudio,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFDF4FF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE9D5FF)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.audio_file_outlined,
              color: Color(0xFFA855F7),
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              l10n.uploadAudioLabel,
              style: const TextStyle(fontSize: 13, color: Color(0xFFA855F7)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAudio() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'm4a', 'aac', 'flac'],
    );
    if (result == null) return;
    final file = result.files.first;
    final bytes = file.bytes ?? await File(file.path!).readAsBytes();

    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: file.name,
          contentType: DioMediaType('audio', 'mpeg'),
        ),
      });
      final res = await ref
          .read(apiClientProvider)
          .post('/auth/files/upload', data: formData);
      if (!res.success || res.data == null) return;
      final url = (res.data as Map)['url'] as String?;
      final uploadedId = (res.data as Map)['id'] as String?;
      if (uploadedId != null) widget.onFileUploaded?.call(uploadedId);
      if (url != null && mounted) {
        setState(() {
          widget.block.content = url;
          widget.block.fileName = file.name;
          widget.block.fileSize = bytes.length;
        });
        widget.onChanged();
      }
    } catch (e) {
      debugPrint('[audio] 上传失败: $e');
    }
  }

  Widget _buildVideoBlock(AppLocalizations l10n) {
    if (widget.membership == 'free') {
      return _membershipLockNotice(
        l10n.videoBlockMembershipLock,
        color: const Color(0xFFC2410C),
      );
    }

    return GestureDetector(
      onTap: () async {
        final picker = ImagePicker();
        final file = await picker.pickVideo(
          source: ImageSource.gallery,
          maxDuration: const Duration(minutes: 10),
        );
        if (file == null) return;
        final bytes = await file.readAsBytes();

        // Pro 视频上限 50MB、Pro Max 100MB。Pro 用户超过 50MB → 弹 Pro Max
        // 升级 Sheet（不是干巴巴的报错）；Pro Max 超过 100MB 才是硬上限提示
        final isMax = widget.membership == 'pro_max';
        if (!isMax && bytes.length > 50 * 1024 * 1024) {
          if (mounted) {
            showProUpgradeSheet(context, feature: '上传 50MB 以上视频', proMax: true);
          }
          return;
        }
        if (isMax && bytes.length > 100 * 1024 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.videoSizeExceedsLimit('100MB'))),
            );
          }
          return;
        }

        try {
          final formData = FormData.fromMap({
            'file': MultipartFile.fromBytes(
              bytes,
              filename: file.name,
              contentType: DioMediaType('video', 'mp4'),
            ),
          });
          final res = await ref
              .read(apiClientProvider)
              .post('/auth/files/upload', data: formData);
          if (!res.success || res.data == null) return;
          final url = (res.data as Map)['url'] as String?;
          final uploadedId = (res.data as Map)['id'] as String?;
          if (uploadedId != null) widget.onFileUploaded?.call(uploadedId);
          if (url != null && mounted) {
            setState(() {
              widget.block.content = url;
              widget.block.fileName = file.name;
              widget.block.fileSize = bytes.length;
            });
            widget.onChanged();
          }
        } catch (e) {
          debugPrint('[video] 上传失败: $e');
        }
      },
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Stack(
          children: [
            Center(
              child: widget.block.content.isNotEmpty
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        const Icon(
                          Icons.play_circle_outline,
                          color: Colors.white,
                          size: 44,
                        ),
                        Positioned(
                          bottom: -30,
                          child: Text(
                            widget.block.fileName ?? 'video.mp4',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.videocam_outlined,
                          color: Colors.white54,
                          size: 28,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          l10n.uploadVideoFromGallery,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white54,
                          ),
                        ),
                        Text(
                          l10n.videoSizeHint,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white38,
                          ),
                        ),
                      ],
                    ),
            ),
            // 常驻的 PRO 角标——标记这是会员专属的 block 类型，不是"锁住了
            // 才显示"的状态提示（免费用户走的是上面 free 分支那套完全
            // 不同的锁定提示，走到这里已经是 Pro/Pro Max 用户）
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: _primary,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Text(
                  'PRO',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinkBlock(AppLocalizations l10n) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E5EA)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: Color(0xFFEEF0FF),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(7),
                bottomLeft: Radius.circular(7),
              ),
            ),
            child: const Icon(Icons.link, color: _primary, size: 20),
          ),
          Expanded(
            child: TextFormField(
              initialValue: widget.block.content.isNotEmpty
                  ? widget.block.content
                  : null,
              decoration: const InputDecoration(
                filled: false,
                hintText: 'https://...',
                hintStyle: TextStyle(color: Color(0xFFC7C7CC), fontSize: 13),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 10),
              ),
              style: const TextStyle(fontSize: 13, color: Color(0xFF1C1C1E)),
              keyboardType: TextInputType.url,
              onChanged: (v) {
                widget.block.content = v;
                widget.block.linkUrl = v;
                widget.onChanged();
              },
            ),
          ),
        ],
      ),
    );
  }

  // 简化成单一"引用"样式——左紫线+米白底+斜体，不再有 tip/warning/info
  // 三态切换。variant 字段还留着（对应已发布内容里可能存在的旧数据），
  // 编辑器这边统一按新样式显示，不再往 variant 写除 info 以外的值
  Widget _buildCalloutBlock(AppLocalizations l10n) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark
        ? (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white)
        : const Color(0xFF1A1A1A);

    // 去掉灰色填充底（pill），只留左侧紫色引用线——干净的引用样式
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.transparent,
        border: Border(left: BorderSide(color: _primary, width: 3)),
      ),
      child: TextFormField(
        key: ValueKey('callout_${widget.block.id}_$_textRevision'),
        focusNode: widget.block.focusNode,
        initialValue: widget.block.content.isNotEmpty
            ? widget.block.content
            : null,
        decoration: InputDecoration(
          filled: false,
          hintText: l10n.calloutBlockHint,
          hintStyle: TextStyle(
            fontStyle: FontStyle.italic,
            color: textColor.withValues(alpha: 0.4),
          ),
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        style: TextStyle(
          fontSize: 14,
          fontStyle: FontStyle.italic,
          color: textColor,
          height: 1.6,
        ),
        maxLines: null,
        onChanged: (v) {
          widget.block.content = v;
          widget.onChanged();
        },
      ),
    );
  }

  Widget _membershipLockNotice(
    String message, {
    Color color = const Color(0xFFD97706),
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: TextStyle(fontSize: 13, color: color)),
          ),
        ],
      ),
    );
  }
}

// Flutter 没有内置的虚线边框，图片 block 空态的"上传区"虚线描边靠这个
// 手写 CustomPainter：沿圆角矩形的路径按固定长度切成一段段短划线画
class _DashedRRectPainter extends CustomPainter {
  final Color color;
  final double radius;
  const _DashedRRectPainter({required this.color, required this.radius});

  static const _dashWidth = 5.0;
  static const _dashGap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + _dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + _dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
