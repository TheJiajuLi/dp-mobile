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

  final data = res.data;
  final List list = data is List
      ? data
      : (data is Map ? (data['data'] ?? data['tutorials'] ?? []) as List : []);

  return list.map((e) => TutorialModel.fromJson(e as Map<String, dynamic>)).toList();
});
