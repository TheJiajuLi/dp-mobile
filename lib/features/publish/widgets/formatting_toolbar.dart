import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/utils/code_highlight.dart';
import '../models/block_model.dart';
import 'block_picker_sheet.dart';

const _primary = AppColors.primary;

const _textColors = [
  null, // 默认——跟随主题正文色，不是字面意义上的"黑"
  AppColors.primary,
  Color(0xFF2563EB),
  Color(0xFF16A34A),
  Color(0xFFEF4444),
  Color(0xFFD97706),
  Color(0xFF888888),
];

const _highlightColors = [
  null, // 不高亮
  Color(0xFFFEF9C3),
  Color(0xFFDBEAFE),
  Color(0xFFDCFCE7),
  Color(0xFFFEE2E2),
  Color(0xFFEEF0FF),
];

// 整块 block 一起套用格式，不是逐字符选区——见 block_model.dart 里
// isBold 等字段的注释。只在 text/heading block 获得焦点时才有意义，
// 焦点不在这两种 block 上（或者压根没有 block）时收起来不占地方
class BlockFormattingToolbar extends StatelessWidget {
  final AppLocalizations l10n;
  final bool isDarkMode;
  final EditorBlock? block;
  final VoidCallback onChanged;
  final VoidCallback onShowFontSheet;
  // EditorBlock.type 是 final 的，没法直接改——text↔heading 互转要在
  // PublishScreen 那层把整个 block 换成新实例（同 id、同 content，
  // FocusNode 也要跟着重建），传 null 表示"转回普通文字段落"
  final void Function(int? headingLevel) onConvertHeading;
  // 已经是当前标题级别时再点一次那个 H 按钮——收起辅助栏（字体/颜色
  // 那行），跟底部"Tt"按钮再点一次收起的行为一致。由父级 PublishScreen
  // 持有 _formatBarExpanded，这里只回调通知它收起
  final VoidCallback onCollapse;
  // 底部工具栏"Tt"按钮点一下收起、再点一下展开——由父级 PublishScreen
  // 持有这个开关状态，这里只负责按它显示/隐藏，不自己管理状态
  final bool expanded;

  const BlockFormattingToolbar({
    super.key,
    required this.l10n,
    required this.isDarkMode,
    required this.block,
    required this.onChanged,
    required this.onShowFontSheet,
    required this.onConvertHeading,
    required this.onCollapse,
    this.expanded = true,
  });

  bool get _applicable =>
      block != null &&
      (block!.type == BlockType.text || block!.type == BlockType.heading);

  @override
  Widget build(BuildContext context) {
    if (!_applicable || !expanded) return const SizedBox.shrink();
    final b = block!;
    final dividerColor = isDarkMode
        ? const Color(0xFF1E1E3A)
        : const Color(0xFFF5F5F5);

    return Container(
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(height: 0.5, thickness: 0.5, color: dividerColor),
          // 字体样式 + 文字/高亮色合并成一行横向滚动——原来是上下两行 +
          // 中间分割线，太占竖向空间；合成一行后高度砍掉约一半
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            // 底部只留 2（原来 6）——缩小跟下面 block 插入工具栏之间的间距
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
            child: Row(
              children: [
                _fmtBtn(
                  context,
                  'A',
                  fontSize: 12,
                  onTap: () => _setFontSizeStep(b, b.fontSizeStep - 1),
                ),
                _fmtBtn(
                  context,
                  'A',
                  fontSize: 17,
                  onTap: () => _setFontSizeStep(b, b.fontSizeStep + 1),
                ),
                _fmtDivider(dividerColor),
                _fmtBtn(
                  context,
                  'B',
                  bold: true,
                  active: b.isBold,
                  onTap: () => _toggle(() => b.isBold = !b.isBold),
                ),
                _fmtBtn(
                  context,
                  'I',
                  italic: true,
                  active: b.isItalic,
                  onTap: () => _toggle(() => b.isItalic = !b.isItalic),
                ),
                _fmtBtn(
                  context,
                  'U',
                  underline: true,
                  active: b.isUnderline,
                  onTap: () => _toggle(() => b.isUnderline = !b.isUnderline),
                ),
                _fmtBtn(
                  context,
                  'S',
                  strike: true,
                  active: b.isStrike,
                  onTap: () => _toggle(() => b.isStrike = !b.isStrike),
                ),
                _fmtDivider(dividerColor),
                _fmtBtn(
                  context,
                  'H1',
                  active: b.type == BlockType.heading && b.headingLevel == 2,
                  onTap: () => _toggleHeading(b, 2),
                ),
                _fmtBtn(
                  context,
                  'H2',
                  active: b.type == BlockType.heading && b.headingLevel == 3,
                  onTap: () => _toggleHeading(b, 3),
                ),
                _fmtBtn(
                  context,
                  'H3',
                  active: b.type == BlockType.heading && b.headingLevel == 4,
                  onTap: () => _toggleHeading(b, 4),
                ),
                _fmtDivider(dividerColor),
                GestureDetector(
                  onTap: onShowFontSheet,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: isDarkMode
                            ? Colors.white.withValues(alpha: 0.1)
                            : const Color(0xFFEBEBEB),
                        width: 0.5,
                      ),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Row(
                      children: [
                        Text(
                          'Tt',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDarkMode
                                ? const Color(0xFFE0E2F0)
                                : const Color(0xFF555555),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.keyboard_arrow_down,
                          size: 14,
                          color: Colors.grey[400],
                        ),
                      ],
                    ),
                  ),
                ),
                _fmtDivider(dividerColor),
                Text(
                  l10n.formattingTextColorLabel,
                  style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                ),
                const SizedBox(width: 8),
                ..._textColors.map(
                  (c) => _colorDot(
                    color: c ?? (isDarkMode ? Colors.white : Colors.black),
                    selected: b.textColorValue == c?.toARGB32(),
                    onTap: () =>
                        _toggle(() => b.textColorValue = c?.toARGB32()),
                  ),
                ),
                const SizedBox(width: 10),
                Container(width: 0.5, height: 16, color: dividerColor),
                const SizedBox(width: 10),
                Text(
                  l10n.formattingHighlightLabel,
                  style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                ),
                const SizedBox(width: 8),
                ..._highlightColors.map(
                  (c) => _colorDot(
                    color: c ?? Colors.transparent,
                    selected: b.highlightColorValue == c?.toARGB32(),
                    hasBorder: true,
                    showSlash: c == null,
                    onTap: () =>
                        _toggle(() => b.highlightColorValue = c?.toARGB32()),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _toggle(VoidCallback mutate) {
    mutate();
    onChanged();
  }

  void _setFontSizeStep(EditorBlock b, int step) {
    _toggle(() => b.fontSizeStep = step.clamp(0, 3));
  }

  // 点一个还不是当前级别的 H → 切到那个标题级别；再点一次已经是当前
  // 级别的同一个 H → 收起辅助栏（字体/颜色），跟底部"Tt"按钮再点收起
  // 一致（不再转回普通段落）
  void _toggleHeading(EditorBlock b, int level) {
    final alreadyThisLevel =
        b.type == BlockType.heading && b.headingLevel == level;
    if (alreadyThisLevel) {
      onCollapse();
      return;
    }
    onConvertHeading(level);
  }

  Widget _fmtDivider(Color color) => Container(
    width: 0.5,
    height: 20,
    margin: const EdgeInsets.symmetric(horizontal: 6),
    color: color,
  );

  Widget _fmtBtn(
    BuildContext context,
    String label, {
    double fontSize = 14,
    bool bold = false,
    bool italic = false,
    bool underline = false,
    bool strike = false,
    bool active = false,
    required VoidCallback onTap,
  }) {
    final color = active
        ? _primary
        : (isDarkMode ? const Color(0xFFE0E2F0) : const Color(0xFF555555));
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        margin: const EdgeInsets.only(right: 2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active
              ? _primary.withValues(alpha: isDarkMode ? 0.18 : 0.08)
              : null,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            fontStyle: italic ? FontStyle.italic : FontStyle.normal,
            decoration: underline
                ? TextDecoration.underline
                : strike
                ? TextDecoration.lineThrough
                : TextDecoration.none,
            color: color,
          ),
        ),
      ),
    );
  }

  Widget _colorDot({
    required Color color,
    required bool selected,
    bool hasBorder = false,
    bool showSlash = false,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 22,
        height: 22,
        margin: const EdgeInsets.only(right: 6),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? _primary
                : hasBorder
                ? const Color(0xFFEEEEEE)
                : Colors.transparent,
            width: selected ? 2 : 0.5,
          ),
        ),
        child: showSlash
            ? const Icon(Icons.close, size: 12, color: Color(0xFFBBBBBB))
            : null,
      ),
    );
  }
}

// 代码块的语言选择条——跟 BlockFormattingToolbar（字体/颜色那条 aux）一个
// 套路：只在聚焦的是代码块且 expanded 时才浮出来，横向滚动的语言 pill，
// 选中态品牌紫底白字。选语言直接改 block.language，重新高亮交给 BlockCard
// 每次 build 同步 _codeCtrl.language（见 block_card._buildCodeBlock）
class CodeLangBar extends StatefulWidget {
  final bool isDarkMode;
  final EditorBlock? block;
  final bool expanded;
  final VoidCallback onChanged;

  const CodeLangBar({
    super.key,
    required this.isDarkMode,
    required this.block,
    required this.expanded,
    required this.onChanged,
  });

  bool get _applicable => block != null && block!.type == BlockType.code;

  @override
  State<CodeLangBar> createState() => _CodeLangBarState();
}

class _CodeLangBarState extends State<CodeLangBar> {
  final _scrollCtrl = ScrollController();
  bool _scrolledOnce = false;

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget._applicable || !widget.expanded) return const SizedBox.shrink();
    final b = widget.block!;
    final isDark = widget.isDarkMode;
    final dividerColor = isDark
        ? const Color(0xFF1E1E3A)
        : const Color(0xFFF5F5F5);
    final pillBg = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : const Color(0xFFF0F0F3);
    final pillFg = isDark ? const Color(0xFFB0B0B8) : const Color(0xFF6B6B72);
    final current = kCodeLanguages.contains(b.language) ? b.language! : 'python';
    // 首帧把选中的 pill 滚进可视区（选的语言可能排在很后面），只做一次
    if (!_scrolledOnce) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollCtrl.hasClients) return;
        _scrolledOnce = true;
        final idx = kCodeLanguages.indexOf(current);
        if (idx <= 0) return;
        _scrollCtrl.jumpTo(
          (idx * 62.0).clamp(0.0, _scrollCtrl.position.maxScrollExtent),
        );
      });
    }
    return Container(
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(height: 0.5, thickness: 0.5, color: dividerColor),
          SizedBox(
            height: 38,
            child: ListView.separated(
              controller: _scrollCtrl,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              itemCount: kCodeLanguages.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (ctx, i) {
                final lang = kCodeLanguages[i];
                final selected = lang == current;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: selected
                      ? null
                      : () {
                          b.language = lang;
                          widget.onChanged();
                        },
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: selected ? _primary : pillBg,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      capLang(lang),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: selected ? Colors.white : pillFg,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

void showFontSheet(
  BuildContext context, {
  required AppLocalizations l10n,
  required bool isDarkMode,
  required EditorBlock block,
  required VoidCallback onChanged,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) {
        final dark = Theme.of(ctx).brightness == Brightness.dark;
        Widget fontOption(String name, String preview, String? family) {
          final selected = (block.fontFamily ?? '') == (family ?? '');
          return InkWell(
            onTap: () => setSheetState(() {
              block.fontFamily = family;
              onChanged();
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(ctx).textTheme.bodyLarge?.color,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          preview,
                          style: TextStyle(
                            fontSize: 13,
                            fontFamily: family,
                            color: Colors.grey[400],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selected)
                    const Icon(Icons.check, size: 18, color: _primary),
                ],
              ),
            ),
          );
        }

        Widget stepRow(
          List<String> labels,
          int current,
          void Function(int) onPick,
        ) {
          return Row(
            children: labels.asMap().entries.map((e) {
              final selected = current == e.key;
              return GestureDetector(
                onTap: () => setSheetState(() {
                  onPick(e.key);
                  onChanged();
                }),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFFEEF0FF)
                        : (dark
                              ? const Color(0xFF111118)
                              : const Color(0xFFF5F5F5)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    e.value,
                    style: TextStyle(
                      fontSize: 12,
                      color: selected ? _primary : Colors.grey[500],
                      fontWeight: selected
                          ? FontWeight.w500
                          : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          );
        }

        return Container(
          padding: const EdgeInsets.fromLTRB(0, 14, 0, 40),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF17171F) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 3,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.fontPickerTitle,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(ctx).textTheme.bodyLarge?.color,
                    ),
                  ),
                ),
              ),
              fontOption(l10n.fontSystemLabel, 'The quick brown fox', null),
              fontOption(l10n.fontSerifLabel, 'The quick brown fox', 'serif'),
              fontOption(
                l10n.fontMonospaceLabel,
                'The quick brown fox',
                'monospace',
              ),
              Divider(
                height: 1,
                color: dark ? const Color(0xFF1E1E3A) : const Color(0xFFF5F5F5),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.fontSizeLabel,
                      style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                    ),
                    const SizedBox(height: 10),
                    stepRow(
                      [
                        l10n.fontSizeSmall,
                        l10n.fontSizeMedium,
                        l10n.fontSizeLarge,
                        l10n.fontSizeXLarge,
                      ],
                      block.fontSizeStep,
                      (i) => block.fontSizeStep = i,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.lineHeightLabel,
                      style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                    ),
                    const SizedBox(height: 10),
                    stepRow(
                      [
                        l10n.lineHeightCompact,
                        l10n.lineHeightStandard,
                        l10n.lineHeightRelaxed,
                      ],
                      block.lineHeightStep,
                      (i) => block.lineHeightStep = i,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

// 紧凑 4 列 Block 选择器——列表末尾"添加内容块"虚线按钮打开的那个
// sheet；跟顶栏图标行是两个不同的入口，图标行是"直接加"，这个是给
// 已经滚到内容区底部、不想再滚回顶栏的场景用
void showBlockPickerSheet(
  BuildContext context, {
  required AppLocalizations l10n,
  required bool isDarkMode,
  required void Function(BlockType type) onPick,
}) {
  const types = [
    BlockType.text,
    BlockType.code,
    BlockType.latex,
    BlockType.image,
    BlockType.callout,
    BlockType.link,
    BlockType.heading,
    BlockType.audio,
  ];
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final dark = Theme.of(ctx).brightness == Brightness.dark;
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 32),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF17171F) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 3,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 8),
                child: Text(
                  l10n.blockPickerTitle,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(ctx).textTheme.bodyLarge?.color,
                  ),
                ),
              ),
            ),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 4,
              childAspectRatio: 0.85,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: types
                  .map(
                    (type) => _BlockPickerItem(
                      icon: blockTypeIcon(type),
                      label: blockTypeLabel(l10n, type),
                      isDark: dark,
                      onTap: () {
                        Navigator.pop(ctx);
                        onPick(type);
                      },
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      );
    },
  );
}

class _BlockPickerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;
  const _BlockPickerItem({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF20284A) : const Color(0xFFEEF0FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 22, color: _primary),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    ),
  );
}
