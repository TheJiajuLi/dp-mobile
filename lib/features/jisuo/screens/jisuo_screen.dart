import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/jisuo_refresh_signal.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/formula_error.dart';
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

  // 底部输入框的模式：ai=小梦直答 / community=社区提问。只影响 hint 文案和
  // 发送后的落点
  String _mode = 'ai';

  // 回答态：一提问就进入——隐藏底部导航栏(jisuoImmersiveProvider)、左上角出
  // 返回键，小梦的回答在分割线下方流式输出
  bool _answerMode = false;
  String _askedQuestion = '';
  String _answer = '';
  bool _answering = false;
  String? _convId;

  static const _sampleQuestions = [
    '量子纠缠真的可以超光速通信吗？',
    'Python 和 R 哪个更适合数据分析？',
    '为什么黑洞不会把自己吞掉？',
  ];

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
    return Map<String, dynamic>.from(res.data as Map);
  }

  void _startQuestion(String q) => _askInline(q);

  // 小梦直答：进入回答态，流式拉 /auth/xmeng/chat/stream，回答实时追加到
  // _answer，就在本页分割线下方渲染
  Future<void> _askInline(String question) async {
    final q = question.trim();
    if (q.isEmpty || _answering) return;
    _inputCtrl.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _answerMode = true;
      _askedQuestion = q;
      _answer = '';
      _answering = true;
    });
    ref.read(jisuoImmersiveProvider.notifier).state = true;

    try {
      final response = await ref
          .read(apiClientProvider)
          .dio
          .post(
            '/auth/xmeng/chat/stream',
            data: {
              'message': q,
              if (_convId != null) 'conversationId': _convId,
            },
            options: Options(
              responseType: ResponseType.stream,
              receiveTimeout: const Duration(seconds: 120),
            ),
          );
      final body = response.data as ResponseBody;
      final lines = body.stream
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      String? errorMessage;
      await for (final line in lines) {
        if (!mounted) return;
        if (!line.startsWith('data:')) continue;
        final jsonStr = line.substring(5).trim();
        if (jsonStr.isEmpty) continue;
        final data = jsonDecode(jsonStr) as Map<String, dynamic>;
        switch (data['type']) {
          case 'meta':
          case 'done':
            _convId = data['conversationId']?.toString() ?? _convId;
            break;
          case 'chunk':
            setState(() => _answer += data['text']?.toString() ?? '');
            break;
          case 'error':
            errorMessage = data['message']?.toString() ?? '小梦暂时休息中，请稍后再试';
            break;
        }
      }
      if (!mounted) return;
      setState(() => _answering = false);
      if (errorMessage != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage)));
      }
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _answering = false);
      final msg = e.response?.data is Map
          ? ((e.response!.data as Map)['message']?.toString() ??
                '小梦暂时休息中，请稍后再试')
          : '小梦暂时休息中，请稍后再试';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  // 返回键：退出回答态，回落地页，恢复底部导航栏
  void _exitAnswerMode() {
    ref.read(jisuoImmersiveProvider.notifier).state = false;
    setState(() {
      _answerMode = false;
      _askedQuestion = '';
      _answer = '';
      _answering = false;
    });
  }

  // 清空回答：清掉当前一问一答，停在回答态等下一次提问
  void _clearAnswer() {
    setState(() {
      _askedQuestion = '';
      _answer = '';
      _answering = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      // 装饰性星云/光晕要铺到状态栏后面才是完整的背景——之前包在
      // SafeArea 里面，SafeArea 顶部内边距会把这层背景一起往下推，
      // 状态栏那一条就会露出 scaffoldBackgroundColor 的纯色，跟下面
      // 的渐变背景断成两截，看起来像一块白条盖住了背景。挪到 SafeArea
      // 外层、Scaffold body 的 Stack 底层，跟首页极光光晕同一个做法
      body: Stack(
        children: [
          if (!_answerMode)
            Positioned.fill(
              child: IgnorePointer(
                child: isDark
                    ? const CustomPaint(painter: _NebulaPainter(isDark: true))
                    : Stack(
                        children: [
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
                        ],
                      ),
              ),
            ),
          SafeArea(
            bottom: false,
            child: _answerMode
                ? _buildAnswerMode(isDark)
                : _buildLanding(isDark),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomInput(isDark),
    );
  }

  Widget _buildLanding(bool isDark) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildHero(isDark)),
        SliverToBoxAdapter(child: _buildModeChips(isDark)),
        const SliverToBoxAdapter(child: SizedBox(height: 20)),
      ],
    );
  }

  Widget _buildHero(bool isDark) {
    // 星云/光晕装饰层挪到 Scaffold body 的 Stack 底层了（build()
    // 里，SafeArea 外面），这里只剩文字内容本身
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.5,
      child: Stack(
        children: [
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

  void _submit() {
    // community 模式走社区提问 Sheet；ai 模式在本页流式直答
    if (_mode == 'community') {
      _showAskSheet();
      return;
    }
    _askInline(_inputCtrl.text);
  }

  Widget _buildBottomInput(bool isDark) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 100),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : const Color(0xFFF0F0F8),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Theme.of(context).dividerColor,
                      width: 0.5,
                    ),
                  ),
                  child: TextField(
                    controller: _inputCtrl,
                    minLines: 1,
                    maxLines: 4,
                    // community 模式输入框只当"打开提问 Sheet"的按钮用
                    readOnly: _mode == 'community',
                    onTap: _mode == 'community' ? _showAskSheet : null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _submit(),
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: _mode == 'ai' ? '问小梦任何问题...' : '提问，让社区来回答...',
                      hintStyle: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[400],
                      ),
                      prefixIcon: Icon(
                        Icons.edit_outlined,
                        size: 16,
                        color: Colors.grey[400],
                      ),
                      prefixIconConstraints: const BoxConstraints(minWidth: 40),
                      filled: false,
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _answering ? null : _submit,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _answering ? Colors.grey[400] : _primary,
                    shape: BoxShape.circle,
                  ),
                  child: _answering
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send, size: 18, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 回答态 ─────────────────────────────────────────────────────────
  Widget _buildAnswerMode(bool isDark) {
    return Column(
      children: [
        // 顶栏：返回(退出回答态) + 历史对话 + 清空回答
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 2),
          child: Row(
            children: [
              GestureDetector(
                onTap: _exitAnswerMode,
                child: const SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(Icons.arrow_back_ios, size: 18),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: '历史对话',
                icon: const Icon(Icons.history, size: 20),
                color: Colors.grey[500],
                onPressed: () => context.push('/xiaomeng/history'),
              ),
              IconButton(
                tooltip: '清空回答',
                icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                color: Colors.grey[500],
                onPressed: _clearAnswer,
              ),
            ],
          ),
        ),
        Expanded(
          child: _askedQuestion.isEmpty
              ? Center(
                  child: Text(
                    '清空了，换个问题再问问小梦',
                    style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  children: [
                    // 问题（用户气泡，右对齐）
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.75,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: const BoxDecoration(
                          color: _primary,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(16),
                            topRight: Radius.circular(16),
                            bottomLeft: Radius.circular(16),
                            bottomRight: Radius.circular(4),
                          ),
                        ),
                        child: Text(
                          _askedQuestion,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 16),
                    // 回答（分割线下方流式输出）
                    if (_answer.isEmpty && _answering)
                      Row(
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _primary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '小梦正在思考...',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      )
                    else
                      ..._buildAnswerContent(_answer, isDark),
                  ],
                ),
        ),
      ],
    );
  }

  // 跟小梦对话页同一套解析：``` 代码块 / $公式$ / 其余文字
  List<Widget> _buildAnswerContent(String content, bool isDark) {
    final regex = RegExp(
      r'```(\w*)\n([\s\S]*?)```'
      r'|\$\$([\s\S]*?)\$\$'
      r'|\$([^\$\n]+)\$',
    );
    final widgets = <Widget>[];
    var last = 0;
    for (final m in regex.allMatches(content)) {
      if (m.start > last) {
        final t = content.substring(last, m.start).trim();
        if (t.isNotEmpty) widgets.add(_ansText(t, isDark));
      }
      if (m.group(2) != null) {
        widgets.add(_ansCode(m.group(2) ?? '', (m.group(1) ?? '').trim()));
      } else {
        final f = m.group(3) ?? m.group(4) ?? '';
        widgets.add(_ansFormula(f, isDark, isDisplay: m.group(3) != null));
      }
      last = m.end;
    }
    if (last < content.length) {
      final t = content.substring(last).trim();
      if (t.isNotEmpty) widgets.add(_ansText(t, isDark));
    }
    if (widgets.isEmpty) widgets.add(_ansText(content, isDark));
    return widgets;
  }

  Widget _ansText(String t, bool isDark) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Text(
      t,
      style: TextStyle(
        fontSize: 15,
        height: 1.7,
        color: isDark ? const Color(0xFFC8CAD8) : const Color(0xFF2A2A2A),
      ),
    ),
  );

  Widget _ansCode(String code, String lang) => Container(
    margin: const EdgeInsets.symmetric(vertical: 8),
    width: double.infinity,
    decoration: BoxDecoration(
      color: const Color(0xFF1E1E2E),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
          child: Row(
            children: [
              Text(
                lang.isEmpty ? 'CODE' : lang.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF9B9EF8),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: code));
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
                },
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Text(
                    '复制',
                    style: TextStyle(fontSize: 10, color: Color(0xFF9B9EF8)),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              code.trim(),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Color(0xFFE0E0FF),
                height: 1.6,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _ansFormula(String tex, bool isDark, {bool isDisplay = true}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Math.tex(
            tex.trim(),
            mathStyle: isDisplay ? MathStyle.display : MathStyle.text,
            textStyle: TextStyle(
              fontSize: isDisplay ? 17 : 15,
              color: isDark ? const Color(0xFF9B9EF8) : const Color(0xFF4F46E5),
            ),
            onErrorFallback: (_) => const FormulaErrorPlaceholder(),
          ),
        ),
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
    const blobColors = [
      Color(0xFF6366F1),
      Color(0xFF8B5CF6),
      Color(0xFF3B82F6),
    ];
    final blobAlphas = isDark
        ? const [0.35, 0.22, 0.18]
        : const [0.10, 0.07, 0.05];
    final positions = [
      Offset(size.width * 0.78, size.height * 0.28),
      Offset(size.width * 0.92, size.height * 0.6),
      Offset(size.width * 0.55, size.height * 0.1),
    ];
    final radii = [size.width * 0.32, size.width * 0.22, size.width * 0.18];

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
  bool shouldRepaint(_NebulaPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
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
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _done ? _buildSuccess() : _buildForm(),
    );
  }

  Widget _buildForm() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canPost = _ctrl.text.trim().length >= 10 && _domain != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.only(top: 10, bottom: 4),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[700] : Colors.grey[200],
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
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.grey[100],
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
                        color: on
                            ? jisuoDomainBg(d)
                            : isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.grey[50],
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: on
                              ? jisuoDomainColor(d)
                              : isDark
                              ? Colors.white.withValues(alpha: 0.12)
                              : Colors.grey[200]!,
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        d,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: on ? FontWeight.w500 : FontWeight.normal,
                          color: on
                              ? jisuoDomainColor(d)
                              : isDark
                              ? Colors.grey[400]
                              : Colors.grey[600],
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
                    Text(
                      '匿名提问',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? const Color(0xFFE0E2F0)
                            : const Color(0xFF374151),
                      ),
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
                backgroundColor: isDark ? _primary : const Color(0xFF1A1A1A),
                foregroundColor: Colors.white,
                elevation: 0,
                disabledBackgroundColor: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.grey[200],
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
