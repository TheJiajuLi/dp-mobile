import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/utils/storage_checker.dart';
import '../../auth/auth_service.dart';
import '../models/conversation_model.dart';
import '../models/message_model.dart';

const _primary = Color(0xFF6366F1);

String _initial(String? name) {
  if (name == null || name.isEmpty) return '?';
  return name.substring(0, 1).toUpperCase();
}

// 跟全项目其它头像渲染的地方（user_profile_screen/edit_profile_screen/
// home_screen 等）保持同一套判断：data:image 开头是旧的 base64 头像，
// 否则是 COS 的图片 URL，用 CachedNetworkImageProvider 而不是 NetworkImage
// 才能吃到缓存
Widget _buildAvatar(
  String? avatar,
  String username,
  Color bgColor, {
  double radius = 16,
}) {
  if (avatar != null && avatar.isNotEmpty) {
    if (avatar.startsWith('data:image')) {
      try {
        return CircleAvatar(
          radius: radius,
          backgroundImage: MemoryImage(base64Decode(avatar.split(',').last)),
        );
      } catch (_) {
        // 解码失败落到下面的首字母占位
      }
    } else {
      return CircleAvatar(
        radius: radius,
        backgroundImage: CachedNetworkImageProvider(avatar),
      );
    }
  }
  return CircleAvatar(
    radius: radius,
    backgroundColor: bgColor,
    child: Text(
      _initial(username),
      style: TextStyle(
        color: Colors.white,
        fontSize: radius * 0.75,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class ChatScreen extends ConsumerStatefulWidget {
  final String conversationId;
  final Conversation? conversation;

  const ChatScreen({
    super.key,
    required this.conversationId,
    this.conversation,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _sendingImage = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    // 每 5 秒拉新消息
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadMessages());
  }

  Future<void> _loadMessages() async {
    final res = await ref
        .read(apiClientProvider)
        .get('/auth/conversations/${widget.conversationId}/messages');
    if (!res.success || res.data == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final list = (res.data['messages'] as List)
          .map((j) => ChatMessage.fromJson(j as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      setState(() {
        _messages = list;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send({
    String? text,
    String type = 'text',
    Map<String, dynamic>? metadata,
  }) async {
    debugPrint('[Chat] _send调用');
    final content = text ?? _ctrl.text.trim();
    debugPrint('[Chat] content: "$content"');
    if (content.isEmpty) {
      debugPrint('[Chat] ❌ content为空');
      return;
    }

    final otherId = widget.conversation?.otherUserId ?? '';
    debugPrint('[Chat] conversationId: ${widget.conversationId}');
    debugPrint('[Chat] conversation: ${widget.conversation}');
    debugPrint('[Chat] otherId: "$otherId"');
    if (otherId.isEmpty) {
      debugPrint('[Chat] ❌ otherId为空，无法发送');
      return;
    }

    debugPrint('[Chat] 准备发送到 /auth/messages');
    _ctrl.clear();
    final res = await ref.read(apiClientProvider).post('/auth/messages', data: {
      'toUserId': otherId,
      'content': content,
      'type': type,
      if (metadata != null) 'metadata': metadata,
    });
    if (!res.success) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('发送失败：${res.message}')));
      return;
    }
    await _loadMessages();
  }

  Future<void> _sendImage() async {
    if (_sendingImage) return;
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 80,
    );
    if (file == null) return;

    final bytes = await file.readAsBytes();
    if (!mounted) return;

    // 存储检查放在拿到文件字节之后——发送前才知道这张图实际多大，
    // 挑图之前根本没有 estimatedBytes 可用
    final ok = await StorageChecker.checkAndPrompt(
      context,
      ref,
      estimatedBytes: bytes.length,
    );
    if (!ok) return;
    if (!mounted) return;

    setState(() => _sendingImage = true);
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: 'img_${DateTime.now().millisecondsSinceEpoch}.jpg',
          contentType: DioMediaType('image', 'jpeg'),
        ),
      });

      // ApiClient.post 内部吞掉了 DioException，不会抛异常——失败与否要看
      // res.success，不能只靠 try/catch
      final uploadRes = await ref
          .read(apiClientProvider)
          .post('/auth/files/upload', data: formData);
      if (!uploadRes.success) {
        throw Exception(uploadRes.message ?? '上传失败，请重试');
      }

      final imageUrl = (uploadRes.data as Map)['url'] as String?;
      if (imageUrl == null) {
        throw Exception('上传失败，请重试');
      }

      await _send(text: imageUrl, type: 'image');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发图失败：${e.toString().replaceAll('Exception: ', '')}')),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingImage = false);
    }
  }

  void _showImagePreview(BuildContext context, String url) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          body: Center(
            child: InteractiveViewer(
              child: CachedNetworkImage(imageUrl: url),
            ),
          ),
        ),
      ),
    );
  }

  void _showAttachMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration:
                  BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _attachBtn(Icons.code, '代码', () {
                  Navigator.pop(ctx);
                  _showCodeInput();
                }),
                _attachBtn(Icons.functions, '公式', () {
                  Navigator.pop(ctx);
                  _showLatexInput();
                }),
                _attachBtn(Icons.article_outlined, '教程', () {
                  Navigator.pop(ctx);
                  // TODO: 选择教程分享
                }),
                _attachBtn(Icons.image, '图片', () {
                  Navigator.pop(ctx);
                  _sendImage();
                }),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showCodeInput() {
    final codeCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('发送代码', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Container(
              decoration:
                  BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: codeCtrl,
                maxLines: 6,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Colors.white),
                decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: '# 输入代码...',
                    hintStyle: TextStyle(color: Colors.grey)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () {
                  Navigator.pop(ctx);
                  _send(text: codeCtrl.text.trim(), type: 'code');
                },
                child: const Text('发送', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLatexInput() {
    final latexCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('发送公式', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              controller: latexCtrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: r'例：\frac{1}{2}',
                filled: true,
                fillColor: Theme.of(ctx).inputDecorationTheme.fillColor,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () {
                  final latex = latexCtrl.text.trim();
                  // 之前这里不管输入框是不是空的都先 pop 再发，空输入时
                  // _send() 内部会因为 content.isEmpty 直接 return——弹窗
                  // 已经关了，但什么都没发出去，跟"点了没反应"一样
                  if (latex.isEmpty) return;
                  Navigator.pop(ctx);
                  // 用独立的 type='latex'，不是 type='code' + metadata。
                  // 实测两种后端都接受、都能正确存取，但依赖 metadata 里的
                  // language 字段才能认出这是公式，比直接用 type 多一层
                  // 容易失配的环节——type 字段是消息模型里保证一定有的
                  _send(text: latex, type: 'latex');
                },
                child: const Text('发送', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _attachBtn(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration:
                BoxDecoration(color: const Color(0xFFEEF0FF), borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: _primary, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(currentUserProvider)?.id ?? '';
    final otherName = widget.conversation?.otherUsername ?? '用户';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // 顶部栏
            Container(
              color: Theme.of(context).cardColor,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios, size: 18),
                    onPressed: () => context.pop(),
                  ),
                  _buildAvatar(
                    widget.conversation?.otherAvatar,
                    otherName,
                    _primary,
                    radius: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(otherName,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  const Icon(Icons.more_horiz, size: 22),
                ],
              ),
            ),

            // 消息列表
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.all(12),
                      itemCount: _messages.length,
                      itemBuilder: (ctx, i) => _buildBubble(_messages[i], currentUserId),
                    ),
            ),

            // 图片发送中提示——上传/发消息接口都要走一次网络请求，
            // attach 菜单已经关掉了，不给点反馈会看起来跟点了没反应一样
            if (_sendingImage)
              Container(
                width: double.infinity,
                color: Theme.of(context).cardColor,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _primary),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '发送图片中...',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color),
                    ),
                  ],
                ),
              ),

            // 输入栏
            Container(
              color: Theme.of(context).cardColor,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _showAttachMenu,
                    child: const Icon(Icons.add_circle_outline, size: 26, color: Colors.grey),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).inputDecorationTheme.fillColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: TextField(
                        controller: _ctrl,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: '发消息...',
                          hintStyle: TextStyle(color: Colors.grey),
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      debugPrint('[Chat] 发送按钮点击');
                      _send();
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(color: _primary, shape: BoxShape.circle),
                      child: const Icon(Icons.send, color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBubble(ChatMessage msg, String currentUserId) {
    final isMe = msg.senderId == currentUserId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            _buildAvatar(msg.senderAvatar, msg.senderUsername, const Color(0xFF16A34A)),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                _buildBubbleContent(msg, isMe),
                const SizedBox(height: 3),
                Text(_formatTime(msg.createdAt),
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 8),
            _buildAvatar(msg.senderAvatar, msg.senderUsername, _primary),
          ],
        ],
      ),
    );
  }

  Widget _buildBubbleContent(ChatMessage msg, bool isMe) {
    if (msg.type == 'image') {
      return GestureDetector(
        onTap: () => _showImagePreview(context, msg.content),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CachedNetworkImage(
            imageUrl: msg.content,
            width: 200,
            fit: BoxFit.cover,
            placeholder: (ctx, url) => Container(
              width: 200,
              height: 150,
              color: Colors.grey[200],
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            errorWidget: (ctx, url, error) => Container(
              width: 200,
              height: 100,
              color: Colors.grey[200],
              child: const Icon(Icons.broken_image, color: Colors.grey),
            ),
          ),
        ),
      );
    }

    // type=='latex' 是现在发公式走的路径；旧的 type=='code'+metadata.language
    // 这个组合以前也用来发过公式，两个都认，历史消息不会突然变回代码块
    final isLatex = msg.type == 'latex' || (msg.type == 'code' && msg.metadata?['language'] == 'latex');
    if (isLatex) {
      final tex = msg.content.replaceAll(r'$$', '').replaceAll(r'\[', '').replaceAll(r'\]', '').trim();
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe ? _primary : Theme.of(context).cardColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMe ? 18 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 18),
          ),
          border: isMe ? null : Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Math.tex(
          tex,
          textStyle: TextStyle(
            fontSize: 16,
            color: isMe ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color,
          ),
          onErrorFallback: (err) => Text(msg.content,
              style: TextStyle(fontSize: 13, color: isMe ? Colors.white : Colors.red)),
        ),
      );
    }

    if (msg.type == 'code') {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration:
            BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(14)),
        child: Text(msg.content,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Colors.white, height: 1.5)),
      );
    }

    // 普通文字气泡
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isMe ? _primary : Theme.of(context).cardColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isMe ? 18 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 18),
        ),
        border: isMe ? null : Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Text(msg.content,
          style: TextStyle(
            fontSize: 15,
            color: isMe ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color,
            height: 1.4,
          )),
    );
  }

  String _formatTime(int tsMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(tsMs);
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
