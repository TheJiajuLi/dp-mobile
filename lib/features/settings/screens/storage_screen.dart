import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/generated/app_localizations.dart';

enum _MediaKind { image, video, audio, other }

class StorageScreen extends ConsumerStatefulWidget {
  const StorageScreen({super.key});

  @override
  ConsumerState<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends ConsumerState<StorageScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _cleaningUp = false;
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

  // 之前这里靠反推 cos_key 拼出 id（假设格式固定是
  // "users/{userId}/{fileId}-{原始文件名}"），但小梦生成的封面/头像走的是
  // xmeng.controller.ts 的 persistImages，cos_key 是
  // "users/{userId}/{subdir}/{timestamp}-{i}.jpg"，根本不含 UUID——导致
  // 这类文件永远反推不出 id，删除按钮不显示、"清空此分类"里它们也永远
  // 进不了可删除列表。实测确认（2026-07-07）GET /auth/storage/usage 的
  // SQL 本来就 SELECT 了 id 这一列，直接读 f['id'] 就行，不需要反推
  String? _fileIdOf(dynamic f) => f['id'] as String?;

  // 实测确认：media/docs/notebooks 分类里 cos_key 是相对路径
  // ("users/{userId}/{fileId}-{文件名}")，但 tutorials 分类的 cos_key
  // 已经是完整的 https:// URL——两种格式混在同一个渲染逻辑里，靠
  // startsWith('http') 区分，不能无脑拼前缀（拼出来会是重复前缀的坏URL）
  static const _cosBaseUrl = 'https://dp-1317483118.cos.ap-hongkong.myqcloud.com/';

  String? _coverUrl(String? cosKey) {
    if (cosKey == null || cosKey.isEmpty) return null;
    return cosKey.startsWith('http') ? cosKey : '$_cosBaseUrl$cosKey';
  }

  // 实测确认：/auth/files/upload 对所有上传（图片/视频/音频）返回的
  // file_type 统一都是 "other"，后端并不区分媒体子类型——图片/视频/音频
  // 只能靠文件名后缀在客户端自己猜
  static const _imageExts = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic'};
  static const _videoExts = {'mp4', 'mov', 'm4v', 'avi', 'mkv', 'webm'};
  static const _audioExts = {'mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg'};

  _MediaKind _mediaKindOf(String filename) {
    final dot = filename.lastIndexOf('.');
    if (dot < 0 || dot == filename.length - 1) return _MediaKind.other;
    final ext = filename.substring(dot + 1).toLowerCase();
    if (_imageExts.contains(ext)) return _MediaKind.image;
    if (_videoExts.contains(ext)) return _MediaKind.video;
    if (_audioExts.contains(ext)) return _MediaKind.audio;
    return _MediaKind.other;
  }

  Widget _buildThumbnail(dynamic f, String categoryKey) {
    final name = f['filename'] as String? ?? '';
    final isTutorial = categoryKey == 'tutorials';
    final coverUrl = _coverUrl(f['cos_key'] as String?);
    final kind = isTutorial ? null : _mediaKindOf(name);

    if (kind == _MediaKind.audio) {
      return Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(color: Color(0xFFF3E8FF), shape: BoxShape.circle),
        child: const Icon(Icons.music_note, size: 18, color: Color(0xFF9333EA)),
      );
    }

    if (kind == _MediaKind.video) {
      return SizedBox(
        width: 52,
        height: 44,
        child: coverUrl != null
            ? _VideoThumbnail(url: coverUrl)
            : Container(
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.videocam_outlined, size: 18, color: Colors.grey[400]),
              ),
      );
    }

    // 教程封面 / 图片缩略图：走同一套 CachedNetworkImage 逻辑，跟首页封面
    // 图渲染方式保持一致（占位色块+错误兜底图标）
    if (isTutorial || kind == _MediaKind.image) {
      final fallbackIcon = isTutorial ? Icons.article_outlined : Icons.image_outlined;
      return Container(
        width: 52,
        height: 44,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: coverUrl != null
            ? CachedNetworkImage(
                imageUrl: coverUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) => const Center(
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 1.6),
                  ),
                ),
                errorWidget: (context, url, error) =>
                    Icon(fallbackIcon, size: 18, color: Colors.grey[400]),
              )
            : Icon(fallbackIcon, size: 18, color: Colors.grey[400]),
      );
    }

    // 兜底：doc/notebook 或无法识别后缀的文件
    return SizedBox(
      width: 52,
      height: 44,
      child: Icon(Icons.insert_drive_file_outlined, size: 22, color: Colors.grey[400]),
    );
  }

  Widget _buildWaveform() {
    // 模拟波形——不是真实音频波形分析，只是固定高度序列做出音频列表项
    // 该有的视觉质感
    const heights = [
      5.0, 10.0, 16.0, 9.0, 14.0, 7.0, 12.0, 6.0, 15.0, 8.0,
      11.0, 5.0, 13.0, 9.0, 16.0, 6.0, 10.0, 14.0, 7.0, 12.0,
    ];
    return SizedBox(
      height: 16,
      child: Row(
        children: heights
            .map(
              (h) => Container(
                width: 2.5,
                height: h,
                margin: const EdgeInsets.only(right: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF9333EA).withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildFileItem(dynamic f, String categoryKey) {
    final l10n = AppLocalizations.of(context)!;
    final name = f['filename'] as String? ?? l10n.unknownFile;
    final size = (f['size_bytes'] as num?)?.toInt() ?? 0;
    final platform = f['platform'] as String? ?? 'mobile';
    final fileId = _fileIdOf(f);
    final isTutorial = categoryKey == 'tutorials';
    final status = f['status'] as String?;
    final isAudio = !isTutorial && _mediaKindOf(name) == _MediaKind.audio;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          _buildThumbnail(f, categoryKey),
          const SizedBox(width: 12),
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
                    if (isTutorial && status != null)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: status == 'published'
                              ? const Color(0xFFE8F8F0)
                              : const Color(0xFFFFF7E6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          status == 'published'
                              ? l10n.tutorialStatusPublished
                              : l10n.tutorialStatusDraft,
                          style: TextStyle(
                            fontSize: 10,
                            color: status == 'published'
                                ? const Color(0xFF16A34A)
                                : const Color(0xFFD97706),
                          ),
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
                if (isAudio) ...[
                  const SizedBox(height: 4),
                  _buildWaveform(),
                ],
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

  // 清理未使用文件——POST /auth/storage/cleanup-orphans 是真实接口：后端
  // 拿 user_files 里所有非头像的记录，跟 tutorials.cover_image / users.
  // avatar 实际引用的 cos_key 比对，凡是没被任何地方引用到的就真删（COS+
  // 数据库记录都删），不是只改本地展示。小梦 AI 生成封面/头像那 2-3 张
  // 候选图里没被选中的那些就是典型的"孤儿文件"，这个按钮就是给这种场景
  // 兜底清掉，不用等它们自然占满配额才发现
  Future<void> _cleanupOrphans() async {
    if (_cleaningUp) return;
    setState(() => _cleaningUp = true);
    final res = await ref
        .read(apiClientProvider)
        .post('/auth/storage/cleanup-orphans', data: {});
    if (!mounted) return;
    if (res.success) {
      await _load();
      if (!mounted) return;
    }
    setState(() => _cleaningUp = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          res.success ? (res.data?['message'] as String? ?? '清理完成') : '清理失败，请稍后重试',
        ),
        backgroundColor: res.success ? const Color(0xFF16A34A) : null,
      ),
    );
  }

  Future<void> _confirmDeleteAll(String categoryKey, List files) async {
    final l10n = AppLocalizations.of(context)!;
    // 只统计真的能删（反推得出 id）的文件，跟实际会执行的删除数量对得上
    final deletable = files
        .map((f) => (f: f, id: _fileIdOf(f)))
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
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _cleaningUp ? null : _cleanupOrphans,
                    icon: _cleaningUp
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Colors.grey,
                            ),
                          )
                        : const Icon(Icons.cleaning_services, size: 16),
                    label: Text(_cleaningUp ? '正在清理...' : '清理未使用文件'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[100],
                      foregroundColor: Colors.grey[700],
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
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
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: Theme.of(context).brightness == Brightness.dark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: folderDefs.asMap().entries.map((entry) {
                final folderIndex = entry.key;
                final folder = entry.value;
                final key = folder['key'] as String;
                final cat = categories[key] as Map? ?? {};
                final files = cat['files'] as List? ?? [];
                final bytes = (cat['totalBytes'] as num?)?.toInt() ?? 0;
                final isExpanded = _expandedCategory == key;
                // 最后一个分类折叠时不画底部分割线——不然圆角卡片最下面
                // 会贴着一条紧挨圆角的线，跟 SettingsGroup/_PreviewCard
                // 最后一项不画分割线是同一个道理
                final isLast = folderIndex == folderDefs.length - 1;

                return Column(
                  children: [
                    GestureDetector(
                      onTap: () => setState(
                        () => _expandedCategory = isExpanded ? null : key,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: (isLast && !isExpanded)
                            ? null
                            : BoxDecoration(
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

// 从视频 URL 截取首帧当缩略图。video_thumbnail 支持直接传网络 URL（内部会
// 自己下载解码），不需要先手动下载到本地文件
class _VideoThumbnail extends StatefulWidget {
  const _VideoThumbnail({required this.url});

  final String url;

  @override
  State<_VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<_VideoThumbnail> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  Future<void> _generate() async {
    try {
      final bytes = await VideoThumbnail.thumbnailData(
        video: widget.url,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 200,
        quality: 75,
      );
      if (!mounted) return;
      setState(() => _bytes = bytes);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          if (_bytes != null)
            Image.memory(_bytes!, fit: BoxFit.cover)
          else if (!_failed)
            const Center(
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.6, color: Colors.white70),
              ),
            )
          else
            Icon(Icons.videocam_outlined, size: 18, color: Colors.grey[400]),
          const Icon(Icons.play_circle_fill, size: 20, color: Colors.white70),
        ],
      ),
    );
  }
}
