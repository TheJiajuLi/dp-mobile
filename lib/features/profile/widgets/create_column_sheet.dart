import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_client.dart';
import '../../../core/profile_refresh_signal.dart';
import '../../auth/auth_service.dart';

const _primary = Color(0xFF6366F1);

// 新建专栏底部弹窗（重设计版）：纯色封面快选 + 名称(必填,30字实时计数) +
// 简介 + 领域单选胶囊 + 灰→黑激活的创建按钮。
//
// 后端 columns 接受 {name, description, coverImage}——图片封面会存进
// columns_table.cover_image 并有换/删清理（cleanupColumnCover），所以图片
// 封面走 /auth/files/upload 拿 url → coverImage 落库。为避免"上传了又取消"
// 的孤儿文件，图片只在真正点「创建」时才上传（选图阶段只留本地预览）。
//
// 纯色封面(coverColor, hex)和领域(domain, 中文标签)后端(commit 63d8759)已
// 加列并接收，跟着 name/description/coverImage 一起发即可入库。
class CreateColumnSheet extends ConsumerStatefulWidget {
  final String? profileId;
  final Future<void> Function(String userId) onCreated;
  const CreateColumnSheet({
    super.key,
    required this.profileId,
    required this.onCreated,
  });

  @override
  ConsumerState<CreateColumnSheet> createState() => _CreateColumnSheetState();
}

class _CreateColumnSheetState extends ConsumerState<CreateColumnSheet> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  Color? _coverColor;
  File? _coverImageFile; // 本地预览，创建时才上传
  String? _selectedDomain;
  bool _loading = false;

  static const _coverColors = [
    Color(0xFF6366F1),
    Color(0xFFF59E0B),
    Color(0xFF16A34A),
    Color(0xFFC026D3),
    Color(0xFF2563EB),
    Color(0xFFDC2626),
    Color(0xFF0D9488),
  ];

  static const _domainColors = {
    '数据': Color(0xFF6366F1),
    '编程': Color(0xFF2563EB),
    '科学': Color(0xFFD97706),
    '经济': Color(0xFFDC2626),
    '宇宙': Color(0xFF8B5CF6),
    '生命科学': Color(0xFF16A34A),
    '时事': Color(0xFF555555),
    '生活': Color(0xFFEC4899),
  };

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  // Color → #RRGGBB（后端 cover_color 存 hex 字符串）
  String _hexOf(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (file == null) return;
    setState(() {
      _coverImageFile = File(file.path);
      _coverColor = null; // 图片和纯色互斥
    });
  }

  Future<void> _createColumn() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || _loading) return;
    setState(() => _loading = true);

    // 有图片封面就先上传拿永久 url（只在这一刻上传，取消不会留孤儿）
    String? coverUrl;
    if (_coverImageFile != null) {
      try {
        final bytes = await _coverImageFile!.readAsBytes();
        final form = FormData.fromMap({
          'file': MultipartFile.fromBytes(
            bytes,
            filename: 'column_cover.jpg',
            contentType: DioMediaType('image', 'jpeg'),
          ),
        });
        final up = await ref
            .read(apiClientProvider)
            .post('/auth/files/upload', data: form);
        if (up.success && up.data is Map) {
          coverUrl = (up.data as Map)['url'] as String?;
        }
        if (coverUrl == null) throw Exception('封面上传失败');
      } catch (e) {
        if (!mounted) return;
        setState(() => _loading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('封面上传失败，请重试')));
        return;
      }
    }

    // 后端(commit 63d8759)已接受 coverImage / coverColor(hex) / domain(中文
    // 标签)。封面图片和纯色互斥，前端保证只发其中一个
    final res = await ref
        .read(apiClientProvider)
        .post(
          '/auth/columns',
          data: {
            'name': name,
            'description': _descCtrl.text.trim(),
            if (coverUrl != null) 'coverImage': coverUrl,
            if (_coverColor != null) 'coverColor': _hexOf(_coverColor!),
            if (_selectedDomain != null) 'domain': _selectedDomain,
          },
        );
    if (!mounted) return;
    setState(() => _loading = false);
    if (!res.success) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(res.message ?? '创建失败，请稍后重试')));
      return;
    }
    notifyProfileShouldRefresh(ref);
    Navigator.pop(context);
    final userId = widget.profileId ?? ref.read(currentUserProvider)?.id;
    if (userId != null) await widget.onCreated(userId);
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = _nameCtrl.text.trim().isNotEmpty && !_loading;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE0E0E0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 10, 12),
              child: Row(
                children: [
                  const Text(
                    '新建专栏',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFF888888)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(
              height: 0.5,
              thickness: 0.5,
              color: Color(0xFFF0F0F0),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('封面'),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: _pickImage,
                          child: Container(
                            width: 96,
                            height: 96,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _coverColor ?? const Color(0xFFF5F5F5),
                              borderRadius: BorderRadius.circular(14),
                              image: _coverImageFile != null
                                  ? DecorationImage(
                                      image: FileImage(_coverImageFile!),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                              border:
                                  _coverColor == null && _coverImageFile == null
                                  ? Border.all(
                                      color: const Color(0xFFEBEBEB),
                                      width: 1,
                                    )
                                  : null,
                            ),
                            child: _coverImageFile != null
                                ? null
                                : _coverColor != null
                                ? const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 26,
                                  )
                                : const Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.add_photo_alternate_outlined,
                                        color: Color(0xFFBBBBBB),
                                        size: 24,
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        '上传封面',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Color(0xFFBBBBBB),
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '点左侧上传封面图，或选一个纯色',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[500],
                                  height: 1.6,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _coverColors.map((c) {
                                  final sel = _coverColor == c;
                                  return GestureDetector(
                                    onTap: () => setState(() {
                                      _coverColor = sel ? null : c;
                                      if (!sel) _coverImageFile = null;
                                    }),
                                    child: Container(
                                      width: 30,
                                      height: 30,
                                      decoration: BoxDecoration(
                                        color: c,
                                        borderRadius: BorderRadius.circular(8),
                                        border: sel
                                            ? Border.all(
                                                color: const Color(0xFF1A1A1A),
                                                width: 2,
                                              )
                                            : null,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        _label('专栏名称'),
                        const Text(
                          ' *',
                          style: TextStyle(color: Color(0xFFDC2626)),
                        ),
                        const Spacer(),
                        Text(
                          '${_nameCtrl.text.length}/30',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[400],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _field(
                      _nameCtrl,
                      '给你的专栏起个名字...',
                      maxLength: 30,
                      onChanged: () => setState(() {}),
                    ),
                    const SizedBox(height: 18),
                    _label('简介'),
                    const SizedBox(height: 8),
                    _field(_descCtrl, '介绍一下这个专栏的内容...', maxLines: 3),
                    const SizedBox(height: 18),
                    _label('领域'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _domainColors.keys.map((d) {
                        final color = _domainColors[d]!;
                        final sel = _selectedDomain == d;
                        return GestureDetector(
                          onTap: () =>
                              setState(() => _selectedDomain = sel ? null : d),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(
                                color: sel
                                    ? color
                                    : color.withValues(alpha: 0.2),
                                width: sel ? 1.5 : 0.5,
                              ),
                            ),
                            child: Text(
                              d,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: color,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(
              height: 0.5,
              thickness: 0.5,
              color: Color(0xFFF0F0F0),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                MediaQuery.of(context).padding.bottom + 12,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          '取消',
                          style: TextStyle(
                            fontSize: 15,
                            color: Color(0xFF888888),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: canCreate ? _createColumn : null,
                      child: Container(
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: canCreate
                              ? const Color(0xFF1A1A1A)
                              : const Color(0xFFE0E0E0),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                '创建专栏',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: canCreate
                                      ? Colors.white
                                      : Colors.grey[500],
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: Color(0xFF1A1A1A),
    ),
  );

  Widget _field(
    TextEditingController ctrl,
    String hint, {
    int maxLines = 1,
    int? maxLength,
    VoidCallback? onChanged,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      maxLength: maxLength,
      onChanged: onChanged == null ? null : (_) => onChanged(),
      style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A1A)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFBBBBBB), fontSize: 14),
        filled: true,
        fillColor: const Color(0xFFF8F8F6),
        counterText: '',
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFEBEBEB), width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFEBEBEB), width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _primary, width: 1),
        ),
      ),
    );
  }
}
