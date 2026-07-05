import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/utils/code_highlight.dart';
import '../models/block_model.dart';
import 'block_picker_sheet.dart';

const _primary = Color(0xFF6366F1);

// code block 的语言下拉里特意不放 latex——LaTeX 已经是独立的 block 类型，
// 跟聊天那边"用独立 type='latex' 而不是 type='code'+metadata.language"
// 是同一个道理，两条路径都能表示公式只会互相打架
const _codeLanguages = ['python', 'javascript', 'sql', 'html', 'markdown'];

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
  });

  @override
  ConsumerState<BlockCard> createState() => _BlockCardState();
}

class _BlockCardState extends ConsumerState<BlockCard> {
  bool _running = false;
  bool _focused = false;
  // 代码块专用——用能实时按 token 上色的 controller 替代默认的
  // TextFormField(initialValue: ...)，编辑态才能跟阅读态一样有语法高亮
  late final HighlightingCodeController _codeCtrl = HighlightingCodeController(
    text: widget.block.content,
    language: widget.block.language ?? 'python',
  );

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _focused ? _primary : const Color(0xFFEBEBEB),
          width: _focused ? 1.0 : 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 类型图标+类型名一行，操作按钮（上移/下移/删除/拖拽）放在
          // 同一行右侧——不再是右上角单独飘一组图标，视觉上归属更清楚
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
                if (widget.onMoveUp != null)
                  _actionBtn(Icons.keyboard_arrow_up, widget.onMoveUp!),
                if (widget.onMoveDown != null)
                  _actionBtn(Icons.keyboard_arrow_down, widget.onMoveDown!),
                _actionBtn(Icons.delete_outline, widget.onDelete),
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
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
            child: _buildContent(l10n),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: Icon(icon, size: 16, color: const Color(0xFFDDDDDD)),
    ),
  );

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

  Widget _buildTextBlock(AppLocalizations l10n) => TextFormField(
    initialValue: widget.block.content.isNotEmpty ? widget.block.content : null,
    decoration: InputDecoration(
      filled: false,
      hintText: l10n.textBlockHint,
      hintStyle: const TextStyle(color: Color(0xFFC7C7CC)),
      border: InputBorder.none,
      isDense: true,
      contentPadding: EdgeInsets.zero,
    ),
    style: const TextStyle(fontSize: 14, height: 1.7, color: Color(0xFF1C1C1E)),
    maxLines: null,
    onChanged: (v) {
      widget.block.content = v;
      widget.onChanged();
    },
    onTap: () => setState(() => _focused = true),
    onEditingComplete: () => setState(() => _focused = false),
  );

  Widget _buildHeadingBlock(AppLocalizations l10n) => TextFormField(
    initialValue: widget.block.content.isNotEmpty ? widget.block.content : null,
    decoration: InputDecoration(
      filled: false,
      hintText: l10n.headingBlockHint(widget.block.headingLevel ?? 2),
      hintStyle: const TextStyle(color: Color(0xFFC7C7CC)),
      border: InputBorder.none,
      isDense: true,
      contentPadding: EdgeInsets.zero,
    ),
    style: TextStyle(
      fontSize: widget.block.headingLevel == 2
          ? 20
          : widget.block.headingLevel == 3
          ? 17
          : 15,
      fontWeight: FontWeight.w700,
      color: const Color(0xFF1C1C1E),
    ),
    maxLines: 1,
    onChanged: (v) {
      widget.block.content = v;
      widget.onChanged();
    },
  );

  Widget _buildCodeBlock(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A1A),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(14),
              topRight: Radius.circular(14),
            ),
          ),
          child: Row(
            children: [
              // macOS 窗口三色点装饰，跟阅读态/预览态的代码块保持一致
              const _MacDot(color: Color(0xFFFF5F56)),
              const SizedBox(width: 6),
              const _MacDot(color: Color(0xFFFFBD2E)),
              const SizedBox(width: 6),
              const _MacDot(color: Color(0xFF27C93F)),
              const SizedBox(width: 10),
              DropdownButton<String>(
                value: widget.block.language ?? 'python',
                dropdownColor: const Color(0xFF1A1A1A),
                style: const TextStyle(fontSize: 12, color: Color(0xFFE5E7EB)),
                underline: const SizedBox(),
                isDense: true,
                items: _codeLanguages
                    .map(
                      (l) => DropdownMenuItem(
                        value: l,
                        child: Text(
                          l,
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
              GestureDetector(
                onTap: _running ? null : _runCode,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _running ? Colors.grey : _primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _running ? Icons.hourglass_empty : Icons.play_arrow,
                        size: 13,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        _running ? l10n.runningLabel : l10n.runAction,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
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
    );
  }

  Widget _buildOutput() {
    final content = widget.block.outputContent;
    if (content == null) {
      return Container(height: 0.5, color: const Color(0xFF1E293B));
    }
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 300),
      decoration: const BoxDecoration(
        color: Color(0xFF111111),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(14),
          bottomRight: Radius.circular(14),
        ),
      ),
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
    final bg = isDark ? const Color(0xFF332701) : const Color(0xFFFFFBEB);
    final border = isDark ? const Color(0xFF78350F) : const Color(0xFFFDE68A);
    final mathColor = isDark
        ? const Color(0xFFFCD34D)
        : const Color(0xFF78350F);
    final hintColor = isDark
        ? const Color(0xFFB45309)
        : const Color(0xFFFCD34D);
    final inputHintColor = isDark
        ? const Color(0xFF92702B)
        : const Color(0xFFC7C7CC);
    final inputTextColor = isDark ? const Color(0xFFD1B37A) : Colors.grey;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Column(
        children: [
          widget.block.content.isNotEmpty
              ? Math.tex(
                  widget.block.content.replaceAll(r'$$', '').trim(),
                  textStyle: TextStyle(fontSize: 16, color: mathColor),
                  onErrorFallback: (err) => Text(
                    widget.block.content,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                )
              : Text(l10n.latexBlockHint, style: TextStyle(color: hintColor)),
          const SizedBox(height: 8),
          TextFormField(
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
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          color: const Color(0xFFF8F8F8),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.photo_camera_outlined,
              color: Color(0xFFC7C7CC),
              size: 28,
            ),
            const SizedBox(height: 6),
            Text(
              l10n.tapToUploadLabel,
              style: const TextStyle(fontSize: 13, color: Color(0xFFC7C7CC)),
            ),
            const SizedBox(height: 2),
            Text(
              l10n.imageSizeHint,
              style: const TextStyle(fontSize: 10, color: Color(0xFFE5E5EA)),
            ),
          ],
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

        final maxSize = widget.membership == 'pro_max'
            ? 100 * 1024 * 1024
            : 50 * 1024 * 1024;
        if (bytes.length > maxSize) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  l10n.videoSizeExceedsLimit(
                    widget.membership == 'pro_max' ? '100MB' : '50MB',
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
              contentType: DioMediaType('video', 'mp4'),
            ),
          });
          final res = await ref
              .read(apiClientProvider)
              .post('/auth/files/upload', data: formData);
          if (!res.success || res.data == null) return;
          final url = (res.data as Map)['url'] as String?;
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
    final bg = isDark
        ? Theme.of(context).scaffoldBackgroundColor
        : const Color(0xFFFAFAF8);
    final textColor = isDark
        ? (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white)
        : const Color(0xFF1A1A1A);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        border: const Border(left: BorderSide(color: _primary, width: 3)),
      ),
      child: TextFormField(
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

class _MacDot extends StatelessWidget {
  final Color color;
  const _MacDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
