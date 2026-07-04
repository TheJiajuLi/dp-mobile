import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

// autoDispose：设置页关掉之后就不用继续占着这份数据，下次打开设置页
// 重新拉一次，配额用量本来就该是"每次打开都是新鲜的"
final storageUsageProvider = FutureProvider.autoDispose<Map<String, dynamic>>((
  ref,
) async {
  final res = await ref.read(apiClientProvider).get('/auth/storage/usage');
  if (!res.success || res.data == null) {
    throw Exception(res.message ?? '加载失败');
  }
  return res.data as Map<String, dynamic>;
});
