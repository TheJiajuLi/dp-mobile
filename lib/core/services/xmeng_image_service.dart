import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';

// AI 封面/头像生成曾经短暂改成 Flutter 直接调 moyu.info——但那样得把
// API key 硬编码进客户端源码，反编译/抓包就能拿到盗刷，安全风险不可接受。
// 改回后端代为调用：Flutter 只传 title/tags/description，图像生成和转存
// COS 都在后端 /auth/xmeng/cover、/auth/xmeng/avatar 里完成
class XmengImageService {
  final ApiClient _api;

  XmengImageService(this._api);

  Future<List<String>> generateCover({
    required String title,
    required List<String> tags,
    String? summary,
  }) async {
    final res = await _api.post(
      '/auth/xmeng/cover',
      data: {'title': title, 'tags': tags, 'summary': summary ?? ''},
      options: Options(
        receiveTimeout: const Duration(seconds: 150),
        sendTimeout: const Duration(seconds: 30),
      ),
    );
    if (!res.success) return [];
    return List<String>.from(res.data['urls'] ?? []);
  }

  Future<List<String>> generateAvatar({String? description}) async {
    final res = await _api.post(
      '/auth/xmeng/avatar',
      data: {'description': description ?? ''},
      options: Options(
        receiveTimeout: const Duration(seconds: 150),
        sendTimeout: const Duration(seconds: 30),
      ),
    );
    if (!res.success) return [];
    return List<String>.from(res.data['urls'] ?? []);
  }
}

final xmengImageServiceProvider = Provider<XmengImageService>((ref) {
  return XmengImageService(ref.read(apiClientProvider));
});
