import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../models/block_model.dart';
import 'block_picker_sheet.dart';

const _primary = Color(0xFF6366F1);

const _textColors = [
  null, // 默认——跟随主题正文色，不是字面意义上的"黑"
  Color(0xFF6366F1),
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

  const BlockFormattingToolbar({
    super.key,
    required this.l10n,
    required this.isDarkMode,
    required this.block,
    required this.onChanged,
    required this.onShowFontSheet,
    required this.onConvertHeading,
  });

  bool get _applicable =>
      block != null &&
      (block!.type == BlockType.text || block!.type == BlockType.heading);

  @override
  Widget build(BuildContext context) {
    if (!_applicable) return const SizedBox.shrink();
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
              ],
            ),
          ),
          Divider(height: 0.5, thickness: 0.5, color: dividerColor),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              children: [
                Text(
                  l10n.formattingTextColorLabel,
                  style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                ),
                const SizedBox(width: 8),
                ..._textColors.map(
                  (c) => _colorDot(
                    color: c ?? (isDarkMode ? Colors.white : Colors.black),
                    selected: b.textColorValue == c?.toARGB32(),
                    onTap: () => _toggle(() => b.textColorValue = c?.toARGB32()),
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

  // 再点一次同一个 H 级别就转回普通文字段落，不用先切别的类型再切回来
  void _toggleHeading(EditorBlock b, int level) {
    final alreadyThisLevel = b.type == BlockType.heading && b.headingLevel == level;
    onConvertHeading(alreadyThisLevel ? null : level);
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
