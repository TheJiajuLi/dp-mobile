import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

// 单篇文章的数据层——拉详情 + 解析 blocks + 抽目录 + 点赞/收藏状态。手机阅读页
// 和 HD 中间阅读面板共用同一份：手机 watch(articleProvider(widget.tutorialId))，
// HD watch(articleProvider(selectedArticleId))。autoDispose family：换文章即重
// 载，够用不过度缓存。
//
// 从 tutorial_detail_screen 的 _load / _toc / _toggleLike / _toggleSave 抽出，
// 行为保持一致（乐观更新、失败不动 state 由调用方弹提示）。
class ArticleState {
  final bool loading;
  final Map<String, dynamic>? tutorial;
  final List<dynamic> blocks;
  final List<Map<String, dynamic>> toc;
  final bool liked;
  final bool saved;
  final int likes;
  final int saveCount;
  final String? error;

  const ArticleState({
    this.loading = true,
    this.tutorial,
    this.blocks = const [],
    this.toc = const [],
    this.liked = false,
    this.saved = false,
    this.likes = 0,
    this.saveCount = 0,
    this.error,
  });

  // 作者是否允许转载——后端 allow_repost（0/1，默认 1）。关闭时 chrome 隐藏
  // 导出/分享入口。拿不到默认 true 安全降级
  bool get allowRepost {
    final v = tutorial?['allow_repost'];
    if (v == null) return true;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v.toString().toLowerCase();
    return s != '0' && s != 'false';
  }

  ArticleState copyWith({
    bool? loading,
    Map<String, dynamic>? tutorial,
    List<dynamic>? blocks,
    List<Map<String, dynamic>>? toc,
    bool? liked,
    bool? saved,
    int? likes,
    int? saveCount,
    String? error,
  }) {
    return ArticleState(
      loading: loading ?? this.loading,
      tutorial: tutorial ?? this.tutorial,
      blocks: blocks ?? this.blocks,
      toc: toc ?? this.toc,
      liked: liked ?? this.liked,
      saved: saved ?? this.saved,
      likes: likes ?? this.likes,
      saveCount: saveCount ?? this.saveCount,
      error: error ?? this.error,
    );
  }
}

final articleProvider = StateNotifierProvider.autoDispose
    .family<ArticleNotifier, ArticleState, String>(
      (ref, tutorialId) => ArticleNotifier(ref, tutorialId)..load(),
    );

class ArticleNotifier extends StateNotifier<ArticleState> {
  ArticleNotifier(this._ref, this._id) : super(const ArticleState());

  final Ref _ref;
  final String _id;

  Future<void> load() async {
    final api = _ref.read(apiClientProvider);
    final res = await api.get('/auth/tutorials/$_id');
    if (!res.success || res.data == null) {
      if (!mounted) return;
      state = state.copyWith(
        loading: false,
        error: res.message ?? 'load failed',
      );
      return;
    }
    final t = res.data as Map<String, dynamic>;

    // blocks 可能是 JSON 字符串或已解析的 List，两种都兼容（跟旧 reader 一致）
    var blocks = <dynamic>[];
    final raw = t['blocks'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final d = jsonDecode(raw);
        if (d is List) blocks = d;
      } catch (_) {}
    } else if (raw is List) {
      blocks = raw;
    }

    if (!mounted) return;
    state = ArticleState(
      loading: false,
      tutorial: t,
      blocks: blocks,
      toc: buildToc(blocks),
      // 后端字段名未确认，兼容 is_liked/liked、is_saved/saved，且兼容 0/1 与 bool
      liked: t['is_liked'] == 1 || t['is_liked'] == true || t['liked'] == true,
      saved: t['is_saved'] == 1 || t['is_saved'] == true || t['saved'] == true,
      likes: (t['likes'] as num?)?.toInt() ?? 0,
      saveCount: (t['save_count'] as num?)?.toInt() ?? 0,
    );
  }

  // 从 blocks 抽 heading → 目录项 {index(块下标), level(1/2/3), text}。只有
  // heading 进目录（跟旧 reader _toc 一致）。HD 右侧目录面板 + 手机目录 sheet 都读它
  static List<Map<String, dynamic>> buildToc(List<dynamic> blocks) {
    final items = <Map<String, dynamic>>[];
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      if (b is Map && b['type'] == 'heading') {
        final text = (b['content']?.toString() ?? '').trim();
        if (text.isEmpty) continue;
        items.add({
          'index': i,
          'level': (b['level'] as num?)?.toInt() ?? 2,
          'text': text,
        });
      }
    }
    return items;
  }

  // 返回是否成功——失败时不动 state，由调用方（chrome）弹提示（保持旧行为）
  Future<bool> toggleLike() async {
    final api = _ref.read(apiClientProvider);
    final res = state.liked
        ? await api.delete('/auth/tutorials/$_id/like')
        : await api.post('/auth/tutorials/$_id/like');
    if (!res.success) return false;
    if (!mounted) return true;
    final now = !state.liked;
    state = state.copyWith(
      liked: now,
      likes: now ? state.likes + 1 : (state.likes > 0 ? state.likes - 1 : 0),
    );
    return true;
  }

  Future<bool> toggleSave() async {
    final api = _ref.read(apiClientProvider);
    final res = state.saved
        ? await api.delete('/auth/tutorials/$_id/save')
        : await api.post('/auth/tutorials/$_id/save');
    if (!res.success) return false;
    if (!mounted) return true;
    final now = !state.saved;
    state = state.copyWith(
      saved: now,
      saveCount: now
          ? state.saveCount + 1
          : (state.saveCount > 0 ? state.saveCount - 1 : 0),
    );
    return true;
  }
}
