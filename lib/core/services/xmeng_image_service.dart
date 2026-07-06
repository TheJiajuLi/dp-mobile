import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';

// AI 封面/头像生成原来是后端转发调 moyu.info，出口网络不稳定导致经常超时。
// 改成 Flutter 客户端直接调用生成接口，拿到 moyu.info 的临时图片 url 后，
// 再让后端 /auth/xmeng/upload-image 把这个临时 url 转存到 COS——后端只做
// 转存，不再经手生成这一步
class XmengImageService {
  static const _imageApiUrl = 'https://www.moyu.info/v1/images/generations';
  static const _apiKey =
      'sk-yuxqWNr4wdyJix8XqKgyI5Fyi8F8g5mgHxvevRVxnOdBpTuW';
  static const _model = 'doubao-seedream-4-0-250828';

  final Dio _imageDio;
  final ApiClient _api;

  XmengImageService(this._imageDio, this._api);

  Future<List<String>> generateCover({
    required String title,
    required List<String> tags,
    String? summary,
  }) async {
    final prompt = _buildCoverPrompt(title, tags.join('、'));
    final tempUrls = <String>[];
    for (var i = 0; i < 3; i++) {
      final url = await _generateOne(prompt, '1280x720');
      if (url != null) tempUrls.add(url);
    }
    return _uploadAll(tempUrls, 'ai-covers');
  }

  Future<List<String>> generateAvatar({String? description}) async {
    final prompt = description?.isNotEmpty == true
        ? '头像图片，$description，正方形构图，简洁精致，适合社交平台头像，高质量'
        : '极简风格头像，抽象几何图案，紫色蓝色配色，正方形构图，高质量';
    final tempUrls = <String>[];
    for (var i = 0; i < 2; i++) {
      final url = await _generateOne(prompt, '1024x1024');
      if (url != null) tempUrls.add(url);
    }
    return _uploadAll(tempUrls, 'ai-avatars');
  }

  Future<List<String>> _uploadAll(List<String> tempUrls, String folder) async {
    final cosUrls = <String>[];
    for (final tempUrl in tempUrls) {
      try {
        cosUrls.add(await _uploadToCos(tempUrl, folder));
      } catch (e) {
        debugPrint('[xmeng] COS上传失败: $e');
      }
    }
    return cosUrls;
  }

  Future<String?> _generateOne(String prompt, String size) async {
    try {
      final res = await _imageDio.post(
        _imageApiUrl,
        data: {'model': _model, 'prompt': prompt, 'n': 1, 'size': size},
        options: Options(
          headers: {
            'Authorization': 'Bearer $_apiKey',
            'Content-Type': 'application/json',
          },
          receiveTimeout: const Duration(seconds: 90),
          sendTimeout: const Duration(seconds: 30),
        ),
      );
      final data = res.data['data'] as List?;
      return data?[0]?['url'] as String?;
    } catch (e) {
      debugPrint('[xmeng/image] 生成失败: $e');
      return null;
    }
  }

  Future<String> _uploadToCos(String tempUrl, String folder) async {
    final res = await _api.post(
      '/auth/xmeng/upload-image',
      data: {'url': tempUrl, 'folder': folder},
      options: Options(receiveTimeout: const Duration(seconds: 30)),
    );
    if (!res.success) {
      throw Exception('上传失败: ${res.message}');
    }
    return res.data['url'] as String;
  }

  String _buildCoverPrompt(String title, String tags) {
    final isCode = [
      'Python',
      '代码',
      '编程',
      'JavaScript',
      'SQL',
    ].any((k) => tags.contains(k));
    final isMath = ['数学', 'LaTeX', '公式', '统计', '物理'].any((k) => tags.contains(k));
    final isData = ['数据', '可视化', '分析', '图表'].any((k) => tags.contains(k));

    String scene;
    if (isCode) {
      scene =
          'glowing code on dark screens, '
          'holographic data streams, '
          'futuristic atmosphere, ';
    } else if (isMath) {
      scene =
          'abstract geometric shapes, '
          'floating mathematical curves, '
          'crystalline structures, ';
    } else if (isData) {
      scene =
          'flowing data visualization, '
          'colorful chart elements, '
          'abstract network graph, ';
    } else {
      scene =
          'abstract knowledge concept, '
          'flowing light particles, '
          'elegant minimal composition, ';
    }
    return '${scene}cinematic wide banner 16:9, '
        'purple blue gradient atmosphere, '
        'professional digital art, '
        'no text no letters no words, '
        'high quality ultra detailed';
  }
}

final xmengImageServiceProvider = Provider<XmengImageService>((ref) {
  return XmengImageService(Dio(), ref.read(apiClientProvider));
});
