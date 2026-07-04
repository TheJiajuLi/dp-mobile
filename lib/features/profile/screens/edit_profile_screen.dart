import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/models/user_model.dart';
import '../../../shared/utils/avatar_upload.dart';
import '../../../shared/widgets/zodiac_icon.dart';
import '../../auth/auth_service.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  static const _primary = Color(0xFF6366F1);
  static const _chevronColor = Color(0xFFC7C7CC);

  final _usernameCtrl = TextEditingController();
  final _handleCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _linkCtrls = <TextEditingController>[];

  String? _handle;
  DateTime? _birthday;
  String? _selectedGender;
  bool _saving = false;
  bool _loaded = false;
  bool _uploadingAvatar = false;
  String? _error;
  UserModel? _user;

  ZodiacSign? get _zodiacSign => _birthday == null
      ? null
      : ZodiacSignExt.fromBirthday(_birthday!.month, _birthday!.day);

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
    _selectedGender = _user?.gender;
    _locationCtrl.text = _user?.location ?? '';

    // 生日/星座优先读后端字段；后端还没这两个字段之前，退回读本地
    // legacy key（上一版编辑资料页存的），保存成功一次后就迁移过去了
    final backendBirthday = _user?.birthday;
    if (backendBirthday != null && backendBirthday.isNotEmpty) {
      _birthday = DateTime.tryParse(backendBirthday);
    } else {
      final legacyBirthday = prefs.getString('${userId}_birthday');
      _birthday = legacyBirthday != null ? DateTime.tryParse(legacyBirthday) : null;
    }

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

    // handle（@用户名）不在 currentUserProvider 里，得单独拉一次自己的主页资料
    if (_user != null) {
      final res = await ref
          .read(apiClientProvider)
          .get('/auth/users/profile/${_user!.username}');
      if (res.success && res.data != null) {
        _handle = (res.data as Map)['handle']?.toString();
        _handleCtrl.text = _handle != null ? '@$_handle' : '';
      }
    }

    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _save() async {
    final username = _usernameCtrl.text.trim();
    final bio = _bioCtrl.text.trim();
    if (username.isEmpty) {
      setState(() => _error = '昵称不能为空');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final userId = _user?.id ?? '';
      final prefs = await SharedPreferences.getInstance();

      final links = _linkCtrls
          .map((c) => c.text.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      await prefs.setString('${userId}_links', jsonEncode(links));

      final website = links.isNotEmpty ? links.first : '';
      final birthdayStr = _birthday == null
          ? null
          : '${_birthday!.year}-${_birthday!.month.toString().padLeft(2, '0')}-'
                '${_birthday!.day.toString().padLeft(2, '0')}';

      // ApiClient 内部已经把 DioException 兜住了，不会抛异常，
      // 失败与否要靠 res.success 判断，不能指望 try/catch 抓到网络层错误
      //
      // 注意：截至写这段代码时实测 /auth/me 还不认 gender/location/
      // birthday/zodiac 这4个字段（后端会静默丢弃，不会报错）——后端加完
      // 字段前这几项保存了也拿不回来，App重启会看起来"又没了"
      final res = await ref.read(apiClientProvider).patch(
        '/auth/me',
        data: {
          'username': username,
          'bio': bio,
          'website': website,
          'gender': _selectedGender,
          'location': _locationCtrl.text.trim(),
          'birthday': birthdayStr,
          'zodiac': _zodiacSign?.name,
        },
      );
      if (!res.success) {
        throw Exception(res.message ?? '保存失败，请重试');
      }

      // 后端字段接上之后，本地 legacy key 就不再是唯一真源了，清掉避免
      // 以后跟后端数据打架
      await prefs.remove('${userId}_birthday');
      await prefs.remove('${userId}_zodiac');

      // handle 改名是独立接口，且有30天频率限制——失败不应该回滚上面
      // 已经保存成功的昵称/简介，只用 SnackBar 单独提示
      final newHandle = _handleCtrl.text.trim().replaceFirst('@', '');
      if (newHandle.isNotEmpty && newHandle != _handle) {
        final handleRes = await ref
            .read(apiClientProvider)
            .put('/auth/users/handle', data: {'handle': newHandle});
        if (!handleRes.success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('用户名未更新：${handleRes.message ?? "请稍后再试"}'),
            ),
          );
        }
      }

      final updated = (_user ?? UserModel(id: userId, username: username, email: ''))
          .copyWith(
            username: username,
            bio: bio,
            website: website,
            gender: _selectedGender,
            location: _locationCtrl.text.trim(),
            birthday: birthdayStr,
            zodiac: _zodiacSign?.name,
          );
      ref.read(authServiceProvider).updateCurrentUser(updated);

      if (mounted) context.pop();
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAndUploadAvatar(ImageSource source) async {
    setState(() => _uploadingAvatar = true);
    try {
      final newAvatar = await pickAndUploadAvatar(ref, source);
      if (newAvatar != null && _user != null) {
        final updated = _user!.copyWith(avatar: newAvatar);
        ref.read(authServiceProvider).updateCurrentUser(updated);
        setState(() => _user = updated);
      }

      if (mounted && newAvatar != null) {
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

  void _showBirthdayPicker() {
    var temp = _birthday ?? DateTime(2000, 1, 1);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final sign = ZodiacSignExt.fromBirthday(temp.month, temp.day);
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(ctx).cardColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(ctx),
                          child: const Text(
                            '取消',
                            style: TextStyle(fontSize: 15, color: Colors.grey),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '选择生日',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(ctx).textTheme.bodyLarge?.color,
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () {
                            setState(() => _birthday = temp);
                            Navigator.pop(ctx);
                          },
                          child: const Text(
                            '完成',
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
                  Divider(height: 1, color: Theme.of(ctx).dividerColor),
                  SizedBox(
                    height: 216,
                    child: CupertinoTheme(
                      data: CupertinoThemeData(
                        brightness: Theme.of(ctx).brightness,
                      ),
                      child: CupertinoDatePicker(
                        mode: CupertinoDatePickerMode.date,
                        initialDateTime: temp,
                        maximumDate: DateTime.now(),
                        minimumDate: DateTime(1930),
                        onDateTimeChanged: (d) => setSheetState(() => temp = d),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20, top: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ZodiacIcon(sign: sign, size: 18),
                        const SizedBox(width: 4),
                        Text(
                          sign.chineseName,
                          style: const TextStyle(fontSize: 13, color: _primary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _handleCtrl.dispose();
    _bioCtrl.dispose();
    _locationCtrl.dispose();
    for (final c in _linkCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: !_loaded
            ? const Center(child: CircularProgressIndicator(color: _primary))
            : Column(
                children: [
                  Container(
                    color: Theme.of(context).cardColor,
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
                        Expanded(
                          child: Text(
                            '编辑资料',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).textTheme.bodyLarge?.color,
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
                      child: Container(
                        color: Theme.of(context).cardColor,
                        child: Column(
                          children: [
                            const SizedBox(height: 20),
                            GestureDetector(
                              onTap: _showAvatarOptions,
                              child: Stack(
                                children: [
                                  _buildAvatarPreview(),
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.45),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Theme.of(context).cardColor,
                                          width: 2,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.camera_alt,
                                        color: Colors.white,
                                        size: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              '点击更换头像',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            const SizedBox(height: 20),
                            Divider(
                              height: 1,
                              thickness: 0.5,
                              color: Theme.of(context).dividerColor,
                            ),

                            // 基本信息
                            _textFieldRow('昵称', _usernameCtrl, '你的昵称'),
                            _textFieldRow(
                              '用户名',
                              _handleCtrl,
                              '@设置你的用户名',
                            ),
                            _bioRow(),
                            Divider(
                              height: 1,
                              thickness: 0.5,
                              color: Theme.of(context).dividerColor,
                            ),

                            // 个人信息
                            _formRow(
                              label: '性别',
                              showChevron: false,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: ['男', '女', '保密'].map((g) {
                                  final selected = _selectedGender == g;
                                  return GestureDetector(
                                    onTap: () =>
                                        setState(() => _selectedGender = g),
                                    child: Container(
                                      margin: const EdgeInsets.only(left: 8),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? const Color(0xFFEEF0FF)
                                            : Theme.of(
                                                context,
                                              ).inputDecorationTheme.fillColor,
                                        borderRadius: BorderRadius.circular(99),
                                        border: Border.all(
                                          color: selected
                                              ? _primary
                                              : Colors.transparent,
                                        ),
                                      ),
                                      child: Text(
                                        g,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: selected
                                              ? _primary
                                              : Theme.of(
                                                  context,
                                                ).textTheme.bodySmall?.color,
                                          fontWeight: selected
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                            _textFieldRow('所在地', _locationCtrl, '城市或地区'),
                            _formRow(
                              label: '生日',
                              onTap: _showBirthdayPicker,
                              child: _birthday == null
                                  ? Text(
                                      '请选择',
                                      style: TextStyle(
                                        fontSize: 15,
                                        color: Theme.of(
                                          context,
                                        ).textTheme.bodySmall?.color,
                                      ),
                                    )
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '${_birthday!.year}年${_birthday!.month}月${_birthday!.day}日',
                                          style: TextStyle(
                                            fontSize: 15,
                                            color: Theme.of(
                                              context,
                                            ).textTheme.bodyLarge?.color,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        ZodiacIcon(sign: _zodiacSign!, size: 18),
                                        const SizedBox(width: 4),
                                        Text(
                                          _zodiacSign!.chineseName,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: _primary,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                            Divider(
                              height: 1,
                              thickness: 0.5,
                              color: Theme.of(context).dividerColor,
                            ),

                            // 个人链接
                            ..._linkCtrls.asMap().entries.map(
                              (e) => _linkRow(e.key, e.value),
                            ),
                            if (_linkCtrls.length < 3)
                              GestureDetector(
                                onTap: _addLink,
                                child: Container(
                                  height: 52,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          color: Theme.of(
                                            context,
                                          ).inputDecorationTheme.fillColor,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Icon(
                                          Icons.add,
                                          color: _primary,
                                          size: 16,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      const Text(
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
                            Divider(
                              height: 1,
                              thickness: 0.5,
                              color: Theme.of(context).dividerColor,
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

                            const SizedBox(height: 24),
                            GestureDetector(
                              onTap: () => context.push('/settings/security'),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Text(
                                  '注销账号',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFFDC2626),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
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
            radius: 38,
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
            radius: 38,
            backgroundImage: MemoryImage(base64Decode(base64Data)),
          );
        } catch (_) {
          // 解码失败落到下面的首字母占位
        }
      } else {
        return CircleAvatar(
          radius: 38,
          backgroundImage: CachedNetworkImageProvider(avatar),
        );
      }
    }
    return CircleAvatar(
      radius: 38,
      backgroundColor: _primary,
      child: Text(
        (_usernameCtrl.text.isNotEmpty ? _usernameCtrl.text[0] : '?')
            .toUpperCase(),
        style: const TextStyle(
          fontSize: 28,
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // 通用表单行：左边固定宽度 label，右边内容右对齐，末尾一个装饰性 chevron
  Widget _formRow({
    required String label,
    required Widget child,
    VoidCallback? onTap,
    bool showChevron = true,
  }) {
    final row = Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
          ),
          Expanded(child: Align(alignment: Alignment.centerRight, child: child)),
          if (showChevron) ...[
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: _chevronColor, size: 18),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: row,
    );
  }

  Widget _textFieldRow(String label, TextEditingController ctrl, String hint) {
    return _formRow(
      label: label,
      child: TextField(
        controller: ctrl,
        textAlign: TextAlign.right,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFFC7C7CC), fontSize: 15),
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        style: TextStyle(
          fontSize: 15,
          color: Theme.of(context).textTheme.bodyLarge?.color,
        ),
      ),
    );
  }

  // 简介允许多行，行高不能锁死在 52，跟其它单行字段区分开
  Widget _bioRow() {
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              '简介',
              style: TextStyle(
                fontSize: 15,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: _bioCtrl,
              maxLines: 3,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                hintText: '介绍一下自己',
                hintStyle: TextStyle(color: Color(0xFFC7C7CC), fontSize: 15),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: TextStyle(
                fontSize: 15,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _linkRow(int idx, TextEditingController ctrl) {
    // github 链接给个更贴题的图标，其它一律用通用的地球图标——
    // 没有品牌图标资源，用 Material 内置图标凑一个大致区分度
    final isGithub = ctrl.text.contains('github.com');
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Theme.of(context).inputDecorationTheme.fillColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isGithub ? Icons.code : Icons.public,
              size: 15,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: ctrl,
              keyboardType: TextInputType.url,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'https://...',
                hintStyle: TextStyle(color: Color(0xFFC7C7CC), fontSize: 14),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _removeLink(idx),
            child: Icon(
              Icons.close,
              size: 16,
              color: Theme.of(context).textTheme.bodySmall?.color,
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
        decoration: BoxDecoration(
          color: Theme.of(ctx).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
