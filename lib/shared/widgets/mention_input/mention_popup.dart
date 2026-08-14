import 'dart:async';
import '../../../core/theme/app_colors.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

/// @ 提及的用户搜索浮层，两种数据来源：
/// - [candidates] == null（评论场景）：走全站搜索接口 GET /auth/search
///   （返回 tutorials + users + tags），这里只取 data['users']；
/// - [candidates] != null（群聊场景）：直接对传入的成员列表本地过滤，
///   不发任何网络请求，query 为空时展示前几个成员。
/// 两种模式都最多展示 6 个。
///
/// 自身不碰输入框：命中的用户名通过 [onSelect] 回调交给外部，由外部用
/// MentionQuery.insert 写回它自己的 controller。
class MentionPopup extends ConsumerStatefulWidget {
  final String query;
  final void Function(String username) onSelect;
  // 本地候选（群成员）。传了就走本地过滤，不打接口
  final List<Map<String, dynamic>>? candidates;

  const MentionPopup({
    super.key,
    required this.query,
    required this.onSelect,
    this.candidates,
  });

  @override
  ConsumerState<MentionPopup> createState() => _MentionPopupState();
}

class _MentionPopupState extends ConsumerState<MentionPopup> {
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  Timer? _debounce;
  // 防止慢请求回来盖掉新请求的结果：只认最后一次发起的查询词
  String _inFlight = '';

  @override
  void initState() {
    super.initState();
    _search(widget.query);
  }

  @override
  void didUpdateWidget(MentionPopup old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) {
      // 本地候选无需 debounce，直接即时过滤；只有走网络的全站搜索才防抖
      if (widget.candidates != null) {
        _search(widget.query);
      } else {
        _debounce?.cancel();
        _debounce = Timer(
          const Duration(milliseconds: 200),
          () => _search(widget.query),
        );
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _search(String q) async {
    // 群成员等本地候选：不打接口，直接按用户名过滤（q 为空时展示前几个）
    final candidates = widget.candidates;
    if (candidates != null) {
      final lower = q.toLowerCase();
      if (!mounted) return;
      setState(() {
        _results = candidates
            .where(
              (u) => ((u['username'] as String?) ?? '')
                  .toLowerCase()
                  .contains(lower),
            )
            .take(6)
            .toList();
        _loading = false;
      });
      return;
    }
    // 刚敲下 @ 还没输入任何字符时不打接口，浮层留空
    if (q.isEmpty) {
      if (mounted) setState(() => _results = []);
      return;
    }
    _inFlight = q;
    setState(() => _loading = true);
    final res = await ref
        .read(apiClientProvider)
        .get('/auth/search', queryParameters: {'q': q});
    if (!mounted || _inFlight != q) return;
    if (res.success && res.data is Map) {
      final users = ((res.data as Map)['users'] as List?) ?? const [];
      setState(() {
        _results = users
            .take(6)
            .map((u) => Map<String, dynamic>.from(u as Map))
            .toList();
        _loading = false;
      });
    } else {
      setState(() {
        _results = [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) {
      return Container(
        height: 44,
        alignment: Alignment.center,
        margin: const EdgeInsets.only(bottom: 8),
        child: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_results.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFEBEBEB),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: _results.length,
        separatorBuilder: (_, __) => Divider(
          height: 0.5,
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFEBEBEB),
        ),
        itemBuilder: (ctx, i) => _buildRow(_results[i], isDark),
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> u, bool isDark) {
    final username = u['username'] as String? ?? '';
    final isAurora =
        u['is_aurora_creator'] == 1 || u['is_aurora_creator'] == true;
    final bio = u['bio'] as String?;
    final handle = u['handle'] as String? ?? username;

    return GestureDetector(
      onTap: () => widget.onSelect(username),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: AppColors.primary,
              child: Text(
                username.isNotEmpty ? username[0].toUpperCase() : 'U',
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.9)
                                : const Color(0xFF1A1A1A),
                          ),
                        ),
                      ),
                      if (isAurora) ...[
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A0E2E),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            '★ 极光',
                            style: TextStyle(
                              fontSize: 9,
                              color: Color(0xFFF59E0B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (bio != null && bio.isNotEmpty)
                    Text(
                      bio,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.4)
                            : Colors.grey[500],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '@$handle',
              style: TextStyle(
                fontSize: 10,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.3)
                    : Colors.grey[400],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
