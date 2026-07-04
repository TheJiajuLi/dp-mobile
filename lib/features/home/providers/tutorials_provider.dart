import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/models/tutorial_model.dart';
import '../../auth/auth_service.dart';

// 首页"最近教程"是个人主页内容，只展示当前登录用户自己创建的教程。
//
// 实测确认 GET /auth/tutorials?author=xxx 这个后端参数目前是无效的——
// 传用户名、传 user_id、传随便一个乱七八糟的值，返回的都是全站所有已发布
// 教程，total 完全一致。这是后端 bug，不是这里传错了参数。在后端修好之前，
// 只能客户端兜底过滤：多拉一批（而不是配合 limit:3 一起用，那样一旦这批
// "全站最新"里恰好没有这个用户自己的教程，过滤完就会变空，即便他其实有
// 教程只是不够新），按 userId 过滤完再按时间倒序取前 3 条。
final recentTutorialsProvider = FutureProvider<List<TutorialModel>>((ref) async {
  final userId = ref.watch(currentUserProvider)?.id;
  if (userId == null || userId.isEmpty) return [];

  final api = ref.watch(apiClientProvider);
  final res = await api.get(
    '/auth/tutorials',
    queryParameters: {'status': 'published', 'author': userId, 'limit': 50},
  );
  if (!res.success) {
    throw Exception(res.message ?? '加载失败');
  }

  // GET /auth/tutorials 返回 {tutorials:[...], total, page, pages}，不是裸数组
  final list = (res.data as Map)['tutorials'] as List;

  final tutorials = list
      .map((e) => TutorialModel.fromJson(e as Map<String, dynamic>))
      .where((t) => t.userId == userId)
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  return tutorials.take(3).toList();
});
