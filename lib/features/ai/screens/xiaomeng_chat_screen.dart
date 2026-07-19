import 'dart:convert';

import 'package:dio/dio.dart'
    show DioException, Options, ResponseBody, ResponseType;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/widgets/ai_content_renderer.dart';
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
  // HD 双栏右栏内嵌时（HdXmengPage）传 false 隐藏返回键——右栏内嵌没有可 pop
  // 的路由（maybePop 不炸但点了没反应，是个死按钮）。手机端 push 进来不传
  final bool showBackButton;
  const XiaomengChatScreen({
    super.key,
    this.conversationId,
    this.initialMessage,
    this.showBackButton = true,
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
    if (widget.initialMessage != null &&
        widget.initialMessage!.trim().isNotEmpty) {
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
          content: Text(
            e.response?.data is Map
                ? ((e.response!.data as Map)['message']?.toString() ??
                      '小梦暂时休息中，请稍后再试')
                : '小梦暂时休息中，请稍后再试',
          ),
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
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  if (widget.showBackButton)
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
              // 点空白处收起键盘
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => FocusScope.of(context).unfocus(),
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
            ),
            _buildToolbar(isDark),
            _buildInputBar(isDark),
          ],
        ),
      ),
    );
  }

  // jisuo（极索）发起的对话，首条起每条用户消息前面都拼了「AI 偏好语言」
  // 指令（[请用简体中文。] / [Please respond in English.] / [请用中英混合：…]），
  // 存进了 ai_messages，从历史加载回来就会显示在用户气泡里。这里只剥掉这种
  // 「[请用…]/[Please respond…] + 换行」的语言前缀，不误伤用户自己打的 [xxx]。
  // 本屏 _send 发的是原文、没有前缀，剥了也是无变化（幂等）
  String _stripLangPrefix(String content) {
    return content
        .replaceFirst(
          RegExp(r'^\s*\[(请用|Please respond)[^\]]*\]\s*\n'),
          '',
        )
        .trimLeft();
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
            _stripLangPrefix(msg.content),
            style: const TextStyle(
              fontSize: 14,
              color: Colors.white,
              height: 1.4,
            ),
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
            child: AiContentRenderer(content: msg.content, isDark: isDark),
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
          decoration: const BoxDecoration(
            color: _primary,
            shape: BoxShape.circle,
          ),
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
  // AI 气泡外观：浅色白底、深色比页面底(#1C1C1E)略亮一档的靛调面(#23233A)，
  // 都带一圈细边；左下角小圆角(4)冲着头像那一侧，跟用户气泡镜像
  BoxDecoration _aiBubbleDecoration(bool isDark) => BoxDecoration(
    color: isDark ? const Color(0xFF23233A) : Colors.white,
    borderRadius: const BorderRadius.only(
      topLeft: Radius.circular(16),
      topRight: Radius.circular(16),
      bottomRight: Radius.circular(16),
      bottomLeft: Radius.circular(4),
    ),
    border: Border.all(
      color: isDark
          ? Colors.white.withValues(alpha: 0.08)
          : const Color(0xFFEBEBEB),
      width: 0.5,
    ),
  );

  Widget _typingRow() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          _miniAvatar(),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: _aiBubbleDecoration(isDark),
            child: const _TypingDots(),
          ),
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
          _toolbarBtn(Icons.alternate_email, '引用', () => _comingSoon('引用内容')),
          const SizedBox(width: 20),
          _toolbarBtn(Icons.image_outlined, '图片', () => _comingSoon('图片')),
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
              final dy = phase < 0.5
                  ? -4 * (phase * 2)
                  : -4 * (1 - (phase - 0.5) * 2);
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
