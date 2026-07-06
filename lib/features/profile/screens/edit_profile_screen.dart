import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/models/user_model.dart';
import '../../../shared/utils/avatar_upload.dart';
import '../../../shared/utils/gender_label.dart';
import '../../../shared/widgets/interest_tag.dart';
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
  List<String> _tags = [];

  ZodiacSign? get _zodiacSign => _birthday == null
      ? null
      : ZodiacSignExt.fromBirthday(_birthday!.month, _birthday!.day);

  @override
  void initState() {
    super.initState();
    _loadCurrentData();
  }

  // 实测（2026-07-04）：提交生日 "1999-03-21" 给 /auth/me，GET 回来的是
  // "1999-03-20T16:00:00.000Z"——后端把这个日期字符串当成服务器本地时区
  // （腾讯云香港服务器，UTC+8，见 CONTEXT.md）解析再转存成 UTC，直接用
  // DateTime.parse 的 UTC 年月日会读成少一天。这里按 +8 小时纠正回来，
  // 前提是后端服务器时区不变——如果后端以后改成存纯日期（不带时区），
  // 这个纠正就要删掉
  DateTime? _parseBackendBirthday(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return null;
    return parsed.toUtc().add(const Duration(hours: 8));
  }

  Future<void> _loadCurrentData() async {
    _user = ref.read(currentUserProvider);
    final userId = _user?.id ?? '';
    final prefs = await SharedPreferences.getInstance();

    _usernameCtrl.text = _user?.username ?? '';
    _bioCtrl.text = _user?.bio ?? '';
    _selectedGender = _user?.gender;
    _locationCtrl.text = _user?.location ?? '';
    _tags = List.of(_user?.tags ?? []);

    // 生日/星座优先读后端字段；后端还没这两个字段之前，退回读本地
    // legacy key（上一版编辑资料页存的），保存成功一次后就迁移过去了
    final backendBirthday = _user?.birthday;
    if (backendBirthday != null && backendBirthday.isNotEmpty) {
      _birthday = _parseBackendBirthday(backendBirthday);
    } else {
      final legacyBirthday = prefs.getString('${userId}_birthday');
      _birthday = legacyBirthday != null
          ? DateTime.tryParse(legacyBirthday)
          : null;
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
    final l10n = AppLocalizations.of(context)!;
    final username = _usernameCtrl.text.trim();
    final bio = _bioCtrl.text.trim();
    if (username.isEmpty) {
      setState(() => _error = l10n.nicknameRequired);
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
      // 2026-07-04 实测：gender/location/birthday/zodiac 后端已经接上了，
      // PATCH /auth/me 会返回完整的 {message, user:{...这4个字段也在...}}
      final res = await ref
          .read(apiClientProvider)
          .patch(
            '/auth/me',
            data: {
              'username': username,
              'bio': bio,
              'website': website,
              'gender': _selectedGender,
              'location': _locationCtrl.text.trim(),
              'birthday': birthdayStr,
              'zodiac': _zodiacSign?.name,
              'tags': _tags,
            },
          );
      if (!res.success) {
        throw Exception(res.message ?? l10n.saveFailedRetry);
      }

      // legacy 本地 key 只是后端字段上线前的过渡存储，保存成功一次之后
      // 就不再需要，清掉避免以后跟后端数据打架
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
              content: Text(
                l10n.usernameNotUpdatedWithReason(
                  handleRes.message ?? l10n.pleaseTryAgainLater,
                ),
              ),
            ),
          );
        }
      }

      // 优先用后端在这次 PATCH 响应里直接回显的 user 数据，避免本地状态跟
      // 后端各自维护、慢慢产生分歧——但只挑我们关心的这几个字段用
      // .copyWith 叠加在原有 _user 上，不整个替换：这个接口的响应里没有
      // email/created_at，直接 UserModel.fromJson(resUser) 会把 email
      // 冲成空字符串。birthday 也不用回显值——后端把日期字符串当服务器
      // 本地时区（UTC+8）解析再转存成UTC，回显值直接解析会差一天（见
      // _parseBackendBirthday 的注释），这里已经有刚选好的本地
      // _birthday，没必要冒这个时区的险去读后端回显值
      final resUser = res.data is Map ? res.data['user'] : null;
      final base =
          _user ?? UserModel(id: userId, username: username, email: '');
      final updated = resUser is Map
          ? base.copyWith(
              username: resUser['username']?.toString() ?? username,
              bio: resUser['bio']?.toString() ?? bio,
              website: resUser['website']?.toString() ?? website,
              gender: resUser['gender']?.toString(),
              location: resUser['location']?.toString(),
              zodiac: resUser['zodiac']?.toString(),
              birthday: birthdayStr,
              tags:
                  (resUser['tags'] as List?)
                      ?.map((e) => e.toString())
                      .toList() ??
                  _tags,
            )
          : base.copyWith(
              username: username,
              bio: bio,
              website: website,
              gender: _selectedGender,
              location: _locationCtrl.text.trim(),
              birthday: birthdayStr,
              zodiac: _zodiacSign?.name,
              tags: _tags,
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
        // /auth/update-avatar 每次都覆盖写同一个固定 COS key，URL 不变，
        // CachedNetworkImageProvider 按 URL 做缓存就不会重新拉取——不清掉
        // 旧缓存的话，状态其实更新对了，界面却"看起来"没变
        await CachedNetworkImage.evictFromCache(newAvatar);

        final updated = _user!.copyWith(avatar: newAvatar);
        ref.read(authServiceProvider).updateCurrentUser(updated);
        setState(() => _user = updated);
      }

      if (mounted && newAvatar != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.avatarUpdated)),
        );
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.uploadFailedWithReason(
                e.toString().replaceAll('Exception: ', ''),
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  void _addLink() {
    if (_linkCtrls.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.maxLinksReached)),
      );
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

  static const _recommendedTags = [
    'Python',
    '数据分析',
    'LaTeX',
    '机器学习',
    'matplotlib',
    '统计学',
    '宇宙科学',
    '经济',
    '编程',
    '生命科学',
    '时事',
    '生活',
  ];

  void _showInterestTagsSheet() {
    final customCtrl = TextEditingController();
    final customFocusNode = FocusNode();
    var selected = List<String>.from(_tags);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          void addTag(String tag) {
            final t = tag.trim();
            if (t.isEmpty || selected.contains(t)) return;
            if (selected.length >= 3) {
              ScaffoldMessenger.of(
                ctx,
              ).showSnackBar(const SnackBar(content: Text('最多添加3个兴趣标签')));
              return;
            }
            setSheetState(() => selected.add(t));
          }

          final atLimit = selected.length >= 3;

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(ctx).cardColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const Text(
                        '兴趣标签（最多3个）',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '根据关键词自动推理类别和配色',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(ctx).textTheme.bodySmall?.color,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ...selected.map(
                            (t) => InterestTag(
                              label: t,
                              removable: true,
                              onRemove: () =>
                                  setSheetState(() => selected.remove(t)),
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              if (atLimit) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(content: Text('最多添加3个兴趣标签')),
                                );
                                return;
                              }
                              FocusScope.of(ctx).requestFocus(customFocusNode);
                            },
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: atLimit
                                    ? Colors.grey.shade200
                                    : Theme.of(
                                        ctx,
                                      ).inputDecorationTheme.fillColor,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.add,
                                size: 18,
                                color: atLimit ? Colors.grey : _primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        '推荐标签',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(ctx).textTheme.bodySmall?.color,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _recommendedTags.map((t) {
                          return InterestTag(
                            label: t,
                            selected: selected.contains(t),
                            onTap: () => addTag(t),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: customCtrl,
                        focusNode: customFocusNode,
                        decoration: InputDecoration(
                          hintText: '输入自定义标签，回车添加',
                          hintStyle: const TextStyle(
                            fontSize: 13,
                            color: Colors.grey,
                          ),
                          filled: true,
                          fillColor: Theme.of(
                            ctx,
                          ).inputDecorationTheme.fillColor,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                        ),
                        style: const TextStyle(fontSize: 14),
                        onSubmitted: (v) {
                          addTag(v);
                          customCtrl.clear();
                        },
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '提示：系统会根据关键词自动匹配配色',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() => _tags = selected);
                            Navigator.pop(ctx);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primary,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            '完成',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showBirthdayPicker() {
    final l10n = AppLocalizations.of(context)!;
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
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
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
                          child: Text(
                            l10n.cancel,
                            style: const TextStyle(
                              fontSize: 15,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          l10n.selectBirthdaySheetTitle,
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
                          child: Text(
                            l10n.done,
                            style: const TextStyle(
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
                          zodiacDisplayName(l10n, sign),
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
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      // 顶部条不套 SafeArea，改成手动加状态栏高度的 padding——SafeArea
      // 会把整个 Column 往下推，露出状态栏那一截 scaffoldBackgroundColor
      // （偏灰）跟下面 cardColor（纯白）的顶部条不是同一个颜色，看起来
      // 像多了一条灰边。让 cardColor 背景直接铺到最顶上，只把内容往下推
      body: !_loaded
          ? const Center(child: CircularProgressIndicator(color: _primary))
          : Column(
              children: [
                Container(
                  color: Theme.of(context).cardColor,
                  padding: EdgeInsets.fromLTRB(
                    16,
                    MediaQuery.of(context).padding.top + 14,
                    16,
                    14,
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => context.pop(),
                        child: Text(
                          l10n.cancel,
                          style: const TextStyle(
                            fontSize: 15,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          l10n.editProfile,
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
                            : Text(
                                l10n.save,
                                style: const TextStyle(
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
                                      color: Colors.black.withValues(
                                        alpha: 0.45,
                                      ),
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
                          Text(
                            l10n.tapToChangeAvatar,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Divider(
                            height: 1,
                            thickness: 0.5,
                            color: Theme.of(context).dividerColor,
                          ),

                          // 基本信息
                          _textFieldRow(
                            l10n.nicknameLabel,
                            _usernameCtrl,
                            l10n.nicknameHint,
                          ),
                          _textFieldRow(
                            l10n.usernameLabel,
                            _handleCtrl,
                            l10n.usernameAtHint,
                          ),
                          _bioRow(),
                          Divider(
                            height: 1,
                            thickness: 0.5,
                            color: Theme.of(context).dividerColor,
                          ),

                          // 个人信息
                          _formRow(
                            label: l10n.genderLabel,
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
                                      genderDisplayLabel(l10n, g),
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
                          _textFieldRow(
                            l10n.locationLabel,
                            _locationCtrl,
                            l10n.locationHint,
                          ),
                          _formRow(
                            label: l10n.birthdayLabel,
                            onTap: _showBirthdayPicker,
                            child: _birthday == null
                                ? Text(
                                    l10n.selectBirthdayPlaceholder,
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
                                        DateFormat.yMMMMd(
                                          Localizations.localeOf(
                                            context,
                                          ).toString(),
                                        ).format(_birthday!),
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
                                        zodiacDisplayName(l10n, _zodiacSign!),
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: _primary,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                          _formRow(
                            label: '兴趣标签',
                            onTap: _showInterestTagsSheet,
                            child: _tags.isEmpty
                                ? Text(
                                    '未设置',
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: Theme.of(
                                        context,
                                      ).textTheme.bodySmall?.color,
                                    ),
                                  )
                                : Wrap(
                                    alignment: WrapAlignment.end,
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: _tags
                                        .map((t) => InterestTag(label: t))
                                        .toList(),
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
                                    Text(
                                      l10n.addLink,
                                      style: const TextStyle(
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
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                l10n.deleteAccount,
                                style: const TextStyle(
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
          Expanded(
            child: Align(alignment: Alignment.centerRight, child: child),
          ),
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
          filled: false,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        style: TextStyle(
          fontSize: 15,
          color: Theme.of(context).textTheme.bodyLarge?.color,
        ),
      ),
      showChevron: false,
    );
  }

  // 简介允许多行，行高不能锁死在 52，跟其它单行字段区分开
  Widget _bioRow() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              l10n.bioLabel,
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
              decoration: InputDecoration(
                hintText: l10n.bioHint,
                hintStyle: const TextStyle(
                  color: Color(0xFFC7C7CC),
                  fontSize: 15,
                ),
                border: InputBorder.none,
                filled: false,
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
                filled: false,
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
    final l10n = AppLocalizations.of(context)!;
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
              title: Text(l10n.selectFromAlbum),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUploadAvatar(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: Text(l10n.takePhoto),
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
