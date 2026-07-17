import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/utils/premium_button.dart';
import '../models/block_model.dart';
import 'block_picker_sheet.dart';

const _ink = Color(0xFF1A1A1A);
const _muted = Color(0xFF999999);

class PublishTopBar extends StatelessWidget {
  final AppLocalizations l10n;
  final bool isDarkMode;
  final TextEditingController titleController;
  final bool saving;
  final VoidCallback onTitleChanged;
  final VoidCallback onSaveDraft;
  final VoidCallback onPublish;
  // 关闭（X）走 PublishScreen 的退出处理——退出前询问保存/清理未保存的
  // COS 文件，不再直接 context.pop()
  final VoidCallback onClose;

  const PublishTopBar({
    super.key,
    required this.l10n,
    required this.isDarkMode,
    required this.titleController,
    required this.saving,
    required this.onTitleChanged,
    required this.onSaveDraft,
    required this.onPublish,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      // 透明，不再单独铺一层卡片色——跟正文共享同一块 Scaffold 背景，
      // 避免顶栏跟下面的内容之间出现一条颜色不一致的分割线
      color: Colors.transparent,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              GestureDetector(
                onTap: onClose,
                child: const Icon(
                  Icons.close,
                  size: 22,
                  color: Color(0xFF888888),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: titleController,
                  decoration: InputDecoration(
                    filled: false,
                    hintText: l10n.publishTitleHint,
                    hintStyle: const TextStyle(color: Color(0xFFC7C7CC)),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                  onChanged: (_) => onTitleChanged(),
                ),
              ),
              Builder(
                builder: (ctx) => GestureDetector(
                  onTap: () => Scaffold.of(ctx).openEndDrawer(),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      Icons.visibility_outlined,
                      size: 20,
                      color: Color(0xFF888888),
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: saving ? null : onSaveDraft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    l10n.saveDraftAction,
                    style: const TextStyle(fontSize: 13, color: _muted),
                  ),
                ),
              ),
              PressableScale(
                onTap: saving ? null : onPublish,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 7,
                  ),
                  // 深色模式下 _ink（#1A1A1A）跟 Scaffold 背景（#1C1C1E）
                  // 几乎是同一个颜色，纯黑底会把发布按钮"吃掉"；改用带
                  // 渐变/高光/投影的主题色胶囊按钮，浅色模式沿用原来的
                  // 纯黑扁平按钮（跟参考截图一致，不是紫色，不用这套）
                  // 深色沿用主题渐变胶囊；浅色去掉纯黑填充改用描边，内容色
                  // 随之从白改成黑，才在透明底上看得见
                  decoration: isDarkMode
                      ? premiumPillDecoration(radius: 10, muted: saving)
                      : BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFFDDDDDD),
                            width: 0.5,
                          ),
                        ),
                  child: saving
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            color: isDarkMode ? Colors.white : _ink,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          l10n.publish,
                          style: TextStyle(
                            color: isDarkMode ? Colors.white : _ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
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
}

// 底部横排工具栏快捷图标。heading 补回来了——模型/渲染其实一直都支持
// （block_model.dart 的 headingLevel、block_card.dart 的
// _buildHeadingBlock 都在），之前只是没有入口能加。file 类型模型也还在
// （已发布内容里可能用到，阅读端要继续认得），但这次任务没要求加，先
// 不动
const _toolbarTypes = [
  BlockType.text,
  BlockType.heading,
  BlockType.code,
  // Markdown 块紧挨代码块——模型/渲染（block_model、block_card）和图标/
  // 文案（block_picker_sheet 的 blockTypeIcon/blockTypeLabel → Icons.notes /
  // "Markdown"）本来就都齐了，之前只是工具栏没给入口
  BlockType.markdown,
  BlockType.latex,
  BlockType.callout,
  BlockType.image,
  BlockType.video,
  BlockType.audio,
  BlockType.link,
  BlockType.reference,
];

class PublishBottomToolbar extends StatelessWidget {
  final AppLocalizations l10n;
  final bool isDarkMode;
  final List<EditorBlock> blocks;
  final BlockType activeToolbarType;
  final void Function(BlockType type) onAddBlock;
  final VoidCallback onImport;
  // 类型按钮（文字/小标题…）现在只负责新建对应 block，不再兼管辅助栏。
  // 辅助栏（字体/颜色）改由工具栏最右侧一个独立的「Aa」图标控制：只有
  // 当前聚焦的是文字/标题 block 时才显示（showFormatToggle），点它切换
  // 辅助栏开关，formatBarExpanded 用来给这个图标上高亮态
  final bool showFormatToggle;
  final bool formatBarExpanded;
  final VoidCallback onToggleFormatBar;
  // 跟 aux 完全同一套路的语言选择器开关——只在聚焦的是代码 block 时才
  // 显示（showLangToggle），钉在最右侧同一个位置（跟 aux 互斥，一次只会
  // 有一个亮），点它切换语言选择条 CodeLangBar，langBarExpanded 给图标高亮
  final bool showLangToggle;
  final bool langBarExpanded;
  final VoidCallback onToggleLangBar;

  const PublishBottomToolbar({
    super.key,
    required this.l10n,
    required this.isDarkMode,
    required this.blocks,
    required this.activeToolbarType,
    required this.onAddBlock,
    required this.onImport,
    required this.showFormatToggle,
    required this.formatBarExpanded,
    required this.onToggleFormatBar,
    required this.showLangToggle,
    required this.langBarExpanded,
    required this.onToggleLangBar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      // 跟顶栏一样透明，不再单独铺卡片色，工具栏跟正文视觉上是同一块背景
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              // 收窄一点（原 56）——减少 block 图标行上下的空白，跟上面格式
              // 工具栏靠得更近
              height: 48,
              child: Row(
                children: [
                  Expanded(
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      children: [
                        // 类型按钮只负责新建对应 block——音频/视频虽是 Pro
                        // 权益但按设计原则不做视觉加锁，点了在 onAddBlock 里
                        // （publish_screen._addBlock）才校验，非 Pro 弹会员 Sheet
                        ..._toolbarTypes.map(
                          (type) => _toolbarButton(
                            icon: blockTypeIcon(type),
                            tooltip: blockTypeLabel(l10n, type),
                            selected: activeToolbarType == type,
                            isDarkMode: isDarkMode,
                            onTap: () => onAddBlock(type),
                          ),
                        ),
                        _toolbarButton(
                          icon: Icons.download_outlined,
                          tooltip: l10n.importFromLinkAction,
                          selected: false,
                          isDarkMode: isDarkMode,
                          onTap: onImport,
                        ),
                      ],
                    ),
                  ),
                  // 右侧独立开关——钉在最右、不随类型列表滚动，只在聚焦
                  // 对应 block 时出现（跟 aux 一致）。文字/标题 → 字体/颜色
                  // 辅助栏开关；代码 → 语言选择条开关。两者互斥，一次只有
                  // 一个亮。左侧一条细分隔线，跟"加内容块"那组分开
                  if (showFormatToggle || showLangToggle)
                    Container(
                      width: 0.5,
                      height: 24,
                      color: isDarkMode
                          ? const Color(0xFF3A3A3C)
                          : const Color(0xFFE5E5EA),
                    ),
                  if (showFormatToggle)
                    _toolbarButton(
                      icon: Icons.text_format,
                      tooltip: l10n.fontPickerTitle,
                      selected: formatBarExpanded,
                      isDarkMode: isDarkMode,
                      onTap: onToggleFormatBar,
                    ),
                  if (showLangToggle)
                    _toolbarButton(
                      icon: Icons.code,
                      tooltip: l10n.blockTypeCode,
                      selected: langBarExpanded,
                      isDarkMode: isDarkMode,
                      onTap: onToggleLangBar,
                    ),
                ],
              ),
            ),
            // 底部字数/块数/阅读时长那行去掉——腾出高度给上面的内容块，
            // 这些统计只在预览抽屉里保留
          ],
        ),
      ),
    );
  }

  Widget _toolbarButton({
    required IconData icon,
    required String tooltip,
    required bool selected,
    required bool isDarkMode,
    required VoidCallback onTap,
  }) {
    final highlightBg = isDarkMode
        ? const Color(0xFF3A3A3C)
        : const Color(0xFFF0F0F0);
    return Padding(
      // 竖向 5（原 9）——图标行更紧凑，跟上方格式工具栏的间距缩小
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            highlightColor: highlightBg,
            splashColor: Colors.transparent,
            onTap: onTap,
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? highlightBg : null,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 20,
                color: isDarkMode
                    ? const Color(0xFFE5E5EA)
                    : const Color(0xFF555555),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
