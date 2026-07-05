import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/generated/app_localizations.dart';
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

  Color get _typeColor {
    switch (widget.block.type) {
      case BlockType.code:
        return const Color(0xFF0F172A);
      case BlockType.latex:
        return const Color(0xFFFEF3C7);
      case BlockType.image:
        return const Color(0xFFECFDF5);
      case BlockType.file:
        return const Color(0xFFEFF6FF);
      case BlockType.audio:
        return const Color(0xFFFDF4FF);
      case BlockType.video:
        return const Color(0xFFFFF7ED);
      case BlockType.link:
        return const Color(0xFFF0FDF4);
      default:
        return Colors.white;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _focused ? _primary : const Color(0xFFE5E5EA),
          width: _focused ? 1.0 : 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _typeColor,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    blockTypeLabel(l10n, widget.block.type),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: widget.block.type == BlockType.code
                          ? const Color(0xFFA5F3FC)
                          : Colors.grey[700],
                    ),
                  ),
                ),
                const Spacer(),
                if (widget.onMoveUp != null)
                  _actionBtn(Icons.keyboard_arrow_up, widget.onMoveUp!),
                if (widget.onMoveDown != null)
                  _actionBtn(Icons.keyboard_arrow_down, widget.onMoveDown!),
                _actionBtn(
                  Icons.delete_outline,
                  widget.onDelete,
                  color: const Color(0xFFDC2626),
                ),
                const Icon(Icons.drag_handle, size: 18, color: Colors.grey),
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

  Widget _actionBtn(IconData icon, VoidCallback onTap, {Color? color}) =>
      GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 16, color: color ?? Colors.grey),
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
            color: Color(0xFF1A1A2E),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(8),
              topRight: Radius.circular(8),
            ),
          ),
          child: Row(
            children: [
              DropdownButton<String>(
                value: widget.block.language ?? 'python',
                dropdownColor: const Color(0xFF1A1A2E),
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
                onChanged: (v) => setState(() => widget.block.language = v),
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
                    borderRadius: BorderRadius.circular(5),
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
          color: const Color(0xFF0F172A),
          padding: const EdgeInsets.all(10),
          child: TextFormField(
            initialValue: widget.block.content.isNotEmpty
                ? widget.block.content
                : null,
            decoration: InputDecoration(
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
              fontSize: 13,
              color: Color(0xFFE2E8F0),
              height: 1.6,
            ),
            maxLines: null,
            onChanged: (v) {
              widget.block.content = v;
              widget.onChanged();
            },
          ),
        ),
        if (widget.block.outputContent != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: const BoxDecoration(
              color: Color(0xFF0A0F1A),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(8),
                bottomRight: Radius.circular(8),
              ),
            ),
            child: SingleChildScrollView(
              child: widget.block.outputType == 'image'
                  ? Image.network(
                      widget.block.outputContent!,
                      fit: BoxFit.contain,
                    )
                  : Text(
                      widget.block.outputContent!,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.6,
                        color: widget.block.outputType == 'error'
                            ? const Color(0xFFFCA5A5)
                            : const Color(0xFF4ADE80),
                      ),
                    ),
            ),
          )
        else
          Container(height: 0.5, color: const Color(0xFF1E293B)),
      ],
    );
  }

  // 目前是模拟执行——真正接 Pyodide 需要复用 Notebook 那套隐藏 WebView
  // 引擎（notebook_editor_screen.dart 里的 _webCtrl/compiler.js），那套
  // 状态机跟 Notebook 页面自身深度绑定，不是简单抽出来就能用，属于单独
  // 的后续工作，这次先把编辑器本身的交互跑通
  Future<void> _runCode() async {
    setState(() => _running = true);
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() {
      _running = false;
      widget.block.outputContent = AppLocalizations.of(
        context,
      )!.runCompleteNoOutputMessage;
      widget.block.outputType = 'text';
    });
    widget.onChanged();
  }

  Widget _buildLatexBlock(AppLocalizations l10n) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFFBEB),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFFDE68A)),
    ),
    child: Column(
      children: [
        widget.block.content.isNotEmpty
            ? Math.tex(
                widget.block.content.replaceAll(r'$$', '').trim(),
                textStyle: const TextStyle(
                  fontSize: 16,
                  color: Color(0xFF78350F),
                ),
                onErrorFallback: (err) => Text(
                  widget.block.content,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              )
            : Text(
                l10n.latexBlockHint,
                style: const TextStyle(color: Color(0xFFFCD34D)),
              ),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: widget.block.content.isNotEmpty
              ? widget.block.content
              : null,
          decoration: InputDecoration(
            hintText: l10n.latexBlockHint,
            hintStyle: const TextStyle(
              fontFamily: 'monospace',
              color: Color(0xFFC7C7CC),
              fontSize: 12,
            ),
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: Colors.grey,
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
        height: 120,
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F7),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE5E5EA)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.cloud_upload_outlined,
              color: Color(0xFFC7C7CC),
              size: 28,
            ),
            const SizedBox(height: 6),
            Text(
              l10n.uploadImageFromGallery,
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
        height: 120,
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(8),
        ),
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
                    bottom: 8,
                    right: 8,
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
                    style: const TextStyle(fontSize: 13, color: Colors.white54),
                  ),
                  Text(
                    l10n.videoSizeHint,
                    style: const TextStyle(fontSize: 10, color: Colors.white38),
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

  Widget _buildCalloutBlock(AppLocalizations l10n) {
    final bgColors = {
      'tip': const Color(0xFFE8F8F0),
      'warning': const Color(0xFFFFF7E6),
      'info': const Color(0xFFEEF0FF),
    };
    final textColors = {
      'tip': const Color(0xFF16A34A),
      'warning': const Color(0xFFD97706),
      'info': const Color(0xFF4F46E5),
    };
    final variantLabels = {
      'tip': l10n.calloutVariantTip,
      'warning': l10n.calloutVariantWarning,
      'info': l10n.calloutVariantInfo,
    };
    final variant = widget.block.variant ?? 'info';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColors[variant],
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: textColors[variant]!, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: ['tip', 'warning', 'info'].map((v) {
              final selected = variant == v;
              return GestureDetector(
                onTap: () {
                  setState(() => widget.block.variant = v);
                  widget.onChanged();
                },
                child: Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? textColors[v] : Colors.white,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: textColors[v]!),
                  ),
                  child: Text(
                    variantLabels[v]!,
                    style: TextStyle(
                      fontSize: 11,
                      color: selected ? Colors.white : textColors[v],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: widget.block.content.isNotEmpty
                ? widget.block.content
                : null,
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            style: TextStyle(
              fontSize: 14,
              color: textColors[variant],
              height: 1.5,
            ),
            maxLines: null,
            onChanged: (v) {
              widget.block.content = v;
              widget.onChanged();
            },
          ),
        ],
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
