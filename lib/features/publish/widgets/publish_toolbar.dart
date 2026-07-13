import 'package:flutter/material.dart';

import '../../../core/utils/membership_utils.dart';
import '../../../core/widgets/pro_gate.dart';
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
                  decoration: isDarkMode
                      ? premiumPillDecoration(radius: 10, muted: saving)
                      : BoxDecoration(
                          color: _ink,
                          borderRadius: BorderRadius.circular(10),
                        ),
                  child: saving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          l10n.publish,
                          style: const TextStyle(
                            color: Colors.white,
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
  BlockType.latex,
  BlockType.callout,
  BlockType.image,
  BlockType.video,
  BlockType.audio,
  BlockType.link,
];

class PublishBottomToolbar extends StatelessWidget {
  final AppLocalizations l10n;
  final bool isDarkMode;
  final List<EditorBlock> blocks;
  final BlockType activeToolbarType;
  final void Function(BlockType type) onAddBlock;
  final VoidCallback onImport;

  const PublishBottomToolbar({
    super.key,
    required this.l10n,
    required this.isDarkMode,
    required this.blocks,
    required this.activeToolbarType,
    required this.onAddBlock,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    final (words, minutes) = computeBlockStats(blocks);
    return Container(
      // 跟顶栏一样透明，不再单独铺卡片色，工具栏跟正文视觉上是同一块背景
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  ..._toolbarTypes.map((type) {
                    final button = _toolbarButton(
                      icon: blockTypeIcon(type),
                      tooltip: blockTypeLabel(l10n, type),
                      selected: activeToolbarType == type,
                      isDarkMode: isDarkMode,
                      onTap: () => onAddBlock(type),
                    );
                    // 音频/视频 Block 是 Pro 权益（跟会员页
                    // subscription_screen.dart 列出的权益一致），文字/
                    // 代码/公式/引用/图片/链接这些免费档本来就能用，不用包
                    if (type == BlockType.audio || type == BlockType.video) {
                      return ProGate(
                        check: MembershipUtils.canPublishMedia,
                        featureName: '音视频发布',
                        child: button,
                      );
                    }
                    return button;
                  }),
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
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                l10n.wordBlocksReadTimeLabel(words, blocks.length, minutes),
                style: TextStyle(
                  fontSize: 11,
                  color: isDarkMode
                      ? const Color(0xFF8E8E93)
                      : const Color(0xFFCCCCCC),
                ),
              ),
            ),
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
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
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
