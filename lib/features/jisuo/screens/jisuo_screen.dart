import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/jisuo_refresh_signal.dart';
import '../../../core/network/api_client.dart';
import '../../../features/auth/auth_service.dart';
import '../../messages/utils/message_avatar.dart';

const _primary = Color(0xFF6366F1);

// 提问领域配色——提问 Sheet 的领域选择跟热门提问卡片的领域标签共用同一套
Color jisuoDomainColor(String d) => switch (d) {
  '编程开发' => const Color(0xFF6366F1),
  '数学' => const Color(0xFFD97706),
  '天体物理' => const Color(0xFF8B5CF6),
  '经济' => const Color(0xFF16A34A),
  '生命科学' => const Color(0xFFDC2626),
  _ => const Color(0xFF6B7280),
};

Color jisuoDomainBg(String d) => switch (d) {
  '编程开发' => const Color(0xFFEEF0FF),
  '数学' => const Color(0xFFFEF3C7),
  '天体物理' => const Color(0xFFF3E8FF),
  '经济' => const Color(0xFFDCFCE7),
  '生命科学' => const Color(0xFFFEE2E2),
  _ => const Color(0xFFF3F4F6),
};

class JisuoScreen extends ConsumerStatefulWidget {
  const JisuoScreen({super.key});

  @override
  ConsumerState<JisuoScreen> createState() => _JisuoScreenState();
}

class _JisuoScreenState extends ConsumerState<JisuoScreen> {
  final _inputCtrl = TextEditingController();
  // "社区精选"/"为你推荐"之前是两个独立分区，但其实是同一个接口
  // （GET /auth/questions，按 view_count DESC, created_at DESC 排序）
  // 翻两页拉出来的——后端没有真正意义上"跟当前用户匹配"的打分能力，
  // "为你推荐"名不副实，合并成一个列表更诚实：第二页只是按 id 去重后
  // 追加在第一页后面，不是另一种排序/来源
  List<Map<String, dynamic>> _hotQuestions = [];

  // 极索是底部导航的常驻分支（跟"我的" tab 一样，切账号只是 goBranch
  // 跳回首页，不会重新 initState），热门提问只在 initState 拉过一次，
  // 不会跟着账号切换自动刷新——用户切完账号如果又点回极索 tab，看到的
  // 可能还是上一个账号在时拉到的数据。跟 user_profile_screen.dart 里
  // "我的" tab 同一个套路：build() 里发现 currentUserProvider 变了就
  // 补一次重新加载
  String? _loadedForUserId;
  bool _reloadingForAccountChange = false;
  final Set<String> _removingQuestionIds = {};

  // 底部输入框的模式：ai=小梦直答 / community=社区提问。只影响输入框点击后
  // 的落点和 hint 文案
  String _mode = 'ai';

  static const _sampleQuestions = [
    '量子纠缠真的可以超光速通信吗？',
    'Python 和 R 哪个更适合数据分析？',
    '为什么黑洞不会把自己吞掉？',
  ];

  @override
  void initState() {
    super.initState();
    _loadHotQuestions();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  void _showAskSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AskSheet(onPost: _postQuestion),
    );
  }

  Future<void> _loadHotQuestions() async {
    _loadedForUserId = ref.read(currentUserProvider)?.id;
    final res = await ref
        .read(apiClientProvider)
        .get('/auth/questions', queryParameters: {'limit': 10});
    if (!mounted || !res.success || res.data == null) return;
    setState(() {
      _hotQuestions = ((res.data['questions'] as List?) ?? [])
          .map((q) => Map<String, dynamic>.from(q as Map))
          .toList();
    });
    unawaited(_loadRecommendedQuestions());
  }

  Future<void> _loadRecommendedQuestions() async {
    final res = await ref
        .read(apiClientProvider)
        .get('/auth/questions', queryParameters: {'limit': 10, 'offset': 10});
    if (!mounted || !res.success || res.data == null) return;
    final existingIds = _hotQuestions.map((q) => q['id'].toString()).toSet();
    final more = ((res.data['questions'] as List?) ?? [])
        .map((q) => Map<String, dynamic>.from(q as Map))
        .where((q) => !existingIds.contains(q['id'].toString()))
        .toList();
    if (more.isEmpty) return;
    setState(() => _hotQuestions.addAll(more));
  }

  Future<Map<String, dynamic>> _postQuestion(
    String text,
    String domain,
    bool anon,
  ) async {
    final res = await ref
        .read(apiClientProvider)
        .post(
          '/auth/questions',
          data: {'text': text, 'domain': domain, 'isAnonymous': anon},
        );
    if (!res.success || res.data == null) {
      throw Exception(res.message ?? '发布失败，请稍后重试');
    }
    unawaited(_loadHotQuestions());
    return Map<String, dynamic>.from(res.data as Map);
  }

  // 问题详情页删除问题成功后 pop 一个 {'deleted': true, 'questionId': ...}
  // 回来——先淡出对应卡片再从列表移除，同时 jisuoRefreshSignalProvider
  // 也会被通知到，覆盖不是从这里直接跳转过去的删除场景（比如从通知点进详情页）
  Future<void> _openQuestion(Map<String, dynamic> q) async {
    final result = await context.push('/questions/${q['id']}', extra: q);
    if (!mounted) return;
    if (result is Map && result['deleted'] == true) {
      final id = result['questionId']?.toString();
      if (id != null) _removeQuestionCard(id);
    }
  }

  void _removeQuestionCard(String id) {
    setState(() => _removingQuestionIds.add(id));
    Future.delayed(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      setState(() {
        _hotQuestions.removeWhere((q) => q['id'].toString() == id);
        _removingQuestionIds.remove(id);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(currentUserProvider)?.id;
    if (!_reloadingForAccountChange &&
        currentUserId != null &&
        currentUserId != _loadedForUserId) {
      _reloadingForAccountChange = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted) await _loadHotQuestions();
        _reloadingForAccountChange = false;
      });
    }
    // 发布回答会让某个问题的 answer_count 变化，但极索是常驻分支不会
    // 自动重新拉——跟 profile_refresh_signal.dart 同一个套路
    ref.listen<int>(jisuoRefreshSignalProvider, (prev, next) {
      if (prev != next) _loadHotQuestions();
    });
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 极索是"深空感·沉浸式"落地页：用比全局主题更黑的 #0A0A0F / 更白的
    // #FAFAF8 做背景，Hero 星空 + 大留白 + 单一紫色强调色
    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0A0A0F)
          : const Color(0xFFFAFAF8),
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHero(isDark)),
            SliverToBoxAdapter(child: _buildModeChips(isDark)),
            // 混合：Hero 之下保留"社区精选/热门问题"内容，不白丢社区问答
            SliverToBoxAdapter(child: _buildJmDivider('社区精选')),
            SliverToBoxAdapter(child: _buildHotQuestions()),
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomInput(isDark),
    );
  }

  void _startQuestion(String q) => _askXiaoMeng(q);

  Widget _buildHero(bool isDark) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.5,
      child: Stack(
        children: [
          // 深色：星空/星云装饰（复用现有 _NebulaPainter）；浅色：一团很淡的
          // 紫色光晕
          if (isDark)
            const Positioned.fill(
              child: CustomPaint(painter: _NebulaPainter(isDark: true)),
            )
          else
            Positioned(
              top: -60,
              left: -40,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _primary.withValues(alpha: 0.06),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      height: 1.3,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                    ),
                    children: const [
                      TextSpan(text: '用'),
                      TextSpan(
                        text: '提问',
                        style: TextStyle(color: _primary),
                      ),
                      TextSpan(text: '发现世界'),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '极梦 · 知识问答社区',
                  style: TextStyle(
                    fontSize: 13,
                    letterSpacing: 0.5,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.45)
                        : Colors.grey[400],
                  ),
                ),
                const SizedBox(height: 36),
                ..._sampleQuestions.map(
                  (q) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: GestureDetector(
                      onTap: () => _startQuestion(q),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : _primary.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.1)
                                : _primary.withValues(alpha: 0.15),
                            width: 0.5,
                          ),
                        ),
                        child: Text(
                          q,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.75)
                                : const Color(0xFF1A1A1A),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeChips(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          _modeChip(
            isDark,
            label: '小梦直答',
            icon: Icons.auto_awesome,
            mode: 'ai',
          ),
          const SizedBox(width: 8),
          _modeChip(
            isDark,
            label: '社区提问',
            icon: Icons.people_outline,
            mode: 'community',
          ),
        ],
      ),
    );
  }

  Widget _modeChip(
    bool isDark, {
    required String label,
    required IconData icon,
    required String mode,
  }) {
    final selected = _mode == mode;
    return GestureDetector(
      onTap: () => setState(() => _mode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? _primary
              : isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? Colors.white : Colors.grey[400],
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: selected ? Colors.white : Colors.grey[400],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomInput(bool isDark) {
    // ai 模式点了进小梦对话；community 模式点了弹社区提问 Sheet
    void onTap() => _mode == 'ai' ? _openXiaoMeng() : _showAskSheet();
    return Container(
      color: isDark ? const Color(0xFF0A0A0F) : const Color(0xFFFAFAF8),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: isDark
                    ? const Color(0xFF1A1A1A)
                    : const Color(0xFFEBEBEB),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF17171F)
                          : const Color(0xFFF0F0F8),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : const Color(0xFFEBEBEB),
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.edit_outlined,
                          size: 16,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _mode == 'ai' ? '问小梦任何问题...' : '提问，让社区来回答...',
                          style: TextStyle(fontSize: 14, color: Colors.grey[400]),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: onTap,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: _primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.send, size: 18, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAuroraIcon(double size) {
    return CustomPaint(
      size: Size(size, size * 0.85),
      painter: _AuroraIconPainter(),
    );
  }

  Widget _buildJmDivider(String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: Colors.grey.withValues(alpha: 0.15),
              thickness: 0.5,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0D0A1E) : const Color(0xFFEEF0FF),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                  width: 0.5,
                ),
              ),
              child: Row(
                children: [
                  _buildAuroraIcon(12),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.85)
                          : const Color(0xFF6366F1),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: Colors.grey.withValues(alpha: 0.15),
              thickness: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  // 头像叠加用的固定配色——跟专家名单那套调色板保持一致
  static const _avatarColors = [
    Color(0xFF6366F1),
    Color(0xFFD97706),
    Color(0xFF16A34A),
  ];

  Widget _buildHotQuestions() {
    if (_hotQuestions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '热门提问',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.grey[400],
              letterSpacing: .04,
            ),
          ),
          const SizedBox(height: 8),
          ..._hotQuestions.map((q) => _hotQuestionCard(q)),
        ],
      ),
    );
  }

  Widget _hotQuestionCard(Map<String, dynamic> q) {
    final domain = q['domain'] as String? ?? '';
    final answerCount = (q['answer_count'] as num?)?.toInt() ?? 0;
    final viewCount = (q['view_count'] as num?)?.toInt() ?? 0;
    final invitedCount = (q['invited_count'] as num?)?.toInt() ?? 0;
    final avatarCount = answerCount < 3 ? answerCount : 3;
    final questionId = q['id'].toString();
    final askerId = q['asker_id']?.toString();
    final isOwn =
        askerId != null && askerId == ref.watch(currentUserProvider)?.id;
    final removing = _removingQuestionIds.contains(questionId);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      opacity: removing ? 0 : 1,
      child: GestureDetector(
        onTap: () => _openQuestion(q),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.grey.withValues(alpha: isDark ? 0.12 : 0.08),
              width: 0.5,
            ),
            // 跟 tutorial_list_card.dart 同款处理——浅色下用很淡的投影
            // 撑出卡片的浮起感，深色下阴影没意义，靠上面那圈描边区分
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: jisuoDomainBg(domain),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      domain,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: jisuoDomainColor(domain),
                      ),
                    ),
                  ),
                  if (isOwn) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A0E2E),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '我的',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFF59E0B),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      q['text'] as String,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  SizedBox(
                    width: avatarCount * 14.0 + 4,
                    height: 20,
                    child: Stack(
                      children: List.generate(
                        avatarCount,
                        (i) => Positioned(
                          left: i * 14.0,
                          child: CircleAvatar(
                            radius: 9,
                            backgroundColor: Colors.white,
                            child: CircleAvatar(
                              radius: 8,
                              backgroundColor:
                                  _avatarColors[i % _avatarColors.length],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$answerCount 个回答',
                    style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.remove_red_eye_outlined,
                    size: 12,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '$viewCount',
                    style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                  ),
                  const Spacer(),
                  if (invitedCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.phone_in_talk,
                            size: 10,
                            color: Color(0xFFF59E0B),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '已邀请 $invitedCount 位专家',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFFF59E0B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 之前这里跳的是 /aria——那是个纯占位屏，没有真的对话能力。小梦对话
  // 页（/xiaomeng）已经真实做完了，这两个入口改跳过去，不然同一个页面
  // 顶部"问问小梦"输入框/快捷问题点了还是假的，跟下面页面里新加的"问问
  // 小梦"入口条一真一假，观感很割裂
  void _openXiaoMeng() => context.push('/xiaomeng');

  void _askXiaoMeng(String question) => context.push(
    '/xiaomeng/chat',
    extra: {'initialMessage': question},
  );
}

// 小梦卡片背景的星云光晕——几个高斯模糊的色块叠加出星云glow，加几道
// 螺旋光带模拟旋涡星系，深色模式下再撒几颗星点。静态画一次，不跟手势/
// 动画联动，shouldRepaint 只在主题切换时才需要真的重画
class _NebulaPainter extends CustomPainter {
  final bool isDark;
  const _NebulaPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    const blobColors = [Color(0xFF6366F1), Color(0xFF8B5CF6), Color(0xFF3B82F6)];
    final blobAlphas = isDark
        ? const [0.35, 0.22, 0.18]
        : const [0.10, 0.07, 0.05];
    final positions = [
      Offset(size.width * 0.78, size.height * 0.28),
      Offset(size.width * 0.92, size.height * 0.6),
      Offset(size.width * 0.55, size.height * 0.1),
    ];
    final radii = [
      size.width * 0.32,
      size.width * 0.22,
      size.width * 0.18,
    ];

    for (var i = 0; i < blobColors.length; i++) {
      final paint = Paint()
        ..color = blobColors[i].withValues(alpha: blobAlphas[i])
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radii[i] * 0.5);
      canvas.drawCircle(positions[i], radii[i], paint);
    }

    final swirlPaint = Paint()
      ..color = (isDark ? Colors.white : _primary).withValues(
        alpha: isDark ? 0.12 : 0.06,
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    final center = Offset(size.width * 0.8, size.height * 0.35);
    for (var i = 0; i < 3; i++) {
      final r = size.width * (0.12 + i * 0.08);
      final path = Path()
        ..addArc(Rect.fromCircle(center: center, radius: r), -0.6, 3.4);
      canvas.drawPath(path, swirlPaint);
    }

    if (isDark) {
      final starPaint = Paint()..color = Colors.white.withValues(alpha: 0.5);
      for (final s in const [
        Offset(0.15, 0.2),
        Offset(0.35, 0.1),
        Offset(0.6, 0.6),
        Offset(0.85, 0.15),
        Offset(0.25, 0.75),
        Offset(0.95, 0.7),
      ]) {
        canvas.drawCircle(
          Offset(size.width * s.dx, size.height * s.dy),
          1.0,
          starPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_NebulaPainter oldDelegate) => oldDelegate.isDark != isDark;
}

// 极光Icon画笔
class _AuroraIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paints = [
      Paint()
        ..color = const Color(0xFF6366F1).withValues(alpha: 0.5)
        ..strokeWidth = size.width * 0.08
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
      Paint()
        ..color = const Color(0xFF818CF8).withValues(alpha: 0.8)
        ..strokeWidth = size.width * 0.08
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
      Paint()
        ..color = const Color(0xFF4ADE80)
        ..strokeWidth = size.width * 0.09
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    ];

    final offsets = [0.0, 0.1, 0.2];
    for (var i = 0; i < 3; i++) {
      final path = Path();
      final y0 = size.height * (0.7 + offsets[i]);
      final cp = Offset(size.width * 0.5, size.height * (0.1 + offsets[i]));
      path.moveTo(0, y0);
      path.quadraticBezierTo(cp.dx, cp.dy, size.width, y0);
      canvas.drawPath(path, paints[i]);
    }
  }

  @override
  bool shouldRepaint(_AuroraIconPainter oldDelegate) => false;
}

class _AskSheet extends StatefulWidget {
  final Future<Map<String, dynamic>> Function(
    String text,
    String domain,
    bool anon,
  )
  onPost;
  const _AskSheet({required this.onPost});

  @override
  State<_AskSheet> createState() => _AskSheetState();
}

class _AskSheetState extends State<_AskSheet> {
  final _ctrl = TextEditingController();
  String? _domain;
  bool _anon = false;
  bool _posting = false;
  bool _done = false;
  int _invitedCount = 0;
  List<Map<String, dynamic>> _experts = [];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  static const _domains = ['编程开发', '数学', '天体物理', '经济', '生命科学', '科普'];

  Future<void> _submit() async {
    if (_ctrl.text.trim().length < 10 || _domain == null) return;
    setState(() => _posting = true);
    try {
      final result = await widget.onPost(_ctrl.text.trim(), _domain!, _anon);
      if (!mounted) return;
      setState(() {
        _posting = false;
        _done = true;
        _invitedCount = (result['invitedCount'] as num?)?.toInt() ?? 0;
        _experts = ((result['experts'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _posting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _done ? _buildSuccess() : _buildForm(),
    );
  }

  Widget _buildForm() {
    final canPost = _ctrl.text.trim().length >= 10 && _domain != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.only(top: 10, bottom: 4),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              const Text(
                '提问',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.close, size: 16, color: Colors.grey[500]),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            '好问题能吸引领域专家作答，尽量描述清楚背景',
            style: TextStyle(fontSize: 12, color: Colors.grey[400]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _ctrl,
            maxLines: 4,
            maxLength: 300,
            onChanged: (_) => setState(() {}),
            autofocus: true,
            decoration: InputDecoration(
              hintText: '你想问什么？',
              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 16),
              border: InputBorder.none,
              counterStyle: TextStyle(fontSize: 11, color: Colors.grey[400]),
            ),
            style: const TextStyle(fontSize: 16, height: 1.6),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '所属领域',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[400],
                  letterSpacing: .04,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _domains.map((d) {
                  final on = _domain == d;
                  return GestureDetector(
                    onTap: () => setState(() => _domain = d),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: on ? jisuoDomainBg(d) : Colors.grey[50],
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: on ? jisuoDomainColor(d) : Colors.grey[200]!,
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        d,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: on ? FontWeight.w500 : FontWeight.normal,
                          color: on ? jisuoDomainColor(d) : Colors.grey[600],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '匿名提问',
                      style: TextStyle(fontSize: 13, color: Color(0xFF374151)),
                    ),
                    Text(
                      '其他用户看不到你的名字',
                      style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _anon,
                onChanged: (v) => setState(() => _anon = v),
                activeThumbColor: const Color(0xFF6366F1),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: canPost && !_posting ? _submit : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1A1A),
                foregroundColor: Colors.white,
                elevation: 0,
                disabledBackgroundColor: Colors.grey[200],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _posting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      '发布提问',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _expertRow(Map<String, dynamic> e) {
    final username = e['username'] as String? ?? '';
    final articleCount = (e['articleCount'] as num?)?.toInt() ?? 0;
    final isAurora = e['isAuroraCreator'] == true;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          buildMessageAvatar(e['avatar'] as String?, username, radius: 12),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    username,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (isAurora) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text(
                      '★ 极光',
                      style: TextStyle(
                        fontSize: 8,
                        color: Color(0xFFF59E0B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 6),
                Text(
                  '$articleCount篇相关内容',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: Color(0xFFEEF0FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_outline,
              size: 30,
              color: Color(0xFF6366F1),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '提问已发布',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            _invitedCount > 0
                ? '极索已根据问题领域\n自动邀请该领域最活跃的创作者为你解答'
                : '暂时还没有该领域的创作者可邀请\n你的问题已经发布，其他人也能看到',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[400],
              height: 1.6,
            ),
          ),
          if (_invitedCount > 0) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1A0E2E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                  width: 0.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('⚡', style: TextStyle(fontSize: 14)),
                      const SizedBox(width: 8),
                      Text(
                        '已邀请 $_invitedCount 位领域创作者',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFF59E0B),
                        ),
                      ),
                    ],
                  ),
                  if (_experts.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    ..._experts.map((e) => _expertRow(e)),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                '好的，期待回答',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
