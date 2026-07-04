import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/generated/app_localizations.dart';

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

  // 实测确认：GET /auth/storage/usage 里 categories[key].files 的每一项
  // 完全没有 id 字段（只有 filename/file_type/size_bytes/cos_key/
  // created_at/platform），跟 GET /auth/files 那个裸数组不一样。但
  // DELETE /auth/files/:id 只能按 id 删——cos_key 的格式固定是
  // "users/{userId}/{fileId}-{原始文件名}"，{fileId} 正好是标准 UUID
  // （36个字符，第37个字符是分隔用的'-'），从这里能可靠地反推出 id。
  // 反推失败（cos_key 缺失或格式对不上）就不显示删除按钮，不冒险删错
  static final _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  String? _extractFileId(String? cosKey) {
    if (cosKey == null || cosKey.isEmpty) return null;
    final lastSegment = cosKey.split('/').last;
    if (lastSegment.length <= 37 || lastSegment[36] != '-') return null;
    final candidate = lastSegment.substring(0, 36);
    return _uuidPattern.hasMatch(candidate) ? candidate : null;
  }

  Widget _buildFileItem(dynamic f, String categoryKey) {
    final l10n = AppLocalizations.of(context)!;
    final name = f['filename'] as String? ?? l10n.unknownFile;
    final size = (f['size_bytes'] as num?)?.toInt() ?? 0;
    final platform = f['platform'] as String? ?? 'mobile';
    final fileId = _extractFileId(f['cos_key'] as String?);
    final isTutorial = categoryKey == 'tutorials';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 52),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (platform != 'mobile')
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          l10n.desktopPlatformTag,
                          style: const TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ),
                  ],
                ),
                if (size > 0)
                  Text(
                    _fmt(size),
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
              ],
            ),
          ),
          // 教程走 tutorials 表自己的 id（这个分类的 files 项直接带真实
          // id，不是 cos_key 拼出来的），删的是 DELETE /auth/tutorials/:id
          // 而不是 /auth/files/:id——创作中心目前还只是个占位入口，没有
          // 真正的教程管理页面，先在这直接支持删除
          if (isTutorial)
            GestureDetector(
              onTap: () => _confirmDeleteTutorial(f['id'] as String? ?? '', name),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.delete_outline, size: 16, color: Color(0xFFDC2626)),
              ),
            )
          // 反推不出 id 的文件不给删除按钮，不冒险删错
          else if (fileId != null)
            GestureDetector(
              onTap: () => _confirmDelete(fileId, name, size),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.delete_outline, size: 16, color: Color(0xFFDC2626)),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(String fileId, String name, int size) async {
    final l10n = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteFile),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.confirmDeleteFileMessage(name)),
            const SizedBox(height: 8),
            if (size > 0)
              Text(
                l10n.willFreeSpace(_fmt(size)),
                style: const TextStyle(fontSize: 13, color: Color(0xFF16A34A)),
              ),
            const SizedBox(height: 4),
            Text(
              l10n.actionCannotBeUndone,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel, style: const TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.deleteAction, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    await _deleteFile(fileId, size);
  }

  Future<void> _deleteFile(String fileId, int size) async {
    final l10n = AppLocalizations.of(context)!;
    final res = await ref.read(apiClientProvider).delete('/auth/files/$fileId');
    if (!mounted) return;

    if (res.success) {
      // 直接改本地这份聚合数据容易因为字段类型/嵌套结构猜错而出岔子——
      // 存储用量这种非高频操作，重新拉一次准确数据更省心
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.deletedFreedSpace(_fmt(size))),
          backgroundColor: const Color(0xFF16A34A),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message ?? l10n.fileDeleteFailed)),
      );
    }
  }

  Future<void> _confirmDeleteTutorial(String tutorialId, String name) async {
    if (tutorialId.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteTutorial),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.confirmDeleteFileMessage(name)),
            const SizedBox(height: 8),
            Text(
              l10n.tutorialContentAndCommentsWillBeDeleted,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.actionCannotBeUndone,
              style: const TextStyle(fontSize: 12, color: Color(0xFFDC2626)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel, style: const TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.deleteAction, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    await _deleteTutorial(tutorialId, name);
  }

  Future<void> _deleteTutorial(String tutorialId, String name) async {
    final l10n = AppLocalizations.of(context)!;
    final res = await ref.read(apiClientProvider).delete('/auth/tutorials/$tutorialId');
    if (!mounted) return;

    if (res.success) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.tutorialDeletedMessage(name)),
          backgroundColor: const Color(0xFF16A34A),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message ?? l10n.fileDeleteFailed)),
      );
    }
  }

  Future<void> _confirmDeleteAll(String categoryKey, List files) async {
    final l10n = AppLocalizations.of(context)!;
    // 只统计真的能删（反推得出 id）的文件，跟实际会执行的删除数量对得上
    final deletable = files
        .map((f) => (f: f, id: _extractFileId(f['cos_key'] as String?)))
        .where((e) => e.id != null)
        .toList();
    final totalSize = deletable.fold<int>(
      0,
      (s, e) => s + ((e.f['size_bytes'] as num?)?.toInt() ?? 0),
    );
    if (deletable.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.clearCategory),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.confirmClearCategoryMessage(deletable.length)),
            const SizedBox(height: 8),
            Text(
              l10n.willFreeSpace(_fmt(totalSize)),
              style: const TextStyle(fontSize: 13, color: Color(0xFF16A34A)),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.actionCannotBeUndone,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel, style: const TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.deleteAllAction, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    var deleted = 0;
    for (final e in deletable) {
      final res = await ref.read(apiClientProvider).delete('/auth/files/${e.id}');
      if (res.success) deleted++;
    }

    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.deletedCountFreedSpace(deleted, _fmt(totalSize))),
        backgroundColor: const Color(0xFF16A34A),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final l10n = AppLocalizations.of(context)!;
    final quota = _data?['quota'] as int? ?? 200 * 1024 * 1024;
    final total = _data?['totalBytes'] as int? ?? 0;
    final membership = _data?['membership'] as String? ?? 'free';
    final categories = _data?['categories'] as Map? ?? {};
    final usedPercent = (total / quota).clamp(0.0, 1.0);

    final membershipLabel =
        {'free': l10n.membershipFree, 'pro': 'Pro', 'pro_max': 'Pro Max'}[membership] ??
        l10n.membershipFree;

    final folderDefs = [
      {
        'key': 'notebooks',
        'label': l10n.folderNotebooks,
        'icon': Icons.menu_book_outlined,
        'color': const Color(0xFF6366F1),
        'bg': const Color(0xFFEEF0FF),
      },
      {
        'key': 'tutorials',
        'label': l10n.folderTutorials,
        'icon': Icons.article_outlined,
        'color': const Color(0xFF16A34A),
        'bg': const Color(0xFFE8F8F0),
      },
      {
        'key': 'media',
        'label': l10n.folderMedia,
        'icon': Icons.perm_media_outlined,
        'color': const Color(0xFFD97706),
        'bg': const Color(0xFFFFF7E6),
      },
      {
        'key': 'docs',
        'label': l10n.folderDocs,
        'icon': Icons.folder_outlined,
        'color': const Color(0xFF2563EB),
        'bg': const Color(0xFFE6F1FB),
      },
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.cloudStorage),
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
                    Text(
                      l10n.storageSpace,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
                      l10n.remainingSpace(_fmt(quota - total)),
                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 文件夹列表
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              l10n.fileCategories,
              style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500),
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
                                    l10n.fileCountWithSize(files.length, _fmt(bytes)),
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
                              Padding(
                                padding: const EdgeInsets.all(20),
                                child: Text(
                                  l10n.noFilesYet,
                                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                                ),
                              ),
                            ]
                          : [
                              // 教程在创作中心管理，这里不重复放清空入口
                              if (key != 'tutorials')
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  color: Theme.of(context).scaffoldBackgroundColor,
                                  child: Row(
                                    children: [
                                      Text(
                                        l10n.filesCountLabel(files.length),
                                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                                      ),
                                      const Spacer(),
                                      GestureDetector(
                                        onTap: () => _confirmDeleteAll(key, files),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFEF2F2),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            l10n.clearCategory,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFFDC2626),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ...files.map((f) => _buildFileItem(f, key)),
                            ],
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
