import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/models/tutorial_model.dart';
import '../../auth/auth_service.dart';

// 首页"最近教程"是个人主页内容，只展示当前登录用户自己创建的教程——
// 不带 author 过滤会拿到全社区的教程列表
final recentTutorialsProvider = FutureProvider<List<TutorialModel>>((ref) async {
  final userId = ref.watch(currentUserProvider)?.id;
  if (userId == null || userId.isEmpty) return [];

  final api = ref.watch(apiClientProvider);
  final res = await api.get(
    '/auth/tutorials',
    queryParameters: {'status': 'published', 'author': userId, 'limit': 3},
  );
  if (!res.success) {
    throw Exception(res.message ?? '加载失败');
  }

  // GET /auth/tutorials 返回 {tutorials:[...], total, page, pages}，不是裸数组
  final list = (res.data as Map)['tutorials'] as List;

  return list.map((e) => TutorialModel.fromJson(e as Map<String, dynamic>)).toList();
});
