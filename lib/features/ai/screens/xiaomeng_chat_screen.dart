import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart' show DioException, Options, ResponseBody, ResponseType;

import '../../../core/network/api_client.dart';
import '../../auth/auth_service.dart';
import '../../notebook/models/notebook_model.dart';
import '../../notebook/services/notebook_service.dart';
import '../models/ai_message_model.dart';

const _primary = Color(0xFF6366F1);

// 小梦对话页——真实接口：
// 新对话 POST /auth/xmeng/conversations {message}
//   → {reply, conversationId}
// 继续对话 POST /auth/xmeng/conversations/:id/messages {message}
//   → {reply, conversationId}
// 打开历史对话 GET /auth/xmeng/conversations/:id
//   → {conversation, messages:[{id,role,content,created_at}]}
// 这一整套后端本来就是真实、完整的，不是这次新建的——之前只是 Flutter
// 端从没接过，UI 全部走的是占位的 /aria
//
// initialMessage 统一是"预填输入框，不自动发送"——欢迎页无论是能力卡片
// 还是快捷问题，点了都只是把文字带过来，用户在这个页面自己点发送才会
// 真的调接口，不会一进页面就打一次 API
class XiaomengChatScreen extends ConsumerStatefulWidget {
  final String? conversationId;
  final String? initialMessage;
  const XiaomengChatScreen({
    super.key,
    this.conversationId,
    this.initialMessage,
  });

  @override
  ConsumerState<XiaomengChatScreen> createState() => _XiaomengChatScreenState();
}

class _XiaomengChatScreenState extends ConsumerState<XiaomengChatScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode = FocusNode();
  List<AiMessage> _messages = [];
  String? _conversationId;
  bool _sending = false;
  bool _loadingHistory = false;

  @override
  void initState() {
    super.initState();
    _conversationId = widget.conversationId;
    if (_conversationId != null) {
      _loadHistory(_conversationId!);
    }
    if (widget.initialMessage != null && widget.initialMessage!.trim().isNotEmpty) {
      _inputCtrl.text = widget.initialMessage!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadHistory(String conversationId) async {
    setState(() => _loadingHistory = true);
    final res = await ref
        .read(apiClientProvider)
        .get('/auth/xmeng/conversations/$conversationId');
    if (!mounted) return;
    setState(() {
      _loadingHistory = false;
      if (res.success && res.data is Map) {
        final list = ((res.data as Map)['messages'] as List?) ?? const [];
        _messages = list
            .map((m) => AiMessage.fromJson(Map<String, dynamic>.from(m as Map)))
            .toList();
      }
    });
    _scrollToBottom();
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

  // 真实接口 POST /auth/xmeng/chat/stream——跟 conversations 系列共用同一张
  // ai_conversations/ai_messages 表，只是响应换成 SSE：data: {"type":"meta"
  // |"chunk"|"done"|"error", ...}。用 apiClientProvider 内部现成的 Dio 实例
  // （ResponseType.stream）发起，不额外引入 http 包——这样 Authorization
  // 头、cookie、403刷新重试这些拦截器逻辑照样生效，不用像最初的
  // demo 代码那样自己再手动读一遍 token
  Future<void> _send([String? overrideText]) async {
    final text = (overrideText ?? _inputCtrl.text).trim();
    if (text.isEmpty || _sending) return;
    _inputCtrl.clear();

    const streamingId = 'streaming';
    setState(() {
      _sending = true;
      _messages.add(
        AiMessage(
          id: 'local-${DateTime.now().microsecondsSinceEpoch}',
          role: 'user',
          content: text,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      _messages.add(
        const AiMessage(
          id: streamingId,
          role: 'assistant',
          content: '',
          createdAt: 0,
        ),
      );
    });
    _scrollToBottom();

    void appendChunk(String chunk) {
      if (!mounted) return;
      setState(() {
        final i = _messages.indexWhere((m) => m.id == streamingId);
        if (i == -1) return;
        _messages[i] = AiMessage(
          id: streamingId,
          role: 'assistant',
          content: _messages[i].content + chunk,
          createdAt: _messages[i].createdAt,
        );
      });
      _scrollToBottom();
    }

    void removePlaceholder() {
      _messages.removeWhere((m) => m.id == streamingId);
    }

    try {
      final response = await ref
          .read(apiClientProvider)
          .dio
          .post(
            '/auth/xmeng/chat/stream',
            data: {
              'message': text,
              if (_conversationId != null) 'conversationId': _conversationId,
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
            _conversationId =
                data['conversationId']?.toString() ?? _conversationId;
            break;
          case 'chunk':
            appendChunk(data['text']?.toString() ?? '');
            break;
          case 'error':
            errorMessage = data['message']?.toString() ?? '小梦暂时休息中，请稍后再试';
            break;
        }
      }
      if (!mounted) return;
      if (errorMessage != null) {
        setState(() {
          removePlaceholder();
          _sending = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage)));
        return;
      }
      setState(() => _sending = false);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        removePlaceholder();
        _sending = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.response?.data is Map
              ? ((e.response!.data as Map)['message']?.toString() ??
                  '小梦暂时休息中，请稍后再试')
              : '小梦暂时休息中，请稍后再试'),
        ),
      );
    }
  }

  void _showMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: Color(0xFFDC2626),
                ),
                title: const Text(
                  '删除此对话',
                  style: TextStyle(color: Color(0xFFDC2626)),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDelete();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    if (_conversationId == null) {
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除此对话'),
        content: const Text('删除后无法恢复'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Color(0xFFDC2626))),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final res = await ref
        .read(apiClientProvider)
        .delete('/auth/xmeng/conversations/$_conversationId');
    if (!mounted) return;
    if (res.success) {
      Navigator.of(context).maybePop();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(res.message ?? '删除失败，请稍后重试')));
    }
  }

  // 引用内容/图片/在Notebook运行——POST /auth/xmeng/conversations(/:id)/
  // messages 目前只接受纯文本 message 一个字段，没有附件/引用/notebook
  // 联动的能力，老实提示"即将上线"，不假装点了有真的功能
  void _comingSoon(String feature) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$feature即将上线')));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 4),
            Text(
              '对话中',
              style: TextStyle(fontSize: 11, color: Colors.grey[400]),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : const Color(0xFFF0F0F0),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.arrow_back_ios, size: 16),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          '小梦',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                        ),
                        const Text(
                          '在线',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF22C55E),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _showMenu,
                    child: const SizedBox(
                      width: 34,
                      height: 34,
                      child: Icon(Icons.more_horiz, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 12, thickness: 0.5),
            Expanded(
              child: _loadingHistory
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      itemCount: _messages.length + (_sending ? 1 : 0),
                      itemBuilder: (ctx, i) {
                        if (i == _messages.length) return _typingRow();
                        return _messageRow(_messages[i], isDark);
                      },
                    ),
            ),
            _buildToolbar(isDark),
            _buildInputBar(isDark),
          ],
        ),
      ),
    );
  }

  Widget _messageRow(AiMessage msg, bool isDark) {
    if (msg.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.72,
          ),
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
          child: Text(
            msg.content,
            style: const TextStyle(fontSize: 14, color: Colors.white, height: 1.4),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _miniAvatar(),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _buildContent(msg.content, isDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniAvatar() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: const BoxDecoration(color: _primary, shape: BoxShape.circle),
          child: const Center(
            child: Text(
              '梦',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -1,
          right: -1,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E),
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).scaffoldBackgroundColor,
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // AI 回复里可能混着纯文字/```lang代码块```/$$公式$$——按顺序切开分别
  // 渲染，不是整段当纯文字丢进一个气泡。极梦相关文章那种"引用卡片"是
  // Demo 里的装饰性元素，没有对应的真实数据来源（后端回复只有一个纯
  // 文本 reply 字段，没有引用了哪篇文章的结构化信息），没有做
  // 模型实际回复里公式不止 $$...$$ 一种写法——真实见过 \[...\]（行间）、
  // \(...\)（行内）、$$...$$（行间）、$...$（行内）四种都在用，只认
  // $$ 会把另外三种原样漏成文字。$...$ 那条不允许跨行/不允许内容为空，
  // 是为了不误吞代码块里孤立的美元符号
  List<Widget> _buildContent(String content, bool isDark) {
    final regex = RegExp(
      r'```(\w*)\n([\s\S]*?)```'
      r'|\\\[([\s\S]*?)\\\]'
      r'|\\\(([\s\S]*?)\\\)'
      r'|\$\$([\s\S]*?)\$\$'
      r'|\$([^\$\n]+)\$',
    );
    final widgets = <Widget>[];
    var last = 0;
    for (final m in regex.allMatches(content)) {
      if (m.start > last) {
        final text = content.substring(last, m.start).trim();
        if (text.isNotEmpty) widgets.add(_textBubble(text, isDark));
      }
      if (m.group(2) != null) {
        final lang = (m.group(1) ?? '').trim();
        final code = m.group(2) ?? '';
        widgets.add(_codeBubble(code, lang.isEmpty ? 'code' : lang));
        final cellType = _notebookCellType(lang);
        if (cellType != null) {
          widgets.add(_runInNotebookButton(code, cellType));
        }
      } else {
        final formula = m.group(3) ?? m.group(4) ?? m.group(5) ?? m.group(6) ?? '';
        final isDisplay = m.group(3) != null || m.group(5) != null;
        widgets.add(_formulaBubble(formula, isDark, isDisplay: isDisplay));
      }
      last = m.end;
    }
    if (last < content.length) {
      final text = content.substring(last).trim();
      if (text.isNotEmpty) widgets.add(_textBubble(text, isDark));
    }
    if (widgets.isEmpty) widgets.add(_textBubble(content, isDark));
    return widgets;
  }

  Widget _textBubble(String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          height: 1.55,
          color: isDark
              ? Colors.white.withValues(alpha: 0.9)
              : const Color(0xFF1A1A1A),
        ),
      ),
    );
  }

  Widget _formulaBubble(String tex, bool isDark, {bool isDisplay = true}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? _primary.withValues(alpha: 0.12) : const Color(0xFFEEF0FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Math.tex(
        tex.trim(),
        mathStyle: isDisplay ? MathStyle.display : MathStyle.text,
        textStyle: TextStyle(
          fontSize: isDisplay ? 16 : 14,
          color: isDark ? Colors.white.withValues(alpha: 0.9) : const Color(0xFF1A1A1A),
        ),
        onErrorFallback: (err) => Text(
          tex,
          style: const TextStyle(fontSize: 13, color: Color(0xFFDC2626)),
        ),
      ),
    );
  }

  Widget _codeBubble(String code, String lang) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      constraints: const BoxConstraints(maxWidth: 260),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3A3A5C), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E2E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(
              children: [
                Text(
                  lang.toUpperCase(),
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
                  child: const Text(
                    '复制',
                    style: TextStyle(fontSize: 10, color: Color(0xFF9B9EF8)),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: Color(0xFF282840),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(11)),
            ),
            child: Text(
              code.trim(),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: Color(0xFFE0E0FF),
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 代码块「运行」——聊天页没有可复用的独立执行服务（Notebook 的 Python
  // 执行是绑死在 NotebookEditorScreen 一个 State 里的 WebView+Pyodide
  // JS桥接，不是能抽出来直接调的 service），与其在这里重新糊一套执行
  // 环境，不如把这段代码存成一个新 Notebook 并跳转过去，用 Notebook
  // 现成的环境跑——Python/SQL 跳过去是真的能运行，R/Julia 跳过去后跟
  // 用户在 Notebook 首页自己新建一个 R/Julia cell 看到的一样，还是
  // 「即将上线」，不会显得比原来更假
  String? _notebookCellType(String lang) {
    switch (lang.toLowerCase()) {
      case 'python':
      case 'py':
        return 'python';
      case 'sql':
        return 'sql';
      case 'r':
        return 'r';
      case 'julia':
        return 'julia';
      case 'javascript':
      case 'js':
        return 'javascript';
      default:
        return null;
    }
  }

  Future<void> _runInNotebook(String code, String cellType) async {
    final user = ref.read(currentUserProvider);
    final svc = NotebookService(user?.id ?? 'guest');
    final now = DateTime.now().millisecondsSinceEpoch;
    final nb = Notebook(
      id: 'nb_$now',
      name: '小梦生成的代码',
      lang: cellType == 'python' ? 'python' : 'mixed',
      cells: [NotebookCell(id: 'cell_$now', type: cellType, code: code)],
      createdAt: now ~/ 1000,
      updatedAt: now ~/ 1000,
    );
    await svc.save(nb);
    if (!mounted) return;
    context.push('/notebook/${nb.id}');
  }

  Widget _runInNotebookButton(String code, String cellType) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: GestureDetector(
        onTap: () => _runInNotebook(code, cellType),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _primary,
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.play_arrow, size: 14, color: Colors.white),
              SizedBox(width: 4),
              Text(
                '在 Notebook 中运行',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typingRow() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          _miniAvatar(),
          const SizedBox(width: 8),
          const _TypingDots(),
        ],
      ),
    );
  }

  Widget _buildToolbar(bool isDark) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
      child: Row(
        children: [
          _toolbarBtn(Icons.alternate_email, '引用内容', () => _comingSoon('引用内容')),
          const SizedBox(width: 18),
          _toolbarBtn(Icons.image_outlined, '图片', () => _comingSoon('图片')),
          const SizedBox(width: 18),
          _toolbarBtn(
            Icons.play_arrow_outlined,
            '在 Notebook 运行',
            () => _comingSoon('在 Notebook 运行'),
          ),
        ],
      ),
    );
  }

  Widget _toolbarBtn(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.grey[500]),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _buildInputBar(bool isDark) {
    // 工具栏/输入栏之前都用 cardColor，跟消息列表所在的
    // scaffoldBackgroundColor 不是一个颜色——按老规矩统一。输入框内部的
    // 胶囊之前吃全局 inputDecorationTheme.fillColor，跟 cardColor 太接近，
    // 灰蒙蒙糊在一起，换成好友页搜索框同款更深一档的胶囊底，TextField
    // 自己要显式 filled:false，不然还是会被全局主题的填充色盖住
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 100),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : const Color(0xFFE8E8ED),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: TextField(
                    controller: _inputCtrl,
                    focusNode: _focusNode,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: '问小梦任何问题...',
                      filled: false,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _sending ? null : () => _send(),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _sending ? Colors.grey[400] : _primary,
                    shape: BoxShape.circle,
                  ),
                  child: _sending
                      ? const Padding(
                          padding: EdgeInsets.all(9),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send, size: 16, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 三个点弹跳的打字动画——AnimationController 驱动三个点各自延迟一点
// 相位的上下位移，不是三张静态图切换
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor, width: 0.5),
      ),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final phase = (_ctrl.value - i * 0.2) % 1.0;
              final dy = phase < 0.5 ? -4 * (phase * 2) : -4 * (1 - (phase - 0.5) * 2);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Transform.translate(
                  offset: Offset(0, dy),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Colors.grey[400],
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
