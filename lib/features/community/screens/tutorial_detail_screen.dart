import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';

const _primary = Color(0xFF6366F1);

String _initial(String? name) {
  if (name == null || name.isEmpty) return '?';
  return name.substring(0, 1).toUpperCase();
}

class TutorialDetailScreen extends ConsumerStatefulWidget {
  final String tutorialId;
  const TutorialDetailScreen({super.key, required this.tutorialId});

  @override
  ConsumerState<TutorialDetailScreen> createState() =>
      _TutorialDetailScreenState();
}

class _TutorialDetailScreenState extends ConsumerState<TutorialDetailScreen> {
  Map<String, dynamic>? _tutorial;
  List<dynamic> _blocks = [];
  bool _loading = true;
  bool _liked = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(apiClientProvider);
    final res = await api.get('/auth/tutorials/${widget.tutorialId}');
    if (!res.success || res.data == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final t = res.data as Map<String, dynamic>;

    // 解析 blocks
    var blocks = <dynamic>[];
    final rawBlocks = t['blocks'];
    if (rawBlocks is String && rawBlocks.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawBlocks);
        if (decoded is List) blocks = decoded;
      } catch (_) {}
    } else if (rawBlocks is List) {
      blocks = rawBlocks;
    }

    if (!mounted) return;
    setState(() {
      _tutorial = t;
      _blocks = blocks;
      // 后端字段名未确认，兼容 is_liked / liked 两种可能，同时兼容 0/1 和 bool
      _liked =
          t['is_liked'] == 1 || t['is_liked'] == true || t['liked'] == true;
      _loading = false;
    });
  }

  Future<void> _toggleLike() async {
    final api = ref.read(apiClientProvider);
    final res = _liked
        ? await api.delete('/auth/tutorials/${widget.tutorialId}/like')
        : await api.post('/auth/tutorials/${widget.tutorialId}/like');

    if (!res.success) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('操作失败：${res.message}')));
      return;
    }
    setState(() {
      _liked = !_liked;
      final likes = (_tutorial!['likes'] as num?)?.toInt() ?? 0;
      _tutorial!['likes'] = _liked ? likes + 1 : (likes > 0 ? likes - 1 : 0);
    });
  }

  Widget _buildAuthorAvatar(String? avatar, String username) {
    if (avatar != null && avatar.isNotEmpty) {
      if (avatar.startsWith('data:image')) {
        try {
          final raw = avatar.split(',').last;
          return CircleAvatar(
            radius: 18,
            backgroundImage: MemoryImage(base64Decode(raw)),
          );
        } catch (_) {
          // 解码失败落到下面的首字母占位
        }
      } else {
        return CircleAvatar(
          radius: 18,
          backgroundColor: _primary,
          backgroundImage: CachedNetworkImageProvider(avatar),
        );
      }
    }
    return CircleAvatar(
      radius: 18,
      backgroundColor: _primary,
      child: Text(
        _initial(username),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildBlock(Map<String, dynamic> block) {
    final type = block['type'] as String? ?? 'text';
    final content = block['content'] as String? ?? '';

    switch (type) {
      case 'heading':
        final level = block['level'] as int? ?? 2;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            content,
            style: TextStyle(
              fontSize: level == 2
                  ? 20
                  : level == 3
                  ? 17
                  : 15,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
        );

      case 'code':
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _primary.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        block['language'] as String? ?? 'python',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text(
                    content,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: Colors.white,
                      height: 1.6,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );

      case 'latex':
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Math.tex(
            content.replaceAll(r'$$', '').trim(),
            textStyle: const TextStyle(fontSize: 16),
            onErrorFallback: (err) => Text(
              content,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
        );

      case 'image':
        final imageUrl = block['imageUrl'] as String? ?? '';
        if (imageUrl.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            errorWidget: (context, url, error) => const SizedBox.shrink(),
          ),
        );

      case 'callout':
        final variant = block['variant'] as String? ?? 'info';
        final colors = {
          'tip': const Color(0xFF16A34A),
          'warning': const Color(0xFFD97706),
          'info': _primary,
        };
        final bgColors = {
          'tip': const Color(0xFFE8F8F0),
          'warning': const Color(0xFFFFF7E6),
          'info': const Color(0xFFEEF0FF),
        };
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: bgColors[variant] ?? const Color(0xFFEEF0FF),
            borderRadius: BorderRadius.circular(10),
            border: Border(
              left: BorderSide(color: colors[variant] ?? _primary, width: 3),
            ),
          ),
          child: Text(
            content,
            style: TextStyle(
              fontSize: 14,
              color: colors[variant] ?? _primary,
              height: 1.5,
            ),
          ),
        );

      default: // text
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Text(
            content,
            style: TextStyle(
              fontSize: 15,
              height: 1.7,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_tutorial == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('教程')),
        body: const Center(child: Text('教程不存在')),
      );
    }

    final t = _tutorial!;
    final title = t['title'] as String? ?? '';
    final username = t['username'] as String? ?? '';
    final avatar = t['avatar'] as String?;
    final likes = (t['likes'] as num?)?.toInt() ?? 0;
    final views = (t['views'] as num?)?.toInt() ?? 0;
    final coverImage = t['cover_image'] as String?;
    final createdAt = (t['created_at'] as num?)?.toInt() ?? 0;

    // 格式化时间（后端时间戳是秒级）
    final dt = DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);
    final dateStr =
        '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

    // 解析 tags：可能是 List 或 JSON 字符串
    var tags = <String>[];
    final rawTags = t['tags'];
    if (rawTags is List) {
      tags = rawTags.map((e) => e.toString()).toList();
    } else if (rawTags is String && rawTags.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawTags);
        if (decoded is List) tags = decoded.map((e) => e.toString()).toList();
      } catch (_) {}
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: coverImage?.isNotEmpty == true ? 220 : 0,
            pinned: true,
            backgroundColor: Theme.of(context).cardColor,
            foregroundColor: Theme.of(context).textTheme.bodyLarge?.color,
            elevation: 0,
            flexibleSpace: coverImage?.isNotEmpty == true
                ? FlexibleSpaceBar(
                    background: CachedNetworkImage(
                      imageUrl: coverImage!,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) =>
                          Container(color: const Color(0xFFEEF0FF)),
                    ),
                  )
                : null,
          ),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                ),
                if (tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Wrap(
                      spacing: 6,
                      children: tags
                          .map(
                            (tag) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEEF0FF),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                tag,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF4F46E5),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                GestureDetector(
                  onTap: username.isEmpty
                      ? null
                      : () => context.push('/users/$username'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        _buildAuthorAvatar(avatar, username),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              username,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              dateStr,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                ..._blocks.map(
                  (b) => _buildBlock(Map<String, dynamic>.from(b as Map)),
                ),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: _toggleLike,
              child: Row(
                children: [
                  Icon(
                    _liked ? Icons.favorite : Icons.favorite_outline,
                    color: _liked ? Colors.red : Colors.grey,
                    size: 22,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$likes',
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            Row(
              children: [
                const Icon(
                  Icons.visibility_outlined,
                  color: Colors.grey,
                  size: 22,
                ),
                const SizedBox(width: 4),
                Text(
                  '$views',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.share_outlined),
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
  }
}
