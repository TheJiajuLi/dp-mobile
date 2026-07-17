import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, KeyDownEvent, LogicalKeyboardKey;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../../shared/utils/latex_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/utils/block_text_style.dart';
import '../../../shared/utils/pro_access.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/utils/ai_lang.dart';
import '../../../shared/utils/code_highlight.dart';
import '../../../shared/widgets/tutorial_block_renderer.dart'
    show inlineLatexText;
import '../models/block_model.dart';
import 'block_picker_sheet.dart';

const _primary = Color(0xFF6366F1);

String _formatSize(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
}

class BlockCard extends ConsumerStatefulWidget {
  final EditorBlock block;
  final int index;
  final int total;
  // 实测确认：currentUserProvider 的 UserModel 上没有 membership 字段，
  // 会员等级只有 GET /auth/storage/usage 会返回。这个值改成由父级
  // PublishScreen 用 ref.watch(storageUsageProvider) 拿到之后往下传，
  // 而不是在这里自己 ref.read——storageUsageProvider 是 autoDispose 的
  // FutureProvider，没有人在 watch 的话这里读到的会是还没算完的
  // AsyncLoading，永远兜底成 free，付费用户也会被误判成免费版
  final String membership;
  // 真正跑代码的入口，由 PublishScreen 统一持有隐藏 WebView/Pyodide 引擎并
  // 实现；这里不需要知道 WebView 是否就绪、SQL 要不要包装这些细节，调用
  // 一次拿到一份 [{type, content}, ...] 结果就行——环境还没就绪时会在
  // PublishScreen 那边等最多60秒，不是立刻失败
  final Future<List<Map<String, dynamic>>> Function(
    String blockId,
    String code,
    String language,
  )
  onRunCode;
  final VoidCallback onDelete;
  // 文字/标题/代码/公式 block 内容为空时按 Backspace/Delete——删掉这个
  // block 并把焦点交回上一个 block，跟主流block编辑器（Notion等）的
  // 直觉一致。null 表示不适用（比如这是列表第一个block，没有"上一个"
  // 可以交焦点，交给调用方决定要不要允许在这种情况下也删除）
  final VoidCallback? onEmptyBackspace;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onChanged;
  // 文字/标题 block 获得焦点时通知 PublishScreen——底部格式工具栏（粗体/
  // 颜色/字体等）只在"当前正在编辑哪个 block"明确的时候才有意义，这个
  // 状态本来就该由父级持有，不是 BlockCard 自己的事
  final VoidCallback? onFocusGained;
  // 文字/标题输入框失焦（收起键盘/切到别的控件）时通知父级清掉
  // focusedBlockId——不然格式工具栏只会越绑越"新"，永远不会真正收起
  final VoidCallback? onFocusLost;
  // 非文字类block（图片/代码/公式等）点击时通知父级——这些block不适用
  // 格式工具栏，点了应该让工具栏收起，不是继续绑在上一个文字block上
  final VoidCallback? onNonTextTap;
  // 父级当前"激活"的是哪个block——卡片自己的chrome（拖拽手柄/AI按钮/
  // 移动/删除/边框）只在这个block是激活态时才显示，平时收起来减少噪音
  final String? focusedBlockId;
  // 每次上传文件成功（图片/视频/音频/文件）把后端返回的 file id 报给
  // PublishScreen 收集，退出未保存时用来清理 COS 里这些孤儿文件
  final void Function(String fileId)? onFileUploaded;
  // latex 块的公式编号（文档内第 n 个 autoNumber 公式）——由 PublishScreen 按
  // 位置算好传进来，null=该块 autoNumber 关 或 非 latex
  final int? equationNumber;

  const BlockCard({
    super.key,
    required this.block,
    required this.index,
    required this.total,
    required this.membership,
    required this.onRunCode,
    required this.onDelete,
    this.onEmptyBackspace,
    this.onMoveUp,
    this.onMoveDown,
    required this.onChanged,
    this.onFocusGained,
    this.onFocusLost,
    this.onNonTextTap,
    this.focusedBlockId,
    this.onFileUploaded,
    this.equationNumber,
  });

  @override
  ConsumerState<BlockCard> createState() => _BlockCardState();
}

class _BlockCardState extends ConsumerState<BlockCard> {
  bool _running = false;
  bool _focused = false;
  bool _polishing = false;
  // 文字 block 用的是 TextFormField(initialValue: ...)，不是受控的
  // controller——小梦优化后台把 widget.block.content 改掉再 setState 是
  // 不会自动反映到输入框上的（initialValue 只在第一次创建时读一次）。
  // 靠这个计数器换 key 强制 TextFormField 整个重建，才能捡到新的
  // initialValue；只在"应用优化结果"时才 +1，正常打字不碰它，
  // 不会打断输入焦点/光标位置
  int _textRevision = 0;
  // 代码块专用——用能实时按 token 上色的 controller 替代默认的
  // TextFormField(initialValue: ...)，编辑态才能跟阅读态一样有语法高亮
  late final HighlightingCodeController _codeCtrl = HighlightingCodeController(
    text: widget.block.content,
    language: widget.block.language ?? 'python',
  );

  // Markdown 块专用受控 controller——不再走 initialValue+换key 那套。listener
  // 把输入同步进 block.content 并 onChanged；外部改内容（小梦/帮我写）由
  // didUpdateWidget 反向同步进 controller。_mdSyncing 防外部同步时又触发一次
  // onChanged（在 didUpdateWidget 里 setState 会炸）
  TextEditingController? _mdController;
  bool _mdSyncing = false;

  void _initMdController() {
    if (widget.block.type != BlockType.markdown) return;
    _mdController = TextEditingController(text: widget.block.content);
    _mdController!.addListener(() {
      if (_mdSyncing) return;
      widget.block.content = _mdController!.text;
      widget.onChanged();
    });
  }

  // AI/运行输出区的滚动控制器——超过 maxHeight 可滚动；打字机流式输出时
  // 每次内容更新后自动滚到底部，跟着最新文字走
  final ScrollController _aiScrollCtrl = ScrollController();

  // 小梦流式输出的字符队列 + 15ms 打字机 Timer（跟极索页同一套）——SSE 分片
  // 逐字符入队，Timer 每 15ms 吐一个到 outputContent，实现打字机效果
  final Queue<String> _aiCharQueue = Queue<String>();
  Timer? _aiTypeTimer;

  @override
  void initState() {
    super.initState();
    // 用 FocusNode 监听而不是 TextFormField.onTap——_addBlock() 新建
    // block 后是程序调用 focusNode.requestFocus()，不会触发用户点击
    // 手势的 onTap，底部格式工具栏得靠这个监听器才能知道新 block 也
    // "获得了焦点"
    widget.block.focusNode.addListener(_handleFocusChange);
    _initMdController();
  }

  @override
  void didUpdateWidget(covariant BlockCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部改了 Markdown 内容（小梦帮我写填入等）→ 反向同步进 controller，
    // 光标落到末尾。_mdSyncing 期间 listener 不回写、不 onChanged
    if (widget.block.type == BlockType.markdown &&
        _mdController != null &&
        _mdController!.text != widget.block.content) {
      _mdSyncing = true;
      _mdController!.value = TextEditingValue(
        text: widget.block.content,
        selection: TextSelection.collapsed(offset: widget.block.content.length),
      );
      _mdSyncing = false;
    }
  }

  void _handleFocusChange() {
    final hasFocus = widget.block.focusNode.hasFocus;
    // _focused 跟随真实焦点：获焦→编辑态、失焦→预览态。统一所有块（文字/标题/
    // 公式/Markdown）的编辑↔预览切换——修 Markdown 输入一个字就丢焦（程序化
    // 聚焦时 _focused 一直是 false，敲字后内容非空就切回渲染态把输入框拆掉），
    // 以及 # 标题失焦后不渲染（原来只有 onEditingComplete 才置 false，点别处/
    // 收键盘都不触发）。mounted 保护 + 只在真的变化时 setState，避免多余重建
    if (mounted && _focused != hasFocus) {
      setState(() => _focused = hasFocus);
    }
    if (hasFocus) {
      widget.onFocusGained?.call();
    } else {
      widget.onFocusLost?.call();
    }
  }

  bool get _isActive => widget.block.id == widget.focusedBlockId;

  // 空 block 按 Backspace/Delete 删除——包一层 Focus 当祖先拦截键盘事件，
  // 不碰输入框自己的 FocusNode，也不影响内容非空时的正常删字符行为
  // （那种情况下这里直接 ignored，交回给输入框自己处理）。iOS 软键盘的
  // 删除键在内容已清空时也会正常触发这个回调，不是只有外接键盘才有效
  KeyEventResult _handleEmptyBackspace(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isDeleteKey =
        event.logicalKey == LogicalKeyboardKey.backspace ||
        event.logicalKey == LogicalKeyboardKey.delete;
    if (!isDeleteKey || widget.onEmptyBackspace == null) {
      return KeyEventResult.ignored;
    }
    // 辅助诊断：确认 backspace/delete 真的触达了这里，以及此刻 content 到底是
    // 什么——区分"只含空白/换行的块"和"事件根本没到"两种情况
    debugPrint(
      '[EmptyBackspace] content: "${widget.block.content}" '
      'trim: "${widget.block.content.trim()}"',
    );
    // 空判定用 trim 对齐"看起来空"的渲染口径（预览态判空也是 content.trim()）——
    // 只含空格/换行的块看着是空框、以前因为 content.isNotEmpty 为真删不掉，现在
    // 也能删
    if (widget.block.content.trim().isEmpty) {
      widget.onEmptyBackspace?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _withEmptyBackspace(Widget child) => Focus(
    onKeyEvent: (node, event) => _handleEmptyBackspace(event),
    child: child,
  );

  @override
  void dispose() {
    widget.block.focusNode.removeListener(_handleFocusChange);
    _codeCtrl.dispose();
    _mdController?.dispose();
    _aiScrollCtrl.dispose();
    _aiTypeTimer?.cancel();
    super.dispose();
  }

  // ———————————————————————— 小梦流式打字机（输出区展示类动作）
  // 流式拉 /auth/xmeng/chat/stream，SSE 分片入队、15ms 逐字吐进 outputContent。
  // done 带的 fullText 是权威全文（分片偶发丢片），有就整段覆盖兜底。调用前
  // 已把 outputContent 置为 '' + type 'text'，进来就是空白开始打字
  Future<void> _streamXmengToOutput(String prompt) async {
    _aiTypeTimer?.cancel();
    _aiTypeTimer = null;
    _aiCharQueue.clear();
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
      await for (final line in lines) {
        if (!mounted) return;
        if (!line.startsWith('data:')) continue;
        final jsonStr = line.substring(5).trim();
        if (jsonStr.isEmpty) continue;
        Map<String, dynamic> data;
        try {
          data = jsonDecode(jsonStr) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }
        switch (data['type']) {
          case 'chunk':
            _enqueueAiChunk(data['text']?.toString() ?? '');
            break;
          case 'done':
            final full = data['fullText']?.toString();
            _flushAiTyping(
              fullText: (full != null && full.isNotEmpty) ? full : null,
            );
            break;
          case 'error':
            _flushAiTyping();
            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('小梦开小差了，请重试')));
            }
            break;
        }
      }
      // 流正常结束但没收到 done：把队列剩余的字补齐
      _flushAiTyping();
      widget.onChanged();
    } catch (e) {
      _flushAiTyping();
      // 一个字都没吐出来就失败：清掉空白输出气泡，别留一条空的
      if (mounted && (widget.block.outputContent ?? '').isEmpty) {
        setState(() {
          widget.block.outputContent = null;
          widget.block.outputType = null;
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('小梦开小差了，请重试')));
      }
      widget.onChanged();
    }
  }

  // 收到 chunk：按 grapheme（中文/emoji 安全）入队，启动/复用 15ms 打字机
  void _enqueueAiChunk(String text) {
    if (text.isEmpty) return;
    _aiCharQueue.addAll(text.characters);
    _aiTypeTimer ??= Timer.periodic(const Duration(milliseconds: 15), (_) {
      if (!mounted) {
        _aiTypeTimer?.cancel();
        _aiTypeTimer = null;
        return;
      }
      if (_aiCharQueue.isEmpty) return;
      final ch = _aiCharQueue.removeFirst();
      setState(() {
        widget.block.outputContent = (widget.block.outputContent ?? '') + ch;
        widget.block.outputType = 'text';
      });
      _autoScrollAiOutput();
    });
  }

  // 停打字机：取消 Timer，把队列里没吐完的字一次性补齐；done 带 fullText 就
  // 整段覆盖（兜底丢片），跟极索页 _flushTyping 同一套
  void _flushAiTyping({String? fullText}) {
    _aiTypeTimer?.cancel();
    _aiTypeTimer = null;
    final rest = _aiCharQueue.join();
    _aiCharQueue.clear();
    if (!mounted) return;
    setState(() {
      if (fullText != null && fullText.isNotEmpty) {
        widget.block.outputContent = fullText;
      } else if (rest.isNotEmpty) {
        widget.block.outputContent = (widget.block.outputContent ?? '') + rest;
      }
      widget.block.outputType = 'text';
    });
    _autoScrollAiOutput();
  }

  // 输出内容更新后把滚动区滚到底部——打字机流式输出时跟着最新文字走。
  // 内容没超过 maxHeight（maxScrollExtent==0）时是无操作，短输出不会乱跳
  void _autoScrollAiOutput() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_aiScrollCtrl.hasClients) return;
      _aiScrollCtrl.animateTo(
        _aiScrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 50),
        curve: Curves.easeOut,
      );
    });
  }

  // LaTeX 的"用自然语言生成公式"不需要已有内容，其余几种都需要已有内容才
  // 有得优化/解释——不然点开菜单里全是点了也没反应的选项
  bool get _showsAiButton {
    const aiTypes = {
      BlockType.text,
      BlockType.heading,
      BlockType.callout,
      BlockType.code,
      BlockType.latex,
    };
    if (!aiTypes.contains(widget.block.type)) return false;
    // 代码/公式块选中就显示小梦入口，不要求已有内容——代码助手/公式助手
    // 是常驻能力（文字/标题/引用是"优化已有内容"，才要求 content 非空）
    if (widget.block.type == BlockType.latex ||
        widget.block.type == BlockType.code) {
      return true;
    }
    return widget.block.content.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 未激活时卡片完全透明、无边框，跟页面融为一体；激活时才浮出白色/
    // 深色卡片背景+细描边——减少同屏一堆边框叠边框的视觉噪音，只有正在
    // 编辑的那一个 block 需要被"框"出来。代码块不再用深色 pill，跟文字/
    // 公式等内容块一样走这套（代码区本身是一圈中性描边的浅框，见
    // _buildCodeBlock），创作界面更纯净
    return GestureDetector(
      // 非文字/标题类block自己没有走 onFocusGained 那条路（它们的
      // FocusNode 没接到真正的输入框上，或者内部输入框跟格式工具栏无关，
      // 比如代码/公式源码框），点了要主动告诉父级——translucent 不会
      // 拦下内部各自的手势（图片点击换图/代码框输入等照常工作）
      behavior: HitTestBehavior.translucent,
      onTap: () {
        if (widget.block.type != BlockType.text &&
            widget.block.type != BlockType.heading) {
          widget.onNonTextTap?.call();
        }
      },
      child: Container(
        // 不再自带 bottom margin——发布页把每张卡片跟紧随其后的"+"插入条
        // 打包进同一个 ReorderableListView item，卡片之间的间距完全交给
        // 插入条自己的高度（静止收成4px/滚动展开成28px），不然会跟插入条
        // 叠出双倍间距
        decoration: BoxDecoration(
          color: _isActive ? Theme.of(context).cardColor : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: _isActive
              ? Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : const Color(0xFFEBEBEB),
                  width: 0.5,
                )
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 类型图标+类型名一行，操作按钮放在同一行右侧——拖拽手柄/AI入口/
            // 移动/删除只在这个block激活时才显示，平时收起来减少噪音
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 0),
              child: Row(
                children: [
                  // 只保留类型图标，去掉类型名文字标签——创作界面更纯净，
                  // 图标本身已经能表意
                  Icon(
                    blockTypeIcon(widget.block.type),
                    size: 14,
                    color: const Color(0xFF999999),
                  ),
                  const Spacer(),
                  // AI入口/上移/下移/删除/拖拽手柄——只在这个block是当前
                  // 激活的那一个时才显示，没激活时收起来，同屏不再是一堆
                  // block各自顶着一整排图标的噪音感
                  if (_isActive) ...[
                    if (_showsAiButton)
                      _polishing
                          ? const Padding(
                              padding: EdgeInsets.all(4),
                              child: SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: _primary,
                                ),
                              ),
                            )
                          : GestureDetector(
                              onTap: _onSparklesTap,
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  // 有 AI 回答时点亮成紫色实心，提示"再点一下清空"
                                  _hasAiAnswer
                                      ? Icons.auto_awesome
                                      : Icons.auto_awesome_outlined,
                                  size: 15,
                                  color: _hasAiAnswer
                                      ? _primary
                                      : Colors.grey.shade400,
                                ),
                              ),
                            ),
                    // 文字/标题/Markdown/LaTeX 的复制按钮——代码块有自己那个
                    // （下面跟运行成对），这里只给这四类，避免代码块出现两个
                    if (widget.block.type == BlockType.text ||
                        widget.block.type == BlockType.heading ||
                        widget.block.type == BlockType.markdown ||
                        widget.block.type == BlockType.latex)
                      GestureDetector(
                        onTap: _copyContent,
                        child: const Tooltip(
                          message: '复制',
                          child: Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.copy_outlined,
                              size: 15,
                              color: Color(0xFFBBBBBB),
                            ),
                          ),
                        ),
                      ),
                    // 代码块专属操作——复制、运行，跟 AI(小梦) 一起放在这排
                    // chrome 里（去掉代码块内容区那个独立运行按钮）
                    if (widget.block.type == BlockType.code) ...[
                      GestureDetector(
                        onTap: _copyContent,
                        child: const Tooltip(
                          message: '复制',
                          child: Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.copy_outlined,
                              size: 15,
                              color: Color(0xFFBBBBBB),
                            ),
                          ),
                        ),
                      ),
                      _running
                          ? const Padding(
                              padding: EdgeInsets.all(4),
                              child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: _primary,
                                ),
                              ),
                            )
                          : GestureDetector(
                              onTap: _runCode,
                              child: Tooltip(
                                message: l10n.runAction,
                                child: const Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.play_arrow_outlined,
                                    size: 17,
                                    color: _primary,
                                  ),
                                ),
                              ),
                            ),
                    ],
                    if (widget.onMoveUp != null)
                      GestureDetector(
                        onTap: widget.onMoveUp,
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.arrow_upward,
                            size: 16,
                            color: Color(0xFFBBBBBB),
                          ),
                        ),
                      ),
                    if (widget.onMoveDown != null)
                      GestureDetector(
                        onTap: widget.onMoveDown,
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.arrow_downward,
                            size: 16,
                            color: Color(0xFFBBBBBB),
                          ),
                        ),
                      ),
                    GestureDetector(
                      onTap: widget.onDelete,
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color: Color(0xFFBBBBBB),
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                  ],
                  // 拖拽手柄常驻显示（Notion 做法）——不用先点选，随时按住这个
                  // 把手就能立刻拖，不长按、不跟下面输入框的长按选字抢手势。
                  // chrome（AI/上移/下移/删除）仍然只在这个 block 激活时才露出。
                  ReorderableDragStartListener(
                    index: widget.index,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.drag_handle,
                        size: 18,
                        color: Color(0xFFCFCFCF),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              // 所有 block 统一四周留白——代码块自己是一圈中性描边的浅框，
              // 不再铺满整卡，跟文字/公式块的留白节奏一致
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
              child: _buildContent(l10n),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(AppLocalizations l10n) {
    switch (widget.block.type) {
      case BlockType.text:
        return _buildTextBlock(l10n);
      case BlockType.heading:
        return _buildHeadingBlock(l10n);
      case BlockType.code:
        return _buildCodeBlock(l10n);
      case BlockType.latex:
        return _buildLatexBlock(l10n);
      case BlockType.markdown:
        return _buildMarkdownBlock(l10n);
      case BlockType.image:
        return _buildImageBlock(l10n);
      case BlockType.file:
        return _buildFileBlock(l10n);
      case BlockType.audio:
        return _buildAudioBlock(l10n);
      case BlockType.video:
        return _buildVideoBlock(l10n);
      case BlockType.link:
        return _buildLinkBlock(l10n);
      case BlockType.callout:
        return _buildCalloutBlock(l10n);
    }
  }

  static final _inlineLatexPattern = RegExp(
    r'\$[^$\n]+\$'
    r'|\\\(.+?\\\)'
    r'|\\\[.+?\\\]',
    dotAll: true,
  );

  Widget _buildTextBlock(AppLocalizations l10n) {
    final style = applyBlockTextFormat(
      TextStyle(
        fontSize: 14,
        height: 1.7,
        color: Theme.of(context).textTheme.bodyLarge?.color,
      ),
      isBold: widget.block.isBold,
      isItalic: widget.block.isItalic,
      isUnderline: widget.block.isUnderline,
      isStrike: widget.block.isStrike,
      textColorValue: widget.block.textColorValue,
      highlightColorValue: widget.block.highlightColorValue,
      fontFamily: widget.block.fontFamily,
      fontSizeStep: widget.block.fontSizeStep,
      lineHeightStep: widget.block.lineHeightStep,
    );

    // 含 $...$/\(...\)/\[...\] 的文字段——没聚焦时渲染成真正的公式（跟阅读页
    // inlineLatexText 同一份逻辑），不然编辑器里永远只能看到原始
    // $公式$ 源码，写完公式也不知道对不对。一点上去切回原始
    // TextFormField 改源码，光标一收起（onEditingComplete）就切回渲染态。
    // 没有公式的普通段落不受影响，还是原来那个一直可编辑的 TextFormField
    final hasInlineLatex = _inlineLatexPattern.hasMatch(widget.block.content);
    if (!_focused && hasInlineLatex) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() => _focused = true);
          // 同 Markdown：等 TextFormField 挂载后再 requestFocus，避免同步调
          // 落空导致点了弹回预览
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.block.focusNode.requestFocus();
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: inlineLatexText(widget.block.content, style),
        ),
      );
    }

    return _withEmptyBackspace(
      TextFormField(
        key: ValueKey('text_${widget.block.id}_$_textRevision'),
        focusNode: widget.block.focusNode,
        initialValue: widget.block.content.isNotEmpty
            ? widget.block.content
            : null,
        decoration: const InputDecoration(
          filled: false,
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        style: style,
        maxLines: null,
        onChanged: (v) {
          widget.block.content = v;
          widget.onChanged();
        },
        onTap: () => setState(() => _focused = true),
        onEditingComplete: () => setState(() => _focused = false),
      ),
    );
  }

  // AI 回答块已生成完毕（有 outputContent、且不是 'info' loading 态）
  bool get _hasAiAnswer =>
      widget.block.outputContent != null && widget.block.outputType != 'info';

  // ✨ 点击：已有 AI 回答（LaTeX 解释/代码解释；代码运行输出也走同一个
  // outputContent，会一并清掉，重新运行即可）就二次点击清空、回到空白可
  // 重新生成；没有回答时正常打开小梦菜单
  void _onSparklesTap() {
    if (_hasAiAnswer && !_polishing) {
      setState(() {
        widget.block.outputContent = null;
        widget.block.outputType = null;
      });
      widget.onChanged();
      return;
    }
    _showAiMenu();
  }

  void _showAiMenu() {
    switch (widget.block.type) {
      case BlockType.text:
      case BlockType.heading:
      case BlockType.callout:
        _showTextAiMenu();
      case BlockType.code:
        _showCodeAiMenu();
      case BlockType.latex:
        _showLatexAiMenu();
      default:
        break;
    }
  }

  void _showTextAiMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Row(
              children: [
                Icon(Icons.auto_awesome, size: 18, color: _primary),
                SizedBox(width: 8),
                Text(
                  '小梦优化',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...[
              ('vivid', Icons.diamond_outlined, '优化文字', '让表达更生动流畅'),
              ('concise', Icons.content_cut, '精简浓缩', '删掉废话，留下精华'),
              ('formal', Icons.description_outlined, '正式化', '适合学术/报告风格'),
            ].map(
              (item) => ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    item.$2,
                    size: 17,
                    color: const Color(0xFF555555),
                  ),
                ),
                title: Text(
                  item.$3,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(item.$4, style: const TextStyle(fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _polishBlock(item.$1);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _polishBlock(String style) async {
    final original = widget.block.content;
    if (original.isEmpty) return;

    setState(() => _polishing = true);

    try {
      final res = await ref
          .read(apiClientProvider)
          .post('/auth/xmeng/polish', data: {'text': original, 'style': style});

      if (res.success && mounted) {
        final result = (res.data as Map?)?['result'] as String? ?? '';
        if (result.isNotEmpty) {
          showDialog(
            context: context,
            builder: (dCtx) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.auto_awesome, size: 18, color: _primary),
                  SizedBox(width: 8),
                  Text('小梦的修改'),
                ],
              ),
              content: SingleChildScrollView(
                child: Text(
                  result,
                  style: const TextStyle(fontSize: 14, height: 1.6),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dCtx),
                  child: const Text(
                    '不用了',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      widget.block.content = result;
                      _textRevision++;
                    });
                    widget.onChanged();
                    Navigator.pop(dCtx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    '应用',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('小梦开小差了，请重试')));
      }
    } finally {
      if (mounted) setState(() => _polishing = false);
    }
  }

  void _showCodeAiMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF0FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_outlined,
                    size: 14,
                    color: _primary,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  '小梦代码助手',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...[
              ('explain', Icons.menu_book_outlined, '解释代码', '用简单语言解释这段代码'),
              ('optimize', Icons.speed_outlined, '优化代码', '提升可读性和性能'),
              ('comment', Icons.comment_outlined, '添加注释', '为每行添加中文注释'),
              ('bug', Icons.bug_report_outlined, '查找问题', '检查潜在的bug'),
            ].map(
              (item) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    item.$2,
                    size: 17,
                    color: const Color(0xFF555555),
                  ),
                ),
                title: Text(
                  item.$3,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(item.$4, style: const TextStyle(fontSize: 12)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _assistCode(item.$1);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _assistCode(String action) async {
    final code = widget.block.content;
    if (code.isEmpty) return;

    // AI 偏好语言——解释/注释这类自然语言输出跟着设置走，prompt 里不再写死"中文"
    final langHint = await aiLangHint();
    final prompts = {
      'explain':
          '$langHint请用简洁的语言解释以下代码的功能和逻辑，分点说明：\n\n'
          '```${widget.block.language}\n$code\n```',
      'optimize':
          '$langHint请优化以下代码，提升可读性和性能，直接输出优化后的完整代码：\n\n'
          '```${widget.block.language}\n$code\n```',
      'comment':
          '$langHint为以下代码每行添加简洁的注释，直接输出带注释的完整代码：\n\n'
          '```${widget.block.language}\n$code\n```',
      'bug':
          '$langHint检查以下代码中可能存在的bug或问题，列出问题和修改建议：\n\n'
          '```${widget.block.language}\n$code\n```',
    };
    final prompt = prompts[action] ?? '';

    // 解释代码 / 查找问题：结果展示在块下方 → 流式打字机逐字吐出（空白开始打字）
    if (action == 'explain' || action == 'bug') {
      setState(() {
        widget.block.outputContent = '';
        widget.block.outputType = 'text';
      });
      widget.onChanged();
      await _streamXmengToOutput(prompt);
      return;
    }

    // 优化代码 / 添加注释：结果是要替换的完整代码，仍走非流式 + 确认弹层
    setState(() {
      widget.block.outputContent = '小梦分析中...';
      widget.block.outputType = 'info';
    });
    widget.onChanged();

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
            options: Options(receiveTimeout: const Duration(seconds: 60)),
          );

      setState(() {
        widget.block.outputContent = null;
        widget.block.outputType = null;
      });

      if (!res.success || !mounted) return;
      final result = (res.data as Map?)?['message'] as String? ?? '';
      if (result.isEmpty) return;

      {
        // 优化/注释这两种是"替换代码"操作，弹确认框而不是直接覆盖，避免
        // 一言不合就把用户已经写好的代码冲掉
        // 解析小梦返回的 markdown：把代码围栏内的代码抽出来单独用深色高亮
        // 面板渲染，围栏前的说明文字作为引子；没有围栏就整体当文本展示。
        // 「应用」落库的也是抽出来的纯代码（跟展示一致，不再把 ``` 一起塞回）
        final codeMatch = RegExp(
          r'```(\w*)\n?([\s\S]*?)```',
        ).firstMatch(result);
        final fenceLang = codeMatch?.group(1)?.trim() ?? '';
        final suggestedCode = (codeMatch?.group(2)?.trim() ?? result).trim();
        final leadText = codeMatch != null
            ? result.substring(0, codeMatch.start).trim()
            : '';
        final hlLang = fenceLang.isNotEmpty
            ? fenceLang
            : (widget.block.language ?? 'python');

        void applySuggestion(BuildContext dCtx) {
          setState(() {
            widget.block.content = suggestedCode;
            _codeCtrl.text = suggestedCode;
          });
          widget.onChanged();
          Navigator.pop(dCtx);
        }

        showDialog(
          context: context,
          builder: (dCtx) {
            final isDark = Theme.of(dCtx).brightness == Brightness.dark;
            final ink = isDark
                ? const Color(0xFFF0F2F8)
                : const Color(0xFF1A1A1A);
            final muted = isDark ? Colors.white60 : const Color(0xFF8A8F99);
            const codeBase = TextStyle(
              fontFamily: 'monospace',
              fontSize: 12.5,
              height: 1.6,
              color: Color(0xFFE0E2F0),
            );
            return Dialog(
              backgroundColor: isDark ? const Color(0xFF1C1D24) : Colors.white,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 40,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(dCtx).size.height * 0.7,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 头部：品牌紫渐变 sparkle 图标 + 标题
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF818CF8), Color(0xFF6366F1)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.auto_awesome,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '小梦的建议',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (leadText.isNotEmpty) ...[
                              Text(
                                leadText,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  height: 1.5,
                                  color: muted,
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            // 深色代码面板（VS Code Dark+ 配色，深浅模式都用深底）
                            Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: const Color(0xFF17181F),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      14,
                                      10,
                                      14,
                                      0,
                                    ),
                                    child: Text(
                                      hlLang.toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.8,
                                        color: Color(0xFF6B7280),
                                      ),
                                    ),
                                  ),
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    padding: const EdgeInsets.fromLTRB(
                                      14,
                                      8,
                                      14,
                                      14,
                                    ),
                                    child: Text.rich(
                                      TextSpan(
                                        children: highlightCode(
                                          suggestedCode,
                                          hlLang,
                                          codeBase,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // 操作区：关闭（幽灵）+ 应用（品牌紫实心）
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(dCtx),
                            child: Text(
                              '关闭',
                              style: TextStyle(color: muted, fontSize: 14),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () => applySuggestion(dCtx),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primary,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22,
                                vertical: 11,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              '应用',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      }
    } catch (e) {
      setState(() {
        widget.block.outputContent = null;
        widget.block.outputType = null;
      });
      widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('小梦开小差了，请重试')));
      }
    }
  }

  void _showLatexAiMenu() {
    final promptCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF0FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_outlined,
                      size: 14,
                      color: _primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '小梦公式助手',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (widget.block.content.isNotEmpty)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.menu_book_outlined,
                      size: 17,
                      color: Color(0xFF555555),
                    ),
                  ),
                  title: const Text(
                    '解释这个公式',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  subtitle: const Text(
                    '用通俗语言解释公式含义',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _explainLatex();
                  },
                ),
              const Text(
                '用自然语言描述公式',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: promptCtrl,
                decoration: InputDecoration(
                  hintText: '如：泊松分布的概率质量函数',
                  hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
                  filled: true,
                  fillColor: Colors.grey[50],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _primary),
                  ),
                ),
                style: const TextStyle(fontSize: 13),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: ['正态分布', '贝叶斯定理', '泰勒展开', '矩阵行列式'].map((t) {
                  return GestureDetector(
                    onTap: () => promptCtrl.text = t,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        t,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF555555),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final desc = promptCtrl.text.trim();
                    if (desc.isEmpty) return;
                    Navigator.pop(ctx);
                    await _generateLatex(desc);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A1A),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    '生成 LaTeX',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _explainLatex() async {
    final formula = widget.block.content;
    final langHint = await aiLangHint();
    // 解释公式：结果展示在块下方 → 流式打字机逐字吐出（空白开始打字）
    setState(() {
      widget.block.outputContent = '';
      widget.block.outputType = 'text';
    });
    widget.onChanged();
    await _streamXmengToOutput('$langHint请用通俗语言解释以下LaTeX公式的数学含义：\n\n$formula');
  }

  Future<void> _generateLatex(String description) async {
    try {
      final res = await ref
          .read(apiClientProvider)
          .post(
            '/auth/xmeng/chat',
            data: {
              'messages': [
                {
                  'role': 'user',
                  'content':
                      '请把以下数学概念转换为LaTeX公式代码，只输出LaTeX代码本身，不要解释，不要markdown代码块：\n\n$description',
                },
              ],
            },
            options: Options(receiveTimeout: const Duration(seconds: 60)),
          );

      if (!res.success || !mounted) return;
      final latex = (res.data as Map?)?['message'] as String? ?? '';
      if (latex.isNotEmpty) {
        setState(() {
          widget.block.content = latex.trim();
          _textRevision++;
        });
        widget.onChanged();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('生成失败，请重试')));
      }
    }
  }

  Widget _buildHeadingBlock(AppLocalizations l10n) => _withEmptyBackspace(
    TextFormField(
      key: ValueKey('heading_${widget.block.id}_$_textRevision'),
      focusNode: widget.block.focusNode,
      initialValue: widget.block.content.isNotEmpty
          ? widget.block.content
          : null,
      decoration: const InputDecoration(
        filled: false,
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
      ),
      style: applyBlockTextFormat(
        TextStyle(
          fontSize: widget.block.headingLevel == 2
              ? 20
              : widget.block.headingLevel == 3
              ? 17
              : 15,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).textTheme.bodyLarge?.color,
        ),
        isBold: widget.block.isBold,
        isItalic: widget.block.isItalic,
        isUnderline: widget.block.isUnderline,
        isStrike: widget.block.isStrike,
        textColorValue: widget.block.textColorValue,
        highlightColorValue: widget.block.highlightColorValue,
        fontFamily: widget.block.fontFamily,
        fontSizeStep: widget.block.fontSizeStep,
        lineHeightStep: widget.block.lineHeightStep,
      ),
      maxLines: 1,
      onChanged: (v) {
        widget.block.content = v;
        widget.onChanged();
      },
      onTap: () => setState(() => _focused = true),
      onEditingComplete: () => setState(() => _focused = false),
    ),
  );

  void _copyContent() {
    Clipboard.setData(ClipboardData(text: widget.block.content));
    showAppToast(context, '已复制', ok: true);
  }

  // 代码块跟文字/公式块一样简化：去掉外框和顶栏。语言选择挪到底部工具栏
  // 最右侧的语言选择条（跟 aux 一致，见 CodeLangBar）；小梦/复制/运行三个
  // 操作按钮挪到卡片顶部 chrome 那排（跟其它 block 的移动/删除同一排，见
  // build 里 _isActive 分支）。这里只留代码输入框 + 运行输出。language 不在
  // 候选列表里（导入的代码块常给 text/jsx/ts 等）就按 python 兜底高亮；
  // 语言在工具栏被改后靠这里每次 build 同步一次 _codeCtrl.language（普通
  // 字段赋值、不 notify，放 build 里安全）重新上色
  Widget _buildCodeBlock(AppLocalizations l10n) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final codeTextColor = isDark
        ? const Color(0xFFE0E2F0)
        : const Color(0xFF1E293B);
    final hlLang = kCodeLanguages.contains(widget.block.language)
        ? widget.block.language!
        : 'python';
    if (_codeCtrl.language != hlLang) _codeCtrl.language = hlLang;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _withEmptyBackspace(
          TextFormField(
            controller: _codeCtrl,
            focusNode: widget.block.focusNode,
            // 代码块关掉智能标点/自动纠错——避免键盘把 ' " - 变成弯引号/破折号
            smartQuotesType: SmartQuotesType.disabled,
            smartDashesType: SmartDashesType.disabled,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              filled: false,
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: codeTextColor,
              height: 1.6,
            ),
            maxLines: null,
            onChanged: (v) {
              widget.block.content = v;
              widget.onChanged();
            },
          ),
        ),
        _buildOutput(),
      ],
    );
  }

  Widget _buildOutput() {
    final content = widget.block.outputContent;
    if (content == null) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      // key 只认 block.id（不含 content）——否则打字机流式每变一个字符都会
      // 换 key 触发整块重建，且过渡期两个滚动区共用同一个 controller 会崩。
      // 稳定 key 让内部 SingleChildScrollView 在内容更新时原地复用
      child: Container(
        key: ValueKey('output-${widget.block.id}'),
        width: double.infinity,
        constraints: const BoxConstraints(maxHeight: 300),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.03)
              : const Color(0xFFF8F9FC),
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor, width: 0.8),
          ),
        ),
        // html 输出自己就是一个内部可滚动的 WebView，外面不能再套一层
        // SingleChildScrollView——两层滚动区域叠在一起，手势会被内层
        // WebView 吃掉，外层永远收不到
        child: widget.block.outputType == 'html'
            ? SizedBox(
                height: 200,
                child: _renderOutput(content, widget.block.outputType),
              )
            : SingleChildScrollView(
                controller: _aiScrollCtrl,
                padding: const EdgeInsets.all(10),
                child: _renderOutput(content, widget.block.outputType),
              ),
      ),
    );
  }

  Widget _renderOutput(String content, String? type) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final errorColor = isDark
        ? const Color(0xFFFCA5A5)
        : const Color(0xFFDC2626);
    final infoColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);
    final okColor = isDark ? const Color(0xFF4EC9B0) : const Color(0xFF0F766E);
    switch (type) {
      case 'image':
        // matplotlib 图表：compiler.js 吐回来的是 base64 图片
        try {
          final base64Data = content.contains(',')
              ? content.split(',').last
              : content;
          return ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.memory(base64Decode(base64Data), fit: BoxFit.contain),
          );
        } catch (e) {
          return Text(
            '图表渲染失败：$e',
            style: TextStyle(color: errorColor, fontSize: 12),
          );
        }

      case 'html':
        // DataFrame 表格这类 HTML 输出——跟着主题走，浅色下用浅表格样式，
        // 不然一块深色表格糊在浅色输出区里很割裂
        final tableBg = isDark ? '#0a0f1a' : '#f8f9fc';
        final tableFg = isDark ? '#e2e8f0' : '#1e293b';
        final tableBorder = isDark ? '#1e293b' : '#e5e7eb';
        final thBg = isDark ? '#1e293b' : '#eef0f5';
        final thFg = isDark ? '#94a3b8' : '#64748b';
        return InAppWebView(
          initialData: InAppWebViewInitialData(
            data:
                '''
<html>
<head>
<style>
body{font-family:monospace;font-size:11px;margin:0;background:$tableBg;color:$tableFg}
table{border-collapse:collapse;width:100%}
th,td{border:1px solid $tableBorder;padding:4px 8px;text-align:left}
th{background:$thBg;color:$thFg}
</style>
</head>
<body>$content</body>
</html>
''',
          ),
        );

      case 'error':
        return Text(
          content,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: errorColor,
            height: 1.6,
          ),
        );

      case 'info':
        return Text(
          content,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: infoColor,
            height: 1.6,
          ),
        );

      default:
        return Text(
          content,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: okColor,
            height: 1.6,
          ),
        );
    }
  }

  Future<void> _runCode() async {
    final lang = (widget.block.language ?? 'python').toLowerCase();
    // 真正能执行/能被 onRunCode 优雅处理的语言：python/sql 走 Pyodide、
    // javascript 走 JS 引擎、html/markdown 由 onRunCode 直接回一条 info。
    // 其余语言（typescript/java/go/rust…）会被当成 Python 丢进 Pyodide 报
    // 语法错——这里提前拦下，给一条灰色友好提示（outputType='info'），不报错
    const runnable = {'python', 'sql', 'javascript', 'html', 'markdown'};
    if (!runnable.contains(lang)) {
      setState(() {
        widget.block.outputContent =
            '「$lang」代码目前仅高亮显示，暂不支持在这里执行。\n'
            '可运行的语言：Python / SQL / JavaScript。\n\n'
            '多语言运行即将上线 ✦';
        widget.block.outputType = 'info';
      });
      widget.onChanged();
      return;
    }

    setState(() => _running = true);
    List<Map<String, dynamic>> outputs;
    try {
      outputs = await widget.onRunCode(
        widget.block.id,
        widget.block.content,
        widget.block.language ?? 'python',
      );
    } finally {
      if (mounted) setState(() => _running = false);
    }
    if (!mounted) return;

    // 跟 Notebook 同一套过滤规则：调试信息/空文本不展示，取第一条真正
    // 有内容的输出
    String? foundContent;
    String? foundType;
    for (final out in outputs) {
      final type = out['type'] as String? ?? 'text';
      final content = out['content'] as String? ?? '';
      if (['viz-suggestion', 'missing-package', 'debug'].contains(type)) {
        continue;
      }
      if (type == 'text' && content.trim().isEmpty) continue;
      foundContent = content;
      foundType = type;
      break;
    }
    setState(() {
      widget.block.outputContent =
          foundContent ??
          AppLocalizations.of(context)!.runCompleteNoOutputMessage;
      widget.block.outputType = foundType ?? 'text';
    });
    widget.onChanged();
  }

  // 之前这个 block 无论明暗主题都固定用一套奶油黄配色——浅色主题下还好，
  // 深色主题下就会变成一块突兀的亮黄色，跟截图里反馈的"LaTeX 块色彩
  // 不一致"是同一个问题，这里跟着 Theme.of(context).brightness 走
  Widget _buildLatexBlock(AppLocalizations l10n) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 去掉整块填充底色（原来的琥珀/米色 pill），改成我们标准的"中性圆框"：
    // 透明底 + 一圈中性描边，公式本身用正文色渲染，更克制、更一线
    final border = Theme.of(context).dividerColor;
    final mathColor = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final hintColor = isDark ? Colors.white38 : Colors.black38;
    final inputTextColor = isDark ? Colors.white54 : Colors.grey;

    return Container(
      width: double.infinity,
      // 去掉这层描边圆框——它套在「Σ LaTeX」block 卡里是多余的一层 box。
      // 透明底直接融进卡片背景，只留下里面公式渲染那个视觉反馈
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          // 右上角「#编号」开关——toggle autoNumber。开=参与文档公式顺序编号、
          // 右侧显示 (n)；关=不编号。改完 onChanged 让父级重算所有公式编号
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(
                  () => widget.block.autoNumber = !widget.block.autoNumber,
                );
                widget.onChanged();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: widget.block.autoNumber
                      ? _primary.withValues(alpha: isDark ? 0.16 : 0.08)
                      : null,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: widget.block.autoNumber
                        ? _primary.withValues(alpha: 0.3)
                        : border,
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.tag,
                      size: 13,
                      color: widget.block.autoNumber ? _primary : hintColor,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '编号',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: widget.block.autoNumber ? _primary : hintColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          widget.block.content.isNotEmpty
              // Math.tex 不会自动换行/收缩——套横向滚动，宽公式左右滑动。传统
              // 论文样式：公式居中、右侧 (n) 编号（autoNumber 开且父级派了号才显示）
              ? Row(
                  children: [
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Math.tex(
                            preprocessLatex(
                              widget.block.content.replaceAll(r'$$', '').trim(),
                            ),
                            textStyle: TextStyle(fontSize: 16, color: mathColor),
                            onErrorFallback: (err) => Text(
                              widget.block.content,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (widget.equationNumber != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '(${widget.equationNumber})',
                        style: TextStyle(fontSize: 14, color: mathColor),
                      ),
                    ],
                  ],
                )
              : const SizedBox.shrink(),
          const SizedBox(height: 8),
          _withEmptyBackspace(
            TextFormField(
              key: ValueKey('latex_${widget.block.id}_$_textRevision'),
              // 接上 block 的 focusNode——聚焦公式输入框时才会触发
              // _handleFocusChange→onFocusGained，把这个 block 标成激活，
              // 外层才会浮出白色卡片（跟文字/标题块一致）
              focusNode: widget.block.focusNode,
              initialValue: widget.block.content.isNotEmpty
                  ? widget.block.content
                  : null,
              decoration: const InputDecoration(
                filled: false,
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: inputTextColor,
              ),
              onChanged: (v) {
                widget.block.content = v;
                setState(() {});
                widget.onChanged();
              },
            ),
          ),
          if (widget.block.outputContent != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.15)
                    : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: border),
              ),
              child: Text(
                widget.block.outputContent!,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: widget.block.outputType == 'info'
                      ? hintColor
                      : (isDark ? Colors.white70 : const Color(0xFF444444)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // 图片/音频/视频空态共用的"上传区"——主题感知的虚线圆角框 + 圆形图标
  // chip + 主/副提示，跟卡片背景融为一体（不再各自一块实底 pill / 黑框）。
  // badge 用来放视频块右上角的 PRO 角标
  Widget _buildUploadZone({
    required IconData icon,
    required String label,
    String? subHint,
    required VoidCallback onTap,
    Widget? badge,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final zoneBg = isDark
        ? Theme.of(context).cardColor
        : const Color(0xFFFAFAFA);
    final dashColor = isDark ? Colors.white24 : const Color(0xFFD1D1D6);
    final iconChipBg = isDark
        ? _primary.withValues(alpha: 0.18)
        : const Color(0xFFEEF0FF);
    final hintColor = isDark ? Colors.white54 : const Color(0xFF999999);
    final subHintColor = isDark ? Colors.white30 : const Color(0xFFC7C7CC);

    return GestureDetector(
      onTap: onTap,
      child: CustomPaint(
        painter: _DashedRRectPainter(color: dashColor, radius: 12),
        child: Container(
          height: 140,
          width: double.infinity,
          decoration: BoxDecoration(
            color: zoneBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: iconChipBg,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: _primary, size: 22),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: hintColor,
                      ),
                    ),
                    if (subHint != null) ...[
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          subHint,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10,
                            height: 1.5,
                            color: subHintColor,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (badge != null) Positioned(top: 8, right: 8, child: badge),
            ],
          ),
        ),
      ),
    );
  }

  // 视频块的 PRO 角标——空态上传区右上角 + 已上传预览右上角共用
  Widget _proBadge() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: _primary,
      borderRadius: BorderRadius.circular(5),
    ),
    child: const Text(
      'PRO',
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    ),
  );

  // Markdown 块（完整重写）：受控 controller（_mdController）+ 焦点驱动的
  // 编辑↔预览双态。预览态未聚焦且有内容时用 MarkdownBody 渲染（普通字体、
  // 拉开标题层级 + 引用/行内代码样式）；点一下进编辑态，收键盘/点别处失焦
  // 自动切回预览。_focused 完全由 _handleFocusChange 里的 focusNode.hasFocus
  // 驱动，不再用 initialValue+换key、不再在 onTap/onEditingComplete 里手改
  Widget _buildMarkdownBlock(AppLocalizations l10n) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? const Color(0xFFE0E2F0) : const Color(0xFF1A1A1A);
    final muted = isDark ? const Color(0xFF7A80A0) : const Color(0xFF888888);

    // 预览态
    if (!_focused && widget.block.content.trim().isNotEmpty) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          // 预览态下 TextField 没挂载，直接 requestFocus 会落空 → 先 setState
          // 切成编辑态把输入框挂上，再 postFrame 请求焦点（否则点了弹回预览）
          setState(() => _focused = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            widget.block.focusNode.requestFocus();
            _mdController?.selection = TextSelection.collapsed(
              offset: _mdController!.text.length,
            );
          });
        },
        child: SizedBox(
          width: double.infinity,
          child: MarkdownBody(
            data: widget.block.content,
            selectable: false,
            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                .copyWith(
                  h1: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                    color: ink,
                  ),
                  h2: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                    color: ink,
                  ),
                  h3: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                    color: ink,
                  ),
                  h4: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: ink,
                  ),
                  h5: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: ink,
                  ),
                  h6: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: muted,
                  ),
                  p: TextStyle(fontSize: 14, height: 1.7, color: ink),
                  strong: TextStyle(fontWeight: FontWeight.w600, color: ink),
                  em: TextStyle(fontStyle: FontStyle.italic, color: ink),
                  listBullet: TextStyle(fontSize: 14, color: muted),
                  blockquote: TextStyle(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    color: muted,
                  ),
                  code: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Color(0xFF6366F1),
                    backgroundColor: Color(0xFFEEF0FF),
                  ),
                ),
          ),
        ),
      );
    }

    // 编辑态——受控 controller，普通字体（非等宽）显示原始 Markdown 源码
    return _withEmptyBackspace(
      TextField(
        controller: _mdController,
        focusNode: widget.block.focusNode,
        maxLines: null,
        // 关掉智能标点——Markdown 语法里的 ' " - 别被键盘替换成弯引号/破折号
        autocorrect: false,
        enableSuggestions: false,
        smartQuotesType: SmartQuotesType.disabled,
        smartDashesType: SmartDashesType.disabled,
        style: TextStyle(fontSize: 14, height: 1.7, color: ink),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.zero,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          // 去掉 Markdown 块的占位提示（ghost text），空块保持完全干净
          hintText: null,
          hintStyle: TextStyle(fontSize: 14, height: 1.7, color: muted),
        ),
      ),
    );
  }

  Widget _buildImageBlock(AppLocalizations l10n) {
    if (widget.block.imageUrl != null) {
      return Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 80, maxHeight: 400),
              child: Image.network(
                widget.block.imageUrl!,
                fit: BoxFit.cover,
                width: double.infinity,
              ),
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            initialValue: widget.block.caption,
            decoration: InputDecoration(
              filled: false,
              hintText: l10n.imageCaptionHint,
              hintStyle: const TextStyle(
                color: Color(0xFFC7C7CC),
                fontSize: 12,
              ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            style: const TextStyle(fontSize: 12, color: Colors.grey),
            onChanged: (v) {
              widget.block.caption = v;
              widget.onChanged();
            },
          ),
        ],
      );
    }
    // 空态跟音频/视频块共用同一套"虚线上传区"（见 _buildUploadZone）
    return _buildUploadZone(
      icon: Icons.add_photo_alternate_outlined,
      label: l10n.tapToUploadLabel,
      subHint: l10n.imageSizeHint,
      onTap: _pickImage,
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: file.name,
          contentType: DioMediaType('image', 'jpeg'),
        ),
      });
      final res = await ref
          .read(apiClientProvider)
          .post('/auth/files/upload', data: formData);
      if (!res.success || res.data == null) return;
      final url = (res.data as Map)['url'] as String?;
      final uploadedId = (res.data as Map)['id'] as String?;
      if (uploadedId != null) widget.onFileUploaded?.call(uploadedId);
      if (url != null && mounted) {
        setState(() => widget.block.imageUrl = url);
        widget.onChanged();
      }
    } catch (e) {
      debugPrint('[image] 上传失败: $e');
    }
  }

  Widget _buildFileBlock(AppLocalizations l10n) {
    // 不做视觉加锁：块照常渲染，点上传时才在 _pickFile 里 requirePro
    if (widget.block.fileName != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFBFDBFE)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.insert_drive_file,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.block.fileName!,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1D4ED8),
                    ),
                  ),
                  if (widget.block.fileSize != null)
                    Text(
                      _formatSize(widget.block.fileSize!),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF60A5FA),
                      ),
                    ),
                ],
              ),
            ),
            Tooltip(
              message: l10n.downloadFileTooltip,
              child: const Icon(
                Icons.download_outlined,
                color: Color(0xFF2563EB),
                size: 18,
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: _pickFile,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F7),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE5E5EA)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.upload_file_outlined,
              color: Color(0xFFC7C7CC),
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              l10n.uploadFileLabel,
              style: const TextStyle(fontSize: 13, color: Color(0xFFC7C7CC)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFile() async {
    // 文件附件是 Pro 权益——点了才校验，非 Pro 弹会员 Sheet
    if (!requirePro(context, ref, feature: '文件附件')) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'csv',
        'xlsx',
        'xls',
        'json',
        'xml',
        'pdf',
        'txt',
        'py',
        'ipynb',
      ],
    );
    if (result == null) return;
    final file = result.files.first;
    final bytes = file.bytes ?? await File(file.path!).readAsBytes();

    final maxSize = widget.membership == 'pro_max'
        ? 50 * 1024 * 1024
        : 5 * 1024 * 1024;
    if (bytes.length > maxSize) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.fileSizeExceedsLimit(
                widget.membership == 'pro_max' ? '50MB' : '5MB',
              ),
            ),
          ),
        );
      }
      return;
    }

    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: file.name,
          contentType: DioMediaType('application', 'octet-stream'),
        ),
      });
      final res = await ref
          .read(apiClientProvider)
          .post('/auth/files/upload', data: formData);
      if (!res.success || res.data == null) return;
      final url = (res.data as Map)['url'] as String?;
      final uploadedId = (res.data as Map)['id'] as String?;
      if (uploadedId != null) widget.onFileUploaded?.call(uploadedId);
      if (url != null && mounted) {
        setState(() {
          widget.block.content = url;
          widget.block.fileName = file.name;
          widget.block.fileSize = bytes.length;
          widget.block.fileType = file.extension;
        });
        widget.onChanged();
      }
    } catch (e) {
      debugPrint('[file] 上传失败: $e');
    }
  }

  Widget _buildAudioBlock(AppLocalizations l10n) {
    // 不做视觉加锁：块照常渲染，点上传时才在 _pickAudio 里 requirePro

    if (widget.block.fileName != null) {
      // 已上传的音频跟其它内容块一样中性化——去掉紫色实底 pill，改成透明底
      // + 一圈 dividerColor 细描边，文件名走正文色、副行走灰，只有播放按钮
      // 保留品牌紫圆点（一眼认出可播放）
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: _primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.block.fileName!,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  Text(
                    l10n.tapToPlayLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF999999),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 空态跟图片/视频块共用同一套"虚线上传区"，不再是一块紫色实底 pill
    return _buildUploadZone(
      icon: Icons.audio_file_outlined,
      label: l10n.uploadAudioLabel,
      onTap: _pickAudio,
    );
  }

  Future<void> _pickAudio() async {
    // 音频块是 Pro 权益——点了才校验，非 Pro 弹会员 Sheet
    if (!requirePro(context, ref, feature: '音频块')) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'm4a', 'aac', 'flac'],
    );
    if (result == null) return;
    final file = result.files.first;
    final bytes = file.bytes ?? await File(file.path!).readAsBytes();

    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: file.name,
          contentType: DioMediaType('audio', 'mpeg'),
        ),
      });
      final res = await ref
          .read(apiClientProvider)
          .post('/auth/files/upload', data: formData);
      if (!res.success || res.data == null) return;
      final url = (res.data as Map)['url'] as String?;
      final uploadedId = (res.data as Map)['id'] as String?;
      if (uploadedId != null) widget.onFileUploaded?.call(uploadedId);
      if (url != null && mounted) {
        setState(() {
          widget.block.content = url;
          widget.block.fileName = file.name;
          widget.block.fileSize = bytes.length;
        });
        widget.onChanged();
      }
    } catch (e) {
      debugPrint('[audio] 上传失败: $e');
    }
  }

  Widget _buildVideoBlock(AppLocalizations l10n) {
    // 不做视觉加锁：块照常渲染，点上传时才在 _pickVideo 里 requirePro。
    // 已上传 → 深色预览框（视频缩略图本身偏暗，符合直觉）；空态 → 跟图片/
    // 音频一样的虚线上传区（右上角挂 PRO 角标），不再是一整块黑底 box
    if (widget.block.content.isNotEmpty) {
      return Container(
        height: 140,
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Stack(
          children: [
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(
                    Icons.play_circle_outline,
                    color: Colors.white,
                    size: 44,
                  ),
                  Positioned(
                    bottom: -30,
                    child: Text(
                      widget.block.fileName ?? 'video.mp4',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(top: 8, right: 8, child: _proBadge()),
          ],
        ),
      );
    }
    return _buildUploadZone(
      icon: Icons.videocam_outlined,
      label: l10n.uploadVideoFromGallery,
      subHint: l10n.videoSizeHint,
      onTap: _pickVideo,
      badge: _proBadge(),
    );
  }

  Future<void> _pickVideo() async {
    // 视频块是 Pro 权益——非 Pro 弹会员 Sheet
    if (!requirePro(context, ref, feature: '视频块')) return;
    final picker = ImagePicker();
    final file = await picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 10),
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;

    // Pro 视频上限 50MB、Pro Max 100MB。Pro 用户超过 50MB → 弹 Pro Max
    // 升级 Sheet（不是干巴巴的报错）；Pro Max 超过 100MB 才是硬上限提示
    final isMax = widget.membership == 'pro_max';
    if (!isMax && bytes.length > 50 * 1024 * 1024) {
      showProUpgradeSheet(context, feature: '上传 50MB 以上视频', proMax: true);
      return;
    }
    if (isMax && bytes.length > 100 * 1024 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.videoSizeExceedsLimit('100MB'),
          ),
        ),
      );
      return;
    }

    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: file.name,
          contentType: DioMediaType('video', 'mp4'),
        ),
      });
      final res = await ref
          .read(apiClientProvider)
          .post('/auth/files/upload', data: formData);
      if (!res.success || res.data == null) return;
      final url = (res.data as Map)['url'] as String?;
      final uploadedId = (res.data as Map)['id'] as String?;
      if (uploadedId != null) widget.onFileUploaded?.call(uploadedId);
      if (url != null && mounted) {
        setState(() {
          widget.block.content = url;
          widget.block.fileName = file.name;
          widget.block.fileSize = bytes.length;
        });
        widget.onChanged();
      }
    } catch (e) {
      debugPrint('[video] 上传失败: $e');
    }
  }

  Widget _buildLinkBlock(AppLocalizations l10n) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E5EA)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: Color(0xFFEEF0FF),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(7),
                bottomLeft: Radius.circular(7),
              ),
            ),
            child: const Icon(Icons.link, color: _primary, size: 20),
          ),
          Expanded(
            child: _withEmptyBackspace(
              TextFormField(
                initialValue: widget.block.content.isNotEmpty
                    ? widget.block.content
                    : null,
                decoration: const InputDecoration(
                  filled: false,
                  hintText: 'https://...',
                  hintStyle: TextStyle(color: Color(0xFFC7C7CC), fontSize: 13),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 10),
                ),
                style: const TextStyle(fontSize: 13, color: Color(0xFF1C1C1E)),
                keyboardType: TextInputType.url,
                onChanged: (v) {
                  widget.block.content = v;
                  widget.block.linkUrl = v;
                  widget.onChanged();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 简化成单一"引用"样式——左紫线+米白底+斜体，不再有 tip/warning/info
  // 三态切换。variant 字段还留着（对应已发布内容里可能存在的旧数据），
  // 编辑器这边统一按新样式显示，不再往 variant 写除 info 以外的值
  Widget _buildCalloutBlock(AppLocalizations l10n) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark
        ? (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white)
        : const Color(0xFF1A1A1A);

    // 去掉灰色填充底（pill），只留左侧紫色引用线——干净的引用样式
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.transparent,
        border: Border(left: BorderSide(color: _primary, width: 3)),
      ),
      child: _withEmptyBackspace(
        TextFormField(
          key: ValueKey('callout_${widget.block.id}_$_textRevision'),
          focusNode: widget.block.focusNode,
          initialValue: widget.block.content.isNotEmpty
              ? widget.block.content
              : null,
          decoration: const InputDecoration(
            filled: false,
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
          style: TextStyle(
            fontSize: 14,
            fontStyle: FontStyle.italic,
            color: textColor,
            height: 1.6,
          ),
          maxLines: null,
          onChanged: (v) {
            widget.block.content = v;
            widget.onChanged();
          },
        ),
      ),
    );
  }
}

// Flutter 没有内置的虚线边框，图片 block 空态的"上传区"虚线描边靠这个
// 手写 CustomPainter：沿圆角矩形的路径按固定长度切成一段段短划线画
class _DashedRRectPainter extends CustomPainter {
  final Color color;
  final double radius;
  const _DashedRRectPainter({required this.color, required this.radius});

  static const _dashWidth = 5.0;
  static const _dashGap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + _dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + _dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
