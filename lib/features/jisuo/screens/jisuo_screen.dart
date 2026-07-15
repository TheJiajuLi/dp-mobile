import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/ai_content_renderer.dart';
import '../../../shared/widgets/tutorial_block_renderer.dart' show inlineLatexText;
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

// 极索页内直答的三态——streaming/done 现在表示"有没有请求正在飞"，
// 不是某一轮自己的状态（那个在 QaTurn.status 上），只影响输入框是否
// 可用/顶部要不要转圈这些全局层面的东西
enum JisuoMode { idle, streaming, done }

enum QaTurnStatus { streaming, done, error }

// 多轮累加对话的每一轮——一问一答。answer/status/suggestions 是可变的，
// 流式追加内容/切换状态都是原地改这个对象上的字段，不是每次都换一个
// 新的 QaTurn 塞回列表
class QaTurn {
  final String question;
  String answer;
  QaTurnStatus status;
  List<String> suggestions;

  QaTurn({
    required this.question,
    this.answer = '',
    this.status = QaTurnStatus.streaming,
    this.suggestions = const [],
  });
}

class JisuoScreen extends ConsumerStatefulWidget {
  const JisuoScreen({super.key});

  @override
  ConsumerState<JisuoScreen> createState() => _JisuoScreenState();
}

class _JisuoScreenState extends ConsumerState<JisuoScreen> {
  final _inputCtrl = TextEditingController();
  final _inputFocusNode = FocusNode();
  final _scrollCtrl = ScrollController();

  // 底部输入框的 tab：ai=问问小梦 / community=社区提问。只影响 hint 文案和
  // 发送后的落点
  String _tab = 'ai';

  // 输入栏折叠态——默认展开（跟原来行为一致），点空白区域收起成一个
  // 小球，把空间让给上面的回答内容；点小球再展开。收起不清空已经打
  // 的字（_inputCtrl不受折叠影响，收起只是不显示，展开还在）
  bool _composerCollapsed = false;

  // 页内直答状态机：idle=落地页(Hero+示例) / streaming=流式生成中 /
  // done=回答完成。全程不跳转、不隐藏底部栏，就在极索页内展开
  JisuoMode _jisuoMode = JisuoMode.idle;
  // 多轮累加对话——方案A：新问题追加一轮到列表末尾，不覆盖之前的
  // 问答。conversationId 由后端在流式响应里下发，同一个 id 带着问
  // 下一轮，后端自己按这个 id 维护上下文，不需要客户端把历史消息
  // 拼成 messages 数组再传回去
  final List<QaTurn> _turns = [];
  String? _convId;
  bool _stopRequested = false;
  // "社区相关讨论"——回答态下方展示的社区问题（GET /auth/questions），
  // 跟着最新一轮问题刷新，不是每一轮各自一份
  List<Map<String, dynamic>> _related = [];

  // "社区提问"Tab 的内容——切到这个 Tab 才是真的展示社区发布的问答
  // 列表（跟上面 _related 那种"挂在AI回答下面的相关推荐"是两回事），
  // 懒加载：第一次点这个 Tab 才拉，不是一进极索页就请求
  List<Map<String, dynamic>> _communityQuestions = [];
  bool _loadingCommunity = false;
  bool _communityLoaded = false;

  static const _sampleQuestions = [
    '量子纠缠真的可以超光速通信吗？',
    'Python 和 R 哪个更适合数据分析？',
    '为什么黑洞不会把自己吞掉？',
  ];

  @override
  void dispose() {
    _inputCtrl.dispose();
    _inputFocusNode.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _showAskSheet({String prefill = ''}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AskSheet(onPost: _postQuestion, prefill: prefill),
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

  void _startQuestion(String q) => _askQuestion(q);

  // 问问小梦：页内展开流式回复，全程不跳转。流式拉 /auth/xmeng/chat/stream，
  // 每问一次都是新追加一轮 QaTurn 到列表末尾（方案A：多轮累加，不覆盖
  // 之前的问答），回答实时追加到这一轮自己的 answer 上就地渲染；完成后
  // 给三条本地追问建议 + 拉社区相关讨论
  Future<void> _askQuestion(String question) async {
    final q = question.trim();
    if (q.isEmpty || _jisuoMode == JisuoMode.streaming) return;
    _inputCtrl.clear();
    FocusScope.of(context).unfocus();
    final turn = QaTurn(question: q);
    setState(() {
      _jisuoMode = JisuoMode.streaming;
      _turns.add(turn);
      _stopRequested = false;
    });
    // 滚到底部看新追加的这一轮从头展开
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    unawaited(_loadRelated(q));

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
        if (_stopRequested) break; // 用户点了"停止生成"
        if (!line.startsWith('data:')) continue;
        final jsonStr = line.substring(5).trim();
        if (jsonStr.isEmpty) continue;
        final data = jsonDecode(jsonStr) as Map<String, dynamic>;
        switch (data['type']) {
          case 'meta':
            _convId = data['conversationId']?.toString() ?? _convId;
            break;
          case 'done':
            _convId = data['conversationId']?.toString() ?? _convId;
            // 分片累加偶发会丢片（网络/后端 SSE 推送问题），done 事件带的
            // fullText 是权威全文，收到就整段覆盖掉之前拼出来的 answer，
            // 兜底修正任何遗漏，不管丢片具体发生在哪一层
            final fullText = data['fullText'] as String?;
            if (fullText != null && fullText.isNotEmpty) {
              setState(() => turn.answer = fullText);
            }
            break;
          case 'chunk':
            setState(() => turn.answer += data['text']?.toString() ?? '');
            break;
          case 'error':
            errorMessage = data['message']?.toString() ?? '小梦暂时休息中，请稍后再试';
            break;
        }
      }
      if (!mounted) return;
      setState(() {
        _jisuoMode = JisuoMode.done;
        turn.status = QaTurnStatus.done;
        turn.suggestions = _generateSuggestions(q);
      });
      _scrollToBottom();
      if (errorMessage != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage)));
      }
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = e.response?.data is Map
          ? ((e.response!.data as Map)['message']?.toString() ??
                '小梦暂时休息中，请稍后再试')
          : '小梦暂时休息中，请稍后再试';
      // 之前单轮设计里空回答会整页退回 idle——多轮下前面几轮可能已经
      // 问答成功，不能因为最新这一轮失败就把整个对话都收起来，只标这
      // 一轮自己出错，其它轮次照样留着
      setState(() {
        turn.status = QaTurnStatus.error;
        _jisuoMode = JisuoMode.done;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _scrollToBottom() {
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.animateTo(
      _scrollCtrl.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _stopStream() => setState(() {
    _stopRequested = true;
    _jisuoMode = JisuoMode.done;
    if (_turns.isNotEmpty) {
      final turn = _turns.last;
      turn.status = QaTurnStatus.done;
      // 已经吐了一部分就保留，一个字都还没来就给个占位，不然卡片空着
      if (turn.answer.isEmpty) turn.answer = '已停止生成';
      turn.suggestions = _generateSuggestions(turn.question);
    }
  });

  // 顶栏"重置"：回落地页，清掉整个多轮对话——连 conversationId 一起
  // 清掉，不然"重置"完看着是回到欢迎页了，下一次提问其实还在续着
  // 已经清空的这段对话的上下文，答非所问
  void _resetToIdle() {
    setState(() {
      _jisuoMode = JisuoMode.idle;
      _turns.clear();
      _convId = null;
      _related = [];
    });
  }

  void _copyAnswer(QaTurn turn) {
    Clipboard.setData(ClipboardData(text: turn.answer));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
  }

  // 发布到极索：把这个问题抛给社区讨论——复用社区提问 Sheet，并把最新
  // 一轮的问题预填进去，用户不用重打一遍
  void _publishToJisuo() =>
      _showAskSheet(prefill: _turns.isNotEmpty ? _turns.last.question : '');

  List<String> _generateSuggestions(String q) => const [
    '能举一个更具体的例子吗？',
    '这个概念在实际中怎么应用？',
    '有哪些相关的延伸知识？',
  ];

  Future<void> _loadRelated(String q) async {
    final res = await ref
        .read(apiClientProvider)
        .get('/auth/questions', queryParameters: {'limit': 4});
    if (!mounted || !res.success || res.data == null) return;
    setState(() {
      _related = ((res.data['questions'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    });
  }

  Future<void> _loadCommunityQuestions({bool refresh = false}) async {
    setState(() => _loadingCommunity = true);
    final res = await ref
        .read(apiClientProvider)
        .get('/auth/questions', queryParameters: {'limit': 30});
    if (!mounted) return;
    setState(() {
      _loadingCommunity = false;
      _communityLoaded = true;
      if (res.success && res.data != null) {
        _communityQuestions = ((res.data['questions'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      // 浅色统一成首页那种偏米白的 #FAFAF8（比全局 scaffold 的冷灰白
      // #F7F7FB 更舒服），深色维持主题背景
      backgroundColor: isDark
          ? Theme.of(context).scaffoldBackgroundColor
          : const Color(0xFFFAFAF8),
      // 装饰性星云/光晕要铺到状态栏后面才是完整的背景——之前包在
      // SafeArea 里面，SafeArea 顶部内边距会把这层背景一起往下推，
      // 状态栏那一条就会露出 scaffoldBackgroundColor 的纯色，跟下面
      // 的渐变背景断成两截，看起来像一块白条盖住了背景。挪到 SafeArea
      // 外层、Scaffold body 的 Stack 底层，跟首页极光光晕同一个做法
      body: Stack(
        children: [
          if (_jisuoMode == JisuoMode.idle)
            Positioned.fill(
              child: IgnorePointer(
                child: isDark
                    ? const CustomPaint(painter: _NebulaPainter(isDark: true))
                    : Stack(
                        children: [
                          // 实心低透明度圆改成径向渐变——之前是纯色填充，
                          // 边缘是一圈能看出来的硬边界；渐变透明到 0 才是
                          // 真正"雾感"光晕，没有边界感
                          Positioned(
                            top: -80,
                            left: -60,
                            child: Container(
                              width: 340,
                              height: 340,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    _primary.withValues(alpha: 0.10),
                                    _primary.withValues(alpha: 0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _buildTopBar(isDark),
                Expanded(
                  // 键盘展开后点正文空白处收起键盘，同时把输入栏收起成
                  // 小球——输入栏现在是浮在内容上面的 Positioned，不是
                  // bottomNavigationBar，正文是独立的 ListView，默认点
                  // 空白不会 unfocus。opaque 让整块正文（含 ListView
                  // 条目之间的空隙）都能接住 tap
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      FocusScope.of(context).unfocus();
                      if (!_composerCollapsed) {
                        setState(() => _composerCollapsed = true);
                      }
                    },
                    child: _tab == 'community'
                        ? _buildCommunityView(isDark)
                        : (_jisuoMode == JisuoMode.idle
                              ? _buildIdleView(isDark)
                              : _buildAnswerView(isDark)),
                  ),
                ),
              ],
            ),
          ),
          // 输入栏浮在内容上面（不是 bottomNavigationBar），收起时只是
          // 屏幕角落一个小球，把原来一整条常驻输入栏的高度让给上面的
          // 回答区——右下角贴 SafeArea，展开态和收起态共用同一个锚点位置
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: _composerCollapsed
                  ? Align(
                      alignment: Alignment.bottomRight,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 0, 16, 12),
                        child: _buildComposerBall(isDark),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: _buildBottomInput(isDark),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // 收起态——一个悬浮小球，点了展开成完整输入胶囊并直接拉起键盘
  Widget _buildComposerBall(bool isDark) {
    return GestureDetector(
      onTap: () {
        setState(() => _composerCollapsed = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_tab == 'ai') _inputFocusNode.requestFocus();
        });
      },
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.65),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.8),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              Icons.edit_outlined,
              size: 20,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
        ),
      ),
    );
  }

  // 顶栏：标题 + Tab切换（问问小梦/社区提问，跟标题同一行，腾出下面
  // 一整行的竖向空间给内容）+ （AI Tab 非 idle 态）重置/历史对话按钮
  Widget _buildTopBar(bool isDark) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 2),
      child: Row(
        children: [
          Text(
            l10n.navJisuo,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(width: 10),
          _tabChip(
            isDark,
            label: l10n.jisuoAskXiaomeng,
            icon: Icons.auto_awesome,
            mode: 'ai',
          ),
          const SizedBox(width: 6),
          _tabChip(
            isDark,
            label: l10n.jisuoCommunityAsk,
            icon: Icons.people_outline,
            mode: 'community',
          ),
          const Spacer(),
          if (_tab == 'ai' && _jisuoMode != JisuoMode.idle)
            IconButton(
              tooltip: '重新开始',
              icon: const Icon(Icons.refresh, size: 20),
              color: Colors.grey[500],
              onPressed: _resetToIdle,
            ),
          if (_tab == 'ai')
            IconButton(
              tooltip: l10n.chatHistory,
              icon: const Icon(Icons.history, size: 20),
              color: Colors.grey[500],
              onPressed: () => context.push('/xiaomeng/history'),
            ),
        ],
      ),
    );
  }

  // 输入栏改成浮在内容上面的 Positioned 之后，滚动到底的内容会被玻璃
  // 胶囊挡住——统一给每个可滚动视图留出这么多底部空间，跟输入栏展开态
  // 大致高度对齐
  static const _composerClearance = 96.0;

  Widget _buildIdleView(bool isDark) {
    return ListView(
      children: [
        _buildHero(isDark),
        const SizedBox(height: _composerClearance),
      ],
    );
  }

  Widget _buildHero(bool isDark) {
    // 星云/光晕装饰层挪到 Scaffold body 的 Stack 底层了（build()
    // 里，SafeArea 外面），这里只剩文字内容本身。高度进一步收紧到0.3——
    // 用户是来提问的，不是来看 slogan 的，标题不需要撑满半屏，把视觉
    // 重心让给下面的示例问题（真正可点的入口）
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.3,
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
                      fontSize: 27,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
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
                const SizedBox(height: 8),
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
                const SizedBox(height: 26),
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
                              : Colors.white,
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.1)
                                : _primary.withValues(alpha: 0.1),
                            width: 0.5,
                          ),
                          // 浅色下从"淡紫填色+描边"改成"白底+极淡描边+软阴影"
                          // ——原来的纯色填充在同样浅米白的页面背景上层次
                          // 不够，阴影才是真正的深度来源
                          boxShadow: isDark
                              ? null
                              : [
                                  BoxShadow(
                                    color: _primary.withValues(alpha: 0.08),
                                    blurRadius: 18,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
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

  Widget _tabChip(
    bool isDark, {
    required String label,
    required IconData icon,
    required String mode,
  }) {
    final selected = _tab == mode;
    // 未选中态跟输入框/示例问题气泡同一套淡紫胶囊：淡紫底 + 淡紫描边 +
    // 紫色字/图标（浅色），不再是发灰的底 + 灰字；选中态仍是实心紫 + 白字
    final contentColor = selected
        ? Colors.white
        : isDark
        ? Colors.white.withValues(alpha: 0.6)
        : _primary;
    return GestureDetector(
      onTap: () {
        setState(() => _tab = mode);
        if (mode == 'community' && !_communityLoaded) {
          _loadCommunityQuestions();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? _primary
              : isDark
              ? Colors.white.withValues(alpha: 0.06)
              : _primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(99),
          border: selected
              ? null
              : Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : _primary.withValues(alpha: 0.15),
                  width: 0.5,
                ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: contentColor),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: contentColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    // community 模式走社区提问 Sheet；ai 模式在本页流式直答
    if (_tab == 'community') {
      _showAskSheet();
      return;
    }
    _askQuestion(_inputCtrl.text);
  }

  // 输入框和发送键合成同一个胶囊（发送键收进胶囊右侧，不再是外面单独
  // 一个圆），整条胶囊套 BackdropFilter 做成 iOS 风格的毛玻璃——展开态
  // 是浮在内容上面的，玻璃质感能让底下滚动的回答内容透出来，不是一块
  // 完全不透明的实色条
  Widget _buildBottomInput(bool isDark) {
    final streaming = _jisuoMode == JisuoMode.streaming;
    // ai 模式空输入时按钮置灰不可发；community 模式点了是开提问 Sheet，
    // 不看输入框，始终可点
    final disabled =
        !streaming && _tab == 'ai' && _inputCtrl.text.trim().isEmpty;
    final iconColor = streaming
        ? const Color(0xFFEF4444)
        : disabled
        ? Colors.grey[400]!
        : (isDark ? Colors.white : const Color(0xFF1A1A1A));

    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 120),
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.white.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.8),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  focusNode: _inputFocusNode,
                  minLines: 1,
                  maxLines: 4,
                  // community 模式输入框只当"打开提问 Sheet"的按钮用
                  readOnly: _tab == 'community',
                  onTap: _tab == 'community' ? _showAskSheet : null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _submit(),
                  // 跟着输入内容重建，让发送键在"空=灰/有内容=黑"之间实时切
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: _jisuoMode != JisuoMode.idle
                        ? '继续追问小梦...'
                        : _tab == 'ai'
                        ? '问小梦任何问题...'
                        : '提问，让社区来回答...',
                    hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
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
              // 流式中点发送键 = 停止生成；其余点了走 _submit（空输入时
              // _askQuestion 内部会自己 return，点了也没反应）
              GestureDetector(
                onTap: streaming ? _stopStream : _submit,
                child: Container(
                  width: 38,
                  height: 38,
                  margin: const EdgeInsets.only(left: 4),
                  decoration: BoxDecoration(
                    color: disabled
                        ? Colors.transparent
                        : (isDark
                              ? Colors.white.withValues(alpha: 0.12)
                              : Colors.black.withValues(alpha: 0.06)),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    streaming ? Icons.stop_rounded : Icons.arrow_upward,
                    size: 18,
                    color: iconColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 回答态：多轮累加，每一轮一问一答，从上往下按提问顺序排列 ──────
  Widget _buildAnswerView(bool isDark) {
    final line = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : const Color(0xFFF0F0F0);
    final cardBg = isDark ? const Color(0xFF141427) : Colors.white;
    final cardBorder = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFEBEBEB);
    return ListView(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(0, 4, 0, _composerClearance),
      children: [
        for (final turn in _turns)
          ..._buildTurn(
            turn,
            isDark: isDark,
            isLast: identical(turn, _turns.last),
            line: line,
            cardBg: cardBg,
            cardBorder: cardBorder,
          ),
        // 社区相关讨论——跟着最新一轮问题刷新，放在整个对话列表最下面
        if (_related.isNotEmpty) _buildRelatedQuestions(isDark),
      ],
    );
  }

  List<Widget> _buildTurn(
    QaTurn turn, {
    required bool isDark,
    required bool isLast,
    required Color line,
    required Color cardBg,
    required Color cardBorder,
  }) {
    final streaming = turn.status == QaTurnStatus.streaming;
    final errored = turn.status == QaTurnStatus.error && turn.answer.isEmpty;
    return [
      // 用户问题气泡（右对齐）
      Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.fromLTRB(48, 4, 12, 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
            color: _primary,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: inlineLatexText(
            turn.question,
            const TextStyle(fontSize: 14, color: Colors.white, height: 1.6),
          ),
        ),
      ),
      // AI 回复卡片
      Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cardBorder, width: 0.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 卡片头：问问小梦 + 流式中转圈 / 完成后"回答完成"
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 12,
                    backgroundColor: _primary,
                    child: Text(
                      '梦',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    AppLocalizations.of(context)!.jisuoAskXiaomeng,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF9B98FF),
                    ),
                  ),
                  const Spacer(),
                  if (streaming)
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: _primary,
                      ),
                    )
                  else
                    Text(
                      errored ? '出错了' : '回答完成',
                      style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                    ),
                ],
              ),
            ),
            Divider(height: 0.5, color: line),
            // 正文（流式输出）
            Padding(
              padding: const EdgeInsets.all(14),
              child: turn.answer.isEmpty && streaming
                  ? Row(
                      children: [
                        Text(
                          '小梦正在思考...',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    )
                  : errored
                  ? Text(
                      '小梦暂时休息中，请稍后再试',
                      style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                    )
                  : AiContentRenderer(content: turn.answer, isDark: isDark),
            ),
            // 停止生成已移到底部发送键（流式中发送键变红 ■），流式中整条
            // 操作栏隐藏；只在完成后显示 复制 + 发布到极索
            if (!streaming) ...[
              Divider(height: 0.5, color: line),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                child: Row(
                  children: [
                    _ansActionBtn(
                      isDark,
                      Icons.copy_outlined,
                      '复制',
                      () => _copyAnswer(turn),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: _publishToJisuo,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: isDark
                                ? _primary.withValues(alpha: 0.1)
                                : const Color(0xFFEEF0FF),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isDark
                                  ? _primary.withValues(alpha: 0.2)
                                  : const Color(0xFFD0D4FF),
                              width: 0.5,
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.people_outline,
                                size: 14,
                                color: Color(0xFF9B98FF),
                              ),
                              SizedBox(width: 5),
                              Text(
                                '发布到极索让社区讨论',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF9B98FF),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      // 追问建议——只在最新一轮下面显示，不是每一轮都堆一份
      if (isLast &&
          turn.status == QaTurnStatus.done &&
          turn.suggestions.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '你可能还想问',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
              const SizedBox(height: 8),
              ...turn.suggestions.map(
                (s) => GestureDetector(
                  onTap: () => _askQuestion(s),
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: cardBorder, width: 0.5),
                    ),
                    child: Text(
                      s,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? const Color(0xFF7A80A0)
                            : Colors.grey[500],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  Widget _ansActionBtn(
    bool isDark,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFEBEBEB),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey[400]),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[400])),
        ],
      ),
    ),
  );

  Widget _buildRelatedQuestions(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '社区相关讨论',
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
          const SizedBox(height: 4),
          ..._related.map((q) {
            final title = q['text']?.toString() ?? q['title']?.toString() ?? '';
            final username = q['username']?.toString() ?? '';
            final domain = q['domain']?.toString() ?? '';
            final answers = (q['answer_count'] as num?)?.toInt() ?? 0;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.push('/questions/${q['id']}', extra: q),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: jisuoDomainColor(domain),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              username.isNotEmpty
                                  ? username.substring(0, 1)
                                  : '?',
                              style: const TextStyle(
                                fontSize: 9,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          username.isEmpty
                              ? '$answers 回答'
                              : '$username · $answers 回答',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // "社区提问"Tab 的正文——社区已发布问答列表，真实数据
  // （GET /auth/questions），不是切 Tab 只换个高亮颜色、内容照旧
  Widget _buildCommunityView(bool isDark) {
    if (_loadingCommunity && _communityQuestions.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: _primary));
    }
    if (_communityQuestions.isEmpty) {
      return Center(
        child: Text(
          _communityLoaded ? '还没有人在社区提问' : '',
          style: TextStyle(fontSize: 13, color: Colors.grey[500]),
        ),
      );
    }
    final line = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : const Color(0xFFF0F0F0);
    return RefreshIndicator(
      color: _primary,
      onRefresh: () => _loadCommunityQuestions(refresh: true),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, _composerClearance),
        itemCount: _communityQuestions.length,
        separatorBuilder: (_, _) => Divider(height: 1, color: line),
        itemBuilder: (context, i) {
          final q = _communityQuestions[i];
          final title = q['text']?.toString() ?? q['title']?.toString() ?? '';
          final username = q['username']?.toString() ?? '';
          final domain = q['domain']?.toString() ?? '';
          final answers = (q['answer_count'] as num?)?.toInt() ?? 0;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => context.push('/questions/${q['id']}', extra: q),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (domain.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: jisuoDomainBg(domain),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          domain,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: jisuoDomainColor(domain),
                          ),
                        ),
                      ),
                    ),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: jisuoDomainColor(domain),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            username.isNotEmpty
                                ? username.substring(0, 1)
                                : '?',
                            style: const TextStyle(
                              fontSize: 9,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        username.isEmpty
                            ? '$answers 回答'
                            : '$username · $answers 回答',
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
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
  // 从"发布到极索"进来时带上最新一轮的问题，预填进输入框
  final String prefill;
  const _AskSheet({required this.onPost, this.prefill = ''});

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
  void initState() {
    super.initState();
    if (widget.prefill.isNotEmpty) _ctrl.text = widget.prefill;
  }

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
