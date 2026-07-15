import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../models/block_model.dart';

const _primary = Color(0xFF6366F1);

// 小梦生成内容解析出来的"轻量 block 规格"——只带纯数据，不持有 FocusNode，
// 用户关掉对话框不填入时不会泄漏。真正的 EditorBlock 交给 publish_screen 在
// "填入编辑器"那一刻用 _uid() 构造（见 PublishScreen._fillFromXmeng）
class XmengBlock {
  final BlockType type;
  final String content;
  final String? language;
  final int? headingLevel;
  const XmengBlock({
    required this.type,
    required this.content,
    this.language,
    this.headingLevel,
  });
}

// 「小梦帮我写」——对话式：小梦主动发问 → 用户给主题/风格/读者 → AI 生成整篇
// 文章 → 预览 + 填入编辑器/重新生成。生成内容按标题/正文/公式/代码解析成
// 一串 block 规格，点"填入编辑器"时回调给发布页
class XmengWriteSheet extends ConsumerStatefulWidget {
  final void Function(List<XmengBlock> blocks) onFill;
  const XmengWriteSheet({super.key, required this.onFill});

  @override
  ConsumerState<XmengWriteSheet> createState() => _XmengWriteSheetState();
}

class _XmengWriteSheetState extends ConsumerState<XmengWriteSheet> {
  // 0=初始对话，1=等待生成，2=流式展示/完成
  int _step = 0;
  String _userInput = '';
  String _generated = '';
  // 后端 /auth/xmeng/chat 是一次性返回整段、不是 SSE 流——收到全文后用定时器
  // 逐段"打字机"揭示：_typedLen 是当前已显示到第几个字符
  int _typedLen = 0;
  Timer? _typeTimer;
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  bool get _typingDone => _typedLen >= _generated.length;

  static const _greeting =
      '你好！我是小梦 ✦\n\n'
      '你想写什么内容？告诉我主题、风格或目标读者，我来帮你起草。';

  @override
  void dispose() {
    _typeTimer?.cancel();
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // 收到全文后启动打字机——按内容长度算步长，让整段大约 2 秒内揭示完；每
  // 一跳都滚到底，跟着新出现的文字走
  void _startTyping() {
    _typeTimer?.cancel();
    _typedLen = 0;
    final total = _generated.length;
    final chunk = (total / 100).ceil().clamp(1, 30);
    _typeTimer = Timer.periodic(const Duration(milliseconds: 24), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _typedLen = (_typedLen + chunk).clamp(0, total));
      _scrollToBottom();
      if (_typedLen >= total) t.cancel();
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _generate() async {
    final input = _ctrl.text.trim();
    if (input.isEmpty) return;
    _ctrl.clear();
    await _runGenerate(input);
  }

  void _regenerate() => _runGenerate(_userInput);

  Future<void> _runGenerate(String input) async {
    FocusScope.of(context).unfocus();
    _typeTimer?.cancel();
    setState(() {
      _userInput = input;
      _generated = '';
      _typedLen = 0;
      _step = 1;
    });
    _scrollToBottom();

    final prompt =
        '用户想写：$input\n\n'
        '请生成一篇结构完整、可直接发布的中文文章。格式要求：\n'
        '1. 第一行是文章标题（不要加 # 号）\n'
        '2. 正文分段，用空行隔开段落\n'
        '3. 需要数学公式时用 \$...\$ 包裹；单独成行展示的公式用 \$\$...\$\$\n'
        '4. 需要代码时用三个反引号包裹并注明语言（如 ```python）\n'
        '5. 小节标题用 ## 开头\n'
        '6. 直接输出文章内容，不要任何额外说明或客套话';

    try {
      final res = await ref
          .read(apiClientProvider)
          .post(
            '/auth/xmeng/chat',
            data: {
              'messages': [
                {'role': 'user', 'content': prompt},
              ],
            },
            options: Options(receiveTimeout: const Duration(seconds: 90)),
          );
      if (!mounted) return;
      final msg = res.success
          ? ((res.data as Map?)?['message'] as String? ?? '')
          : '';
      if (msg.trim().isEmpty) {
        _fail();
        return;
      }
      setState(() {
        _generated = msg.trim();
        _step = 2;
      });
      _startTyping();
    } catch (_) {
      if (mounted) _fail();
    }
  }

  void _fail() {
    setState(() => _step = 0);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('小梦开小差了，请重试')));
  }

  void _fill() {
    final blocks = _parseToBlocks(_generated);
    if (blocks.isEmpty) return;
    Navigator.pop(context);
    widget.onFill(blocks);
  }

  // 生成的纯文本 → block 规格：三反引号→代码块；首个非空行→标题(heading
  // level 2)；## 小节→heading；整行就是一条公式($$..$$ 或整行 $..$)→latex
  // 块；其余→文字块（行内 $..$ 由文字块自己渲染）
  List<XmengBlock> _parseToBlocks(String content) {
    final blocks = <XmengBlock>[];
    final lines = content.split('\n');
    var inCode = false;
    var codeLang = 'python';
    final codeBuf = <String>[];
    var titleDone = false;

    for (final raw in lines) {
      final trimmed = raw.trim();

      if (trimmed.startsWith('```')) {
        if (!inCode) {
          inCode = true;
          final lang = trimmed.substring(3).trim().toLowerCase();
          codeLang = lang.isEmpty ? 'python' : lang;
          codeBuf.clear();
        } else {
          inCode = false;
          blocks.add(
            XmengBlock(
              type: BlockType.code,
              content: codeBuf.join('\n'),
              language: codeLang,
            ),
          );
        }
        continue;
      }
      if (inCode) {
        codeBuf.add(raw);
        continue;
      }
      if (trimmed.isEmpty) continue;

      // 首个非空行当文章标题
      if (!titleDone) {
        titleDone = true;
        blocks.add(
          XmengBlock(
            type: BlockType.heading,
            content: trimmed.replaceAll(RegExp(r'^#+\s*'), ''),
            headingLevel: 2,
          ),
        );
        continue;
      }

      // 整行就是一条独立公式 → latex 块
      final formula = _standaloneFormula(trimmed);
      if (formula != null) {
        blocks.add(XmengBlock(type: BlockType.latex, content: formula));
        continue;
      }

      // markdown 小节标题 → heading（# 映射成本编辑器的 2/3/4）
      final h = RegExp(r'^(#{1,6})\s+(.*)').firstMatch(trimmed);
      if (h != null) {
        final level = (h.group(1)!.length + 1).clamp(2, 4);
        blocks.add(
          XmengBlock(
            type: BlockType.heading,
            content: h.group(2)!.trim(),
            headingLevel: level,
          ),
        );
        continue;
      }

      blocks.add(XmengBlock(type: BlockType.text, content: trimmed));
    }

    // 代码块没闭合也兜底收进来
    if (inCode && codeBuf.isNotEmpty) {
      blocks.add(
        XmengBlock(
          type: BlockType.code,
          content: codeBuf.join('\n'),
          language: codeLang,
        ),
      );
    }
    return blocks;
  }

  // 整行是一条公式才当独立公式块：$$...$$，或整行只有一个 $...$（没有别的
  // 正文）。返回去掉 $ 的公式体，不是就返回 null
  String? _standaloneFormula(String line) {
    final dd = RegExp(r'^\$\$(.+)\$\$$').firstMatch(line);
    if (dd != null) return dd.group(1)!.trim();
    final s = RegExp(r'^\$([^$]+)\$$').firstMatch(line);
    if (s != null) return s.group(1)!.trim();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? const Color(0xFF17171F) : Colors.white;
    final border = isDark ? Colors.white12 : const Color(0xFFEBEBEB);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            _header(isDark, border),
            Expanded(child: _messages(isDark, border)),
            if (_step == 0) _inputBar(isDark, border),
            // 打字机放完再露出操作按钮，让用户先读到完整草稿
            if (_step == 2 && _typingDone) _actionButtons(isDark, border),
          ],
        ),
      ),
    );
  }

  Widget _header(bool isDark, Color border) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 12, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: border, width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _primary,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '小梦帮我写',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Icon(Icons.close, size: 22, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _messages(bool isDark, Color border) {
    final bubbleAi = isDark ? const Color(0xFF23232B) : const Color(0xFFF7F7F9);
    return ListView(
      controller: _scrollCtrl,
      // 显式允许滚动——内容超过一屏时能滚动查看完整回复，短内容也能回弹
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      children: [
        _aiBubble(_greeting, bubbleAi, border),
        if (_step >= 1) ...[
          const SizedBox(height: 12),
          _userBubble(_userInput),
        ],
        if (_step == 1) ...[
          const SizedBox(height: 12),
          _aiBubble(
            '好的，我来帮你起草，稍等一下…',
            bubbleAi,
            border,
            trailing: const Padding(
              padding: EdgeInsets.only(top: 8),
              child: _TypingDots(),
            ),
          ),
        ],
        // 生成完成：整段文章直接以打字机方式流式显示在气泡里（不再是截断的
        // 预览框），内容超屏就能滚动查看
        if (_step == 2) ...[
          const SizedBox(height: 12),
          _aiBubble(
            _generated.substring(0, _typedLen),
            bubbleAi,
            border,
            trailing: _typingDone
                ? null
                : const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: _TypingDots(),
                  ),
          ),
        ],
      ],
    );
  }

  Widget _aiBubble(String text, Color bubbleBg, Color border, {Widget? trailing}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _primary.withValues(alpha: 0.9),
            shape: BoxShape.circle,
          ),
          child: const Text(
            '梦',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: bubbleBg,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(14),
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(14),
              ),
              border: Border.all(color: border, width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.7,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _userBubble(String text) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: _primary,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(4),
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(14),
              ),
            ),
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _inputBar(bool isDark, Color border) {
    final fieldBg = isDark ? const Color(0xFF23232B) : const Color(0xFFF5F5F5);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: fieldBg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: border, width: 0.5),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _ctrl,
                  autofocus: true,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _generate(),
                  decoration: const InputDecoration(
                    hintText: '比如：写一篇贝叶斯定理的入门文章',
                    hintStyle: TextStyle(color: Color(0xFF9AA0AB), fontSize: 14),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _generate,
              child: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: _primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.send, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButtons(bool isDark, Color border) {
    final ink = isDark ? Colors.white : const Color(0xFF1A1A1A);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: _regenerate,
                child: Container(
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: border),
                  ),
                  child: Text(
                    '重新生成',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: _fill,
                child: Container(
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: ink,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '填入编辑器',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xFF17171F) : Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 生成中的三点跳动动画——一个 900ms 循环的 controller，三个点按相位错开做
// 上下小幅弹跳（三角波，不引入 dart:math）
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final phase = (_c.value + i * 0.2) % 1.0;
          final t = 1 - (phase * 2 - 1).abs(); // 0→1→0 三角波
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Transform.translate(
              offset: Offset(0, -3 * t),
              child: Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFFBBBBBB),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
