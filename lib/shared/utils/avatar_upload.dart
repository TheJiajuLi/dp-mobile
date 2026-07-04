import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/network/api_client.dart';

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
    throw Exception(res.message ?? '上传失败，请重试');
  }
  return (res.data as Map)['avatar'] as String?;
}
