import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/utils/ai_lang.dart';
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
  // 0=初始对话，1=等待首个分片，2=流式展示/完成
  int _step = 0;
  String _userInput = '';
  String _generated = '';
  // SSE 流式：网络还在推 → _streaming=true；chunk 逐字符入队，Timer 每 15ms
  // 吐一个字到 _generated 上，一个字一个字地出现（打字机效果，跟极索页一致）
  bool _streaming = false;
  final _charQueue = Queue<String>();
  Timer? _typeTimer;
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  // 流也结束了、打字机也吐完了才算真正完成——这时才露出操作按钮
  bool get _done => _step == 2 && !_streaming && _charQueue.isEmpty;
  // 还在流/还有字没吐完 → 气泡尾巴挂三点动画
  bool get _writing => _streaming || _charQueue.isNotEmpty;

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

  // 收到 chunk：逐字符（按 grapheme，中文/emoji 安全）入队，Timer 逐字吐出；
  // 首个字到了就从"等待态"切到流式展示态
  void _enqueue(String text) {
    if (text.isEmpty) return;
    if (_step != 2) setState(() => _step = 2);
    _charQueue.addAll(text.characters);
    _typeTimer ??= Timer.periodic(const Duration(milliseconds: 15), (_) {
      if (!mounted) {
        _typeTimer?.cancel();
        _typeTimer = null;
        return;
      }
      if (_charQueue.isEmpty) {
        // 流结束且队列吐空 → 停表；否则等下一批 chunk
        if (!_streaming) {
          _typeTimer?.cancel();
          _typeTimer = null;
          setState(() {});
        }
        return;
      }
      final ch = _charQueue.removeFirst();
      setState(() => _generated += ch);
      _stickToBottom();
    });
  }

  // done 带的 fullText 是权威全文（分片偶发丢片），有就整段覆盖并清掉队列；
  // 没有就把队列里剩的字一次性补齐，都不丢字
  void _flush({String? finalText}) {
    _typeTimer?.cancel();
    _typeTimer = null;
    final rest = _charQueue.join();
    _charQueue.clear();
    setState(() {
      if (finalText != null && finalText.isNotEmpty) {
        _generated = finalText;
      } else {
        _generated += rest;
      }
    });
  }

  // 动画滚到底（切步/开始时用）
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

  // 流式逐字时用——只在用户本来就贴着底部时瞬时跟随，往上翻看历史就不打断
  void _stickToBottom() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    if (pos.maxScrollExtent - pos.pixels < 80) {
      _scrollCtrl.jumpTo(pos.maxScrollExtent);
    }
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
    _typeTimer = null;
    _charQueue.clear();
    setState(() {
      _userInput = input;
      _generated = '';
      _streaming = true;
      _step = 1;
    });
    _scrollToBottom();

    // 语言跟着「AI 偏好语言」设置走——语言指令拼在最前，base prompt 里不再
    // 写死"中文"，避免设成英文/中英混合时相互打架
    final langHint = await aiLangHint();
    final prompt =
        '$langHint'
        '用户想写：$input\n\n'
        '请生成一篇结构完整、可直接发布的文章。格式要求：\n'
        '1. 第一行是文章标题（不要加 # 号）\n'
        '2. 正文分段，用空行隔开段落\n'
        '3. 数学公式：块级公式（单独成行展示）用 \\[...\\] 包裹，行内公式用 \$...\$ 包裹；'
        '不要用 \$\$...\$\$ 格式，不要在公式里用 && 符号，多行公式请用 aligned 环境，'
        '不要生成 \\expression\\ 这类占位写法\n'
        '4. 需要代码时用三个反引号包裹并注明语言（如 ```python）\n'
        '5. 小节标题用 ## 开头\n'
        '6. 直接输出文章内容，不要任何额外说明或客套话';

    // 流式 SSE：跟极索页同一个接口 /auth/xmeng/chat/stream（body 用单条
    // message，不是 messages 数组），逐行读 data: {type: chunk/done/error}
    try {
      final response = await ref
          .read(apiClientProvider)
          .dio
          .post(
            '/auth/xmeng/chat/stream',
            data: {'message': prompt},
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
          case 'chunk':
            _enqueue(data['text']?.toString() ?? '');
            break;
          case 'done':
            final fullText = data['fullText'] as String?;
            _flush(
              finalText: (fullText != null && fullText.isNotEmpty)
                  ? fullText
                  : null,
            );
            break;
          case 'error':
            errorMessage = data['message']?.toString() ?? '小梦开小差了，请重试';
            break;
        }
      }
      // 流结束：停表、补齐残留的字
      _flush();
      if (!mounted) return;
      setState(() => _streaming = false);
      // 一个字都没生成出来就当失败（回到输入态提示重试）；有内容就留着
      if (_generated.trim().isEmpty) {
        _fail(errorMessage ?? '小梦开小差了，请重试');
      } else if (errorMessage != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage)));
      }
    } on DioException catch (e) {
      _flush();
      if (!mounted) return;
      setState(() => _streaming = false);
      if (_generated.trim().isEmpty) {
        final msg = e.response?.data is Map
            ? ((e.response!.data as Map)['message']?.toString() ??
                  '小梦开小差了，请重试')
            : '小梦开小差了，请重试';
        _fail(msg);
      }
    } catch (_) {
      _flush();
      if (!mounted) return;
      setState(() => _streaming = false);
      if (_generated.trim().isEmpty) _fail('小梦开小差了，请重试');
    }
  }

  void _fail(String message) {
    _typeTimer?.cancel();
    _typeTimer = null;
    _charQueue.clear();
    setState(() {
      _streaming = false;
      _step = 0;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _fill() {
    final blocks = _parseToBlocks(_generated);
    if (blocks.isEmpty) return;
    Navigator.pop(context);
    widget.onFill(blocks);
  }

  // 生成的纯文本 → block 规格，按"段落"（空行分隔）切：三反引号→代码块；
  // 首个非空行→标题(heading level 2)；整段就是一条公式($$..$$/整行$..$)→
  // latex 块；段里有行内公式($..$)→文字块（文字块渲染行内公式，Markdown 块
  // 不认 LaTeX，LaTeX 优先）；含 Markdown 语法(** / ## / - / > / 链接 等)→
  // Markdown 块（整段一块，列表/多行才渲染得对）；其余普通段落→文字块
  List<XmengBlock> _parseToBlocks(String content) {
    final blocks = <XmengBlock>[];
    final lines = content.split('\n');
    var inCode = false;
    var codeLang = 'python';
    final codeBuf = <String>[];
    var titleDone = false;
    final para = <String>[];

    void flushPara() {
      if (para.isEmpty) return;
      final text = para.join('\n');
      para.clear();
      if (text.trim().isEmpty) return;
      final formula = _standaloneFormula(text.trim());
      if (formula != null) {
        blocks.add(XmengBlock(type: BlockType.latex, content: formula));
      } else if (_hasInlineFormula(text)) {
        blocks.add(XmengBlock(type: BlockType.text, content: text.trim()));
      } else if (_hasMarkdown(text)) {
        blocks.add(XmengBlock(type: BlockType.markdown, content: text.trim()));
      } else {
        blocks.add(XmengBlock(type: BlockType.text, content: text.trim()));
      }
    }

    for (final raw in lines) {
      final trimmed = raw.trim();

      if (trimmed.startsWith('```')) {
        flushPara();
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
      if (trimmed.isEmpty) {
        flushPara();
        continue;
      }
      // 首个非空行当文章标题（单独成块）
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
      para.add(raw);
    }

    flushPara();
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

  static final _inlineFormulaPattern = RegExp(
    r'\$[^$\n]+\$'
    r'|\\\(.+?\\\)'
    r'|\\\[.+?\\\]',
    dotAll: true,
  );

  bool _hasInlineFormula(String text) => _inlineFormulaPattern.hasMatch(text);

  // 含 Markdown 语法就该走 Markdown 块（文字块只认行内公式、不认 Markdown）：
  // **加粗** / __加粗__ / ## 小节 / - * + 列表 / 1. 有序列表 / > 引用 /
  // [文字](链接) / *斜体*
  bool _hasMarkdown(String text) {
    if (text.contains('**') ||
        text.contains('__') ||
        text.contains('##') ||
        text.contains('> ')) {
      return true;
    }
    for (final line in text.split('\n')) {
      final l = line.trimLeft();
      if (RegExp(r'^([-*+])\s').hasMatch(l)) return true; // 无序列表
      if (RegExp(r'^\d+\.\s').hasMatch(l)) return true; // 有序列表
      if (RegExp(r'^#{1,6}\s').hasMatch(l)) return true; // 小节标题
    }
    if (RegExp(r'\[[^\]]+\]\([^)]+\)').hasMatch(text)) return true; // 链接
    if (RegExp(r'(?<!\*)\*[^*\s][^*\n]*\*(?!\*)').hasMatch(text)) return true; // *斜体*
    return false;
  }

  // 整段是一条独立公式才当 LaTeX 块，返回清理后的公式体、不是就返回 null。
  // 关键：\[...\] 和 $$...$$ 都允许跨行——小梦经常把块级公式拆成
  //   $$
  //   a_0 + \cfrac{1}{...}
  //   $$
  // 三行成一段，旧的单行正则匹配不到，就漏进了文字块显示成源码。用 [\s\S]
  // 而不是 . 才能跨行匹配整段
  String? _standaloneFormula(String para) {
    final s = para.trim();
    // \[ ... \]（块级，允许多行）——新 prompt 要求的首选格式
    final br = RegExp(r'^\\\[([\s\S]+?)\\\]$').firstMatch(s);
    if (br != null) return _cleanLatex(br.group(1)!);
    // $$ ... $$（块级，允许多行）——旧草稿/模型没听指令时的兜底
    final dd = RegExp(r'^\$\$([\s\S]+?)\$\$$').firstMatch(s);
    if (dd != null) return _cleanLatex(dd.group(1)!);
    // 整行只有一个 $...$（没有别的正文）
    final one = RegExp(r'^\$([^$]+)\$$').firstMatch(s);
    if (one != null) return _cleanLatex(one.group(1)!);
    return null;
  }

  // 兜底清理小梦偶尔生成的脏格式：残留的 $$ 包裹、用 && 当换行、连写 3+ 个
  // 反斜杠。正常的 \cfrac \ddots 是单反斜杠、换行 \\ 是双反斜杠，都不受影响
  String _cleanLatex(String formula) {
    return formula
        .replaceAll(r'$$', '')
        .replaceAll('&&', r'\\')
        .replaceAll(RegExp(r'\\{3,}'), r'\\')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? const Color(0xFF17171F) : Colors.white;
    final border = isDark ? Colors.white12 : const Color(0xFFEBEBEB);

    final media = MediaQuery.of(context);
    final kb = media.viewInsets.bottom;
    // 键盘弹起时，白卡撑满键盘上方的全部空间（顶满键盘、四边不留缝），
    // 不再是固定 70% 高度——否则固定高度短于键盘上方可用高度时，底部/两侧
    // 会漏出后面的灰色蒙层。键盘收起时仍是 70%
    final sheetHeight = kb > 0
        ? (media.size.height - kb - media.padding.top).clamp(
            media.size.height * 0.4,
            media.size.height,
          )
        : media.size.height * 0.7;
    return Padding(
      padding: EdgeInsets.only(bottom: kb),
      child: Container(
        height: sheetHeight,
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
            // 流式全部写完再露出操作按钮，让用户先读到完整草稿
            if (_done) _actionButtons(isDark, border),
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
            _generated,
            bubbleAi,
            border,
            trailing: _writing
                ? const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: _TypingDots(),
                  )
                : null,
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
