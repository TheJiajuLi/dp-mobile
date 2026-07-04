import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

class StorageScreen extends ConsumerStatefulWidget {
  const StorageScreen({super.key});

  @override
  ConsumerState<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends ConsumerState<StorageScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _expandedCategory;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 实测 GET /auth/storage/usage 是真的存在、按分类聚合好的接口——不是
    // /auth/files 那个裸数组。ApiClient.get 不会抛异常，失败时 res.data
    // 是 null，下面 build() 里全部用 ?? 兜底，不用额外判断 res.success
    final res = await ref.read(apiClientProvider).get('/auth/storage/usage');
    if (!mounted) return;
    setState(() {
      _data = res.data as Map<String, dynamic>?;
      _loading = false;
    });
  }

  String _fmt(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)}GB';
  }

  String _fmtQuota(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      final gb = bytes / 1024 / 1024 / 1024;
      return '${gb.toStringAsFixed(0)}GB';
    }
    return '${(bytes / 1024 / 1024).toStringAsFixed(0)}MB';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final quota = _data?['quota'] as int? ?? 200 * 1024 * 1024;
    final total = _data?['totalBytes'] as int? ?? 0;
    final membership = _data?['membership'] as String? ?? 'free';
    final categories = _data?['categories'] as Map? ?? {};
    final usedPercent = (total / quota).clamp(0.0, 1.0);

    final membershipLabel =
        const {'free': '免费版', 'pro': 'Pro', 'pro_max': 'Pro Max'}[membership] ??
        '免费版';

    final folderDefs = [
      {
        'key': 'notebooks',
        'label': 'Notebook 文件',
        'icon': Icons.menu_book_outlined,
        'color': const Color(0xFF6366F1),
        'bg': const Color(0xFFEEF0FF),
      },
      {
        'key': 'tutorials',
        'label': '教程 / 笔记',
        'icon': Icons.article_outlined,
        'color': const Color(0xFF16A34A),
        'bg': const Color(0xFFE8F8F0),
      },
      {
        'key': 'media',
        'label': '图片 / 视频 / 音频',
        'icon': Icons.perm_media_outlined,
        'color': const Color(0xFFD97706),
        'bg': const Color(0xFFFFF7E6),
      },
      {
        'key': 'docs',
        'label': '文档 / 数据文件',
        'icon': Icons.folder_outlined,
        'color': const Color(0xFF2563EB),
        'bg': const Color(0xFFE6F1FB),
      },
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('云端存储'),
        backgroundColor: Theme.of(context).cardColor,
        foregroundColor: Theme.of(context).textTheme.bodyLarge?.color,
        elevation: 0,
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: ListView(
        children: [
          // 存储概览卡片
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.cloud_outlined, color: Color(0xFF6366F1)),
                    const SizedBox(width: 8),
                    const Text(
                      '存储空间',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF0FF),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        membershipLabel,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6366F1),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: usedPercent,
                    minHeight: 10,
                    backgroundColor: Colors.grey[100],
                    valueColor: AlwaysStoppedAnimation(
                      usedPercent > 0.9 ? Colors.red : const Color(0xFF6366F1),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      _fmt(total),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      ' / ${_fmtQuota(quota)}',
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const Spacer(),
                    Text(
                      '剩余 ${_fmt(quota - total)}',
                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 文件夹列表
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '文件分类',
              style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500),
            ),
          ),

          Container(
            color: Theme.of(context).cardColor,
            child: Column(
              children: folderDefs.map((folder) {
                final key = folder['key'] as String;
                final cat = categories[key] as Map? ?? {};
                final files = cat['files'] as List? ?? [];
                final bytes = (cat['totalBytes'] as num?)?.toInt() ?? 0;
                final isExpanded = _expandedCategory == key;

                return Column(
                  children: [
                    GestureDetector(
                      onTap: () => setState(
                        () => _expandedCategory = isExpanded ? null : key,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Theme.of(context).dividerColor),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: folder['bg'] as Color,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                folder['icon'] as IconData,
                                color: folder['color'] as Color,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    folder['label'] as String,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    '${files.length} 个文件 · ${_fmt(bytes)}',
                                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              isExpanded ? Icons.expand_less : Icons.expand_more,
                              color: Colors.grey,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 展开文件列表
                    if (isExpanded)
                      ...files.isEmpty
                          ? [
                              const Padding(
                                padding: EdgeInsets.all(20),
                                child: Text(
                                  '暂无文件',
                                  style: TextStyle(color: Colors.grey, fontSize: 14),
                                ),
                              ),
                            ]
                          : files.map((f) {
                              final name =
                                  f['filename'] as String? ?? f['title'] as String? ?? '未知文件';
                              final size = (f['size_bytes'] as num?)?.toInt() ?? 0;
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).scaffoldBackgroundColor,
                                  border: Border(
                                    bottom: BorderSide(color: Theme.of(context).dividerColor),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const SizedBox(width: 52),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            style: const TextStyle(fontSize: 13),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (size > 0)
                                            Text(
                                              _fmt(size),
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                  ],
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
