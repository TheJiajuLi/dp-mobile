import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/models/user_model.dart';
import '../../../shared/widgets/zodiac_icon.dart';
import '../../auth/auth_service.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  static const _primary = Color(0xFF6366F1);

  final _usernameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _linkCtrls = <TextEditingController>[];

  String _zodiac = '';
  bool _saving = false;
  bool _loaded = false;
  bool _uploadingAvatar = false;
  String? _error;
  UserModel? _user;

  @override
  void initState() {
    super.initState();
    _loadCurrentData();
  }

  Future<void> _loadCurrentData() async {
    _user = ref.read(currentUserProvider);
    final userId = _user?.id ?? '';
    final prefs = await SharedPreferences.getInstance();

    _usernameCtrl.text = _user?.username ?? '';
    _bioCtrl.text = _user?.bio ?? '';
    _zodiac = prefs.getString('${userId}_zodiac') ?? '';

    final linksJson = prefs.getString('${userId}_links') ?? '[]';
    final links = List<String>.from(jsonDecode(linksJson) as List);

    // 本地还没存过链接，但后端账号本身有 website，先带出来
    if (links.isEmpty && (_user?.website?.isNotEmpty ?? false)) {
      links.add(_user!.website!);
    }

    for (final l in links) {
      _linkCtrls.add(TextEditingController(text: l));
    }
    if (_linkCtrls.isEmpty) {
      _linkCtrls.add(TextEditingController());
    }
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _save() async {
    final username = _usernameCtrl.text.trim();
    final bio = _bioCtrl.text.trim();
    if (username.isEmpty) {
      setState(() => _error = '用户名不能为空');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final userId = _user?.id ?? '';
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString('${userId}_zodiac', _zodiac);

      final links = _linkCtrls
          .map((c) => c.text.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      await prefs.setString('${userId}_links', jsonEncode(links));

      final website = links.isNotEmpty ? links.first : '';
      // ApiClient 内部已经把 DioException 兜住了，不会抛异常，
      // 失败与否要靠 res.success 判断，不能指望 try/catch 抓到网络层错误
      final res = await ref.read(apiClientProvider).patch(
        '/auth/me',
        data: {'username': username, 'bio': bio, 'website': website},
      );
      if (!res.success) {
        throw Exception(res.message ?? '保存失败，请重试');
      }

      final updated = (_user ?? UserModel(id: userId, username: username, email: ''))
          .copyWith(username: username, bio: bio, website: website);
      ref.read(authServiceProvider).updateCurrentUser(updated);

      if (mounted) context.pop();
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAndUploadAvatar(ImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (file == null) return;

    final bytes = await file.readAsBytes();

    setState(() => _uploadingAvatar = true);

    try {
      final formData = FormData.fromMap({
        'avatar': MultipartFile.fromBytes(
          bytes,
          filename: 'avatar.jpg',
          contentType: DioMediaType('image', 'jpeg'),
        ),
      });

      // ApiClient.post 内部吞掉了 DioException，不会抛异常——失败与否
      // 要看 res.success，不能只靠 try/catch
      final res = await ref
          .read(apiClientProvider)
          .post('/auth/update-avatar', data: formData);
      if (!res.success) {
        throw Exception(res.message ?? '上传失败，请重试');
      }

      final newAvatar = (res.data as Map)['avatar'] as String?;
      if (newAvatar != null && _user != null) {
        final updated = _user!.copyWith(avatar: newAvatar);
        ref.read(authServiceProvider).updateCurrentUser(updated);
        setState(() => _user = updated);
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('头像已更新')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('上传失败：${e.toString().replaceAll('Exception: ', '')}')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  void _addLink() {
    if (_linkCtrls.length >= 3) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('最多添加3条链接')));
      return;
    }
    setState(() => _linkCtrls.add(TextEditingController()));
  }

  void _removeLink(int index) {
    setState(() {
      _linkCtrls[index].dispose();
      _linkCtrls.removeAt(index);
    });
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _bioCtrl.dispose();
    for (final c in _linkCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      body: SafeArea(
        child: !_loaded
            ? const Center(child: CircularProgressIndicator(color: _primary))
            : Column(
                children: [
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => context.pop(),
                          child: const Text(
                            '取消',
                            style: TextStyle(fontSize: 15, color: Colors.grey),
                          ),
                        ),
                        const Expanded(
                          child: Text(
                            '编辑资料',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: _saving ? null : _save,
                          child: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: _primary,
                                  ),
                                )
                              : const Text(
                                  '保存',
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: _primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          Container(
                            color: Colors.white,
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              children: [
                                GestureDetector(
                                  onTap: _showAvatarOptions,
                                  child: Stack(
                                    children: [
                                      _buildAvatarPreview(),
                                      Positioned(
                                        bottom: 0,
                                        right: 0,
                                        child: Container(
                                          width: 28,
                                          height: 28,
                                          decoration: BoxDecoration(
                                            color: _primary,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 2,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.camera_alt,
                                            color: Colors.white,
                                            size: 14,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  '更换头像',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: _primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),

                          _section('基本信息', [
                            _inputRow('用户名', _usernameCtrl, '你的用户名'),
                            _inputRow('个人简介', _bioCtrl, '介绍一下自己', maxLines: 3),
                          ]),
                          const SizedBox(height: 8),

                          Container(
                            color: Colors.white,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
                                  child: Text(
                                    '星座',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: ZodiacPicker(
                                    selected: _zodiac.isNotEmpty
                                        ? ZodiacSign.values.firstWhere(
                                            (z) => z.name == _zodiac,
                                            orElse: () => ZodiacSign.aries,
                                          )
                                        : null,
                                    onSelected: (sign) =>
                                        setState(() => _zodiac = sign.name),
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),

                          Container(
                            color: Colors.white,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    14,
                                    16,
                                    4,
                                  ),
                                  child: Row(
                                    children: [
                                      const Text(
                                        '个人链接',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        '最多3条',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[400],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                ..._linkCtrls.asMap().entries.map(
                                  (e) => _linkRow(e.key, e.value),
                                ),
                                if (_linkCtrls.length < 3)
                                  GestureDetector(
                                    onTap: _addLink,
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.add_circle_outline,
                                            color: _primary,
                                            size: 20,
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            '添加链接',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: _primary,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 8),
                              ],
                            ),
                          ),

                          if (_error != null)
                            Container(
                              margin: const EdgeInsets.all(16),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFFFECACA),
                                ),
                              ),
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  color: Color(0xFFDC2626),
                                  fontSize: 14,
                                ),
                              ),
                            ),

                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildAvatarPreview() {
    return Stack(
      alignment: Alignment.center,
      children: [
        _buildAvatarImage(),
        if (_uploadingAvatar)
          const CircleAvatar(
            radius: 45,
            backgroundColor: Colors.black45,
            child: CircularProgressIndicator(color: Colors.white),
          ),
      ],
    );
  }

  Widget _buildAvatarImage() {
    final avatar = _user?.avatar;
    if (avatar != null && avatar.isNotEmpty) {
      if (avatar.startsWith('data:image')) {
        try {
          final base64Data = avatar.split(',').last;
          return CircleAvatar(
            radius: 45,
            backgroundImage: MemoryImage(base64Decode(base64Data)),
          );
        } catch (_) {
          // 解码失败落到下面的首字母占位
        }
      } else {
        return CircleAvatar(
          radius: 45,
          backgroundImage: CachedNetworkImageProvider(avatar),
        );
      }
    }
    return CircleAvatar(
      radius: 45,
      backgroundColor: _primary,
      child: Text(
        (_usernameCtrl.text.isNotEmpty ? _usernameCtrl.text[0] : '?')
            .toUpperCase(),
        style: const TextStyle(
          fontSize: 34,
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> rows) {
    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
                letterSpacing: 0.5,
              ),
            ),
          ),
          ...rows,
        ],
      ),
    );
  }

  Widget _inputRow(
    String label,
    TextEditingController ctrl,
    String hint, {
    int maxLines = 1,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF5F5F5))),
      ),
      child: Row(
        crossAxisAlignment: maxLines > 1
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ),
          Expanded(
            child: TextField(
              controller: ctrl,
              maxLines: maxLines,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: Color(0xFFC7C7CC)),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: const TextStyle(fontSize: 15, color: Color(0xFF1C1C1E)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _linkRow(int idx, TextEditingController ctrl) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF5F5F5))),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.link, size: 16, color: Colors.grey),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: ctrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: 'https://...',
                hintStyle: TextStyle(color: Color(0xFFC7C7CC)),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: const TextStyle(fontSize: 14, color: Color(0xFF1C1C1E)),
            ),
          ),
          GestureDetector(
            onTap: () => _removeLink(idx),
            child: Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(
                color: Color(0xFFFEF2F2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 14, color: Color(0xFFDC2626)),
            ),
          ),
        ],
      ),
    );
  }

  void _showAvatarOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('从相册选择'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUploadAvatar(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('拍照'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUploadAvatar(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }
}
