import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/models/tutorial_model.dart';

final recentTutorialsProvider = FutureProvider<List<TutorialModel>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.get(
    '/auth/tutorials',
    queryParameters: {'status': 'published', 'limit': 3},
  );
  if (!res.success) {
    throw Exception(res.message ?? '加载失败');
  }

  // GET /auth/tutorials 返回 {tutorials:[...], total, page, pages}，不是裸数组
  final list = (res.data as Map)['tutorials'] as List;

  return list.map((e) => TutorialModel.fromJson(e as Map<String, dynamic>)).toList();
});
