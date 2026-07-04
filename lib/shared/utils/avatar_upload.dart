import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/locale_provider.dart';
import '../../core/network/api_client.dart';
import '../../l10n/generated/app_localizations.dart';

// 抛出去的 Exception message 会被调用方（edit_profile/user_profile 页）
// 再套一层 l10n.uploadFailedWithReason(...) 的本地化"上传失败："前缀，
// 这里必须是纯原因文本，不能再自己嵌一遍中文前缀
AppLocalizations _currentL10n(WidgetRef ref) {
  final pref = ref.read(localeProvider);
  final locale = localeFor(pref) ?? PlatformDispatcher.instance.locale;
  if (AppLocalizations.supportedLocales.any((l) => l.languageCode == locale.languageCode)) {
    return lookupAppLocalizations(locale);
  }
  return lookupAppLocalizations(const Locale('zh'));
}

// 头像上传的核心逻辑抽成共享函数——编辑资料页和个人主页头像上的相机角标
// 都要能直接改头像，不能只有编辑资料页能用
Future<String?> pickAndUploadAvatar(WidgetRef ref, ImageSource source) async {
  final picker = ImagePicker();
  final file = await picker.pickImage(
    source: source,
    maxWidth: 512,
    maxHeight: 512,
    imageQuality: 85,
  );
  if (file == null) return null;

  final bytes = await file.readAsBytes();
  final formData = FormData.fromMap({
    'avatar': MultipartFile.fromBytes(
      bytes,
      filename: 'avatar.jpg',
      contentType: DioMediaType('image', 'jpeg'),
    ),
  });

  // ApiClient.post 内部吞掉了 DioException，不会抛异常——失败与否要看
  // res.success，不能只靠 try/catch
  final res = await ref
      .read(apiClientProvider)
      .post('/auth/update-avatar', data: formData);
  if (!res.success) {
    // 调用方（edit_profile/user_profile）catch住之后会再套一层
    // l10n.uploadFailedWithReason("上传失败：{reason}") 的前缀，这里只
    // 抛纯原因文本，不能是完整句子，否则会跟外层前缀重复成
    // "上传失败：上传失败，请重试"
    throw Exception(res.message ?? _currentL10n(ref).requestFailed);
  }
  return (res.data as Map)['avatar'] as String?;
}
