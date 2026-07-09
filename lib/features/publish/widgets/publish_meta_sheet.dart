import 'package:flutter/material.dart';

import '../../../core/utils/membership_utils.dart';
import '../../../core/widgets/pro_gate.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/utils/premium_button.dart';
import '../../../shared/utils/topic_badge.dart';

const _primary = Color(0xFF6366F1);
const _ink = Color(0xFF1A1A1A);

const _seriesTagOptions = ['连载', '独立', '翻译', '深度', '快讯'];

// 封面 + 摘要 + 标签，固定在 Block 列表上方（不跟着一起滚动）——发布
// 前一眼就知道这篇要发的是什么，不用滚到最上面确认
class PublishMetaSection extends StatelessWidget {
  final AppLocalizations l10n;
  final bool isDarkMode;
  final List<String> tags;
  final VoidCallback onAddTag;
  final void Function(String tag) onRemoveTag;
  final String? coverImageUrl;
  final VoidCallback onCoverTap;
  final TextEditingController summaryController;
  final VoidCallback onSummaryChanged;
  final bool generatingSummary;
  final VoidCallback onAiGenerateSummary;
  final String seriesTag;
  final String subtitle;
  final VoidCallback onTitleInsertionTap;
  final String? selectedColumnId;
  final String? selectedColumnName;
  final VoidCallback onColumnTap;
  final VoidCallback onColumnCancel;

  const PublishMetaSection({
    super.key,
    required this.l10n,
    required this.isDarkMode,
    required this.tags,
    required this.onAddTag,
    required this.onRemoveTag,
    required this.coverImageUrl,
    required this.onCoverTap,
    required this.summaryController,
    required this.onSummaryChanged,
    required this.generatingSummary,
    required this.onAiGenerateSummary,
    required this.seriesTag,
    required this.subtitle,
    required this.onTitleInsertionTap,
    required this.selectedColumnId,
    required this.selectedColumnName,
    required this.onColumnTap,
    required this.onColumnCancel,
  });

  @override
  Widget build(BuildContext context) {
    final topicRule = matchedTopicRuleFor(tags);

    return Column(
      children: [
        // 封面图缩小成一个小方块，塞进摘要这一行左边，跟摘要输入框合并
        // 成一行——不再单独占一整张 140px 高的卡，省下来的空间让整个
        // 元信息区更紧凑
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDarkMode
                  ? Theme.of(context).dividerColor
                  : const Color(0xFFEBEBEB),
              width: 0.5,
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: onCoverTap,
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F0F8),
                          borderRadius: BorderRadius.circular(10),
                          image: coverImageUrl != null
                              ? DecorationImage(
                                  image: NetworkImage(coverImageUrl!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: coverImageUrl == null
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.add_photo_alternate_outlined,
                                    size: 20,
                                    color: (topicRule?.fg ?? _primary)
                                        .withValues(alpha: 0.6),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    l10n.coverImageLabel,
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: (topicRule?.fg ?? _primary)
                                          .withValues(alpha: 0.6),
                                    ),
                                  ),
                                ],
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          TextField(
                            controller: summaryController,
                            decoration: InputDecoration(
                              filled: false,
                              hintText: l10n.addSummaryHint,
                              hintStyle: const TextStyle(
                                color: Color(0xFF888888),
                                fontSize: 13,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF888888),
                              height: 1.4,
                            ),
                            maxLines: 4,
                            minLines: 3,
                            onChanged: (_) => onSummaryChanged(),
                          ),
                          if (generatingSummary)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 4),
                              child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: _primary,
                                ),
                              ),
                            )
                          else if (summaryController.text.isEmpty)
                            ProGate(
                              check: MembershipUtils.canUseXmeng,
                              featureName: '小梦 AI',
                              child: PressableScale(
                                onTap: onAiGenerateSummary,
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: premiumPillDecoration(
                                      radius: 7,
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.auto_awesome,
                                          size: 10,
                                          color: Colors.white,
                                        ),
                                        SizedBox(width: 3),
                                        Text(
                                          '小梦生成',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.white,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
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
              _rowDivider(context, isDarkMode),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ...tags.map(
                      (tag) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: isDarkMode
                              ? _primary.withValues(alpha: 0.15)
                              : const Color(0xFFEEF0FF),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: _primary, width: 0.5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '#$tag',
                              style: const TextStyle(
                                fontSize: 12,
                                color: _primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: () => onRemoveTag(tag),
                              behavior: HitTestBehavior.opaque,
                              child: const Icon(
                                Icons.close,
                                size: 14,
                                color: _primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: onAddTag,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFD1D1D6)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.add, size: 12, color: Colors.grey),
                            const SizedBox(width: 3),
                            Text(
                              l10n.addTagAction,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _rowDivider(context, isDarkMode),
              _metaEntryRow(
                context,
                icon: Icons.sell_outlined,
                iconBg: const Color(0xFFF5F5F5),
                iconColor: const Color(0xFF888888),
                title: l10n.titleInsertionAction,
                subtitle: seriesTag.isNotEmpty || subtitle.isNotEmpty
                    ? [
                        if (seriesTag.isNotEmpty) seriesTag,
                        if (subtitle.isNotEmpty) subtitle,
                      ].join(' · ')
                    : l10n.titleInsertionSubtitleShortHint,
                onTap: onTitleInsertionTap,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: _joinColumnEntry(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 未选：虚线边框+书本图标；已选：实线紫色边框+专栏名+×直接取消，不用
  // 重新打开sheet选"不加入专栏"那条
  Widget _joinColumnEntry(BuildContext context) {
    final selected = selectedColumnId != null;
    return GestureDetector(
      onTap: onColumnTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? _primary.withValues(alpha: 0.06) : null,
          borderRadius: BorderRadius.circular(10),
          // Flutter 原生 Border 不支持虚线，未选中状态就用纯灰实线区分，
          // 不额外引入画虚线的依赖
          border: Border.all(
            color: selected ? _primary : const Color(0xFFD1D1D6),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: 20,
              color: selected ? _primary : Colors.grey[500],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selected ? selectedColumnName ?? '' : l10n.joinColumnAction,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: selected ? _primary : null,
                    ),
                  ),
                  if (!selected)
                    Text(
                      l10n.joinColumnSubtitleHint,
                      style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                    ),
                ],
              ),
            ),
            if (selected)
              GestureDetector(
                onTap: onColumnCancel,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: _primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 14, color: _primary),
                ),
              )
            else
              const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBBBBBB)),
          ],
        ),
      ),
    );
  }

  Widget _rowDivider(BuildContext context, bool isDarkMode) => Divider(
    height: 0.5,
    thickness: 0.5,
    indent: 14,
    endIndent: 14,
    color: isDarkMode
        ? Theme.of(context).dividerColor
        : const Color(0xFFF5F5F5),
  );

  Widget _metaEntryRow(
    BuildContext context, {
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 14, color: iconColor),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFBBBBBB),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBBBBBB)),
          ],
        ),
      ),
    );
  }
}

void showTitleInsertionSheet(
  BuildContext context, {
  required AppLocalizations l10n,
  required String currentTitle,
  required String initialSubtitle,
  required String initialSeriesTag,
  required String initialIssueNumber,
  required void Function({
    required String subtitle,
    required String seriesTag,
    required String issueNumber,
  })
  onSaved,
}) {
  final subtitleCtrl = TextEditingController(text: initialSubtitle);
  final issueCtrl = TextEditingController(text: initialIssueNumber);
  String tempSeriesTag = initialSeriesTag;
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(ctx).cardColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            padding: EdgeInsets.fromLTRB(
              16,
              10,
              16,
              MediaQuery.of(ctx).padding.bottom + 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.titleInsertionAction,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.subtitleLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: subtitleCtrl,
                    onChanged: (_) => setSheetState(() {}),
                    decoration: InputDecoration(
                      hintText: l10n.subtitleHint,
                      filled: true,
                      fillColor: const Color(0xFFF5F5F5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    l10n.seriesTagLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _seriesTagOptions.map((tag) {
                      final selected = tempSeriesTag == tag;
                      return GestureDetector(
                        onTap: () => setSheetState(
                          () => tempSeriesTag = selected ? '' : tag,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: selected ? _ink : const Color(0xFFF5F5F5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            tag,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: selected
                                  ? Colors.white
                                  : const Color(0xFF555555),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    l10n.issueNumberLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: issueCtrl,
                    onChanged: (_) => setSheetState(() {}),
                    decoration: InputDecoration(
                      hintText: l10n.issueNumberHint,
                      filled: true,
                      fillColor: const Color(0xFFF5F5F5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.previewLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAFAF8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (tempSeriesTag.isNotEmpty) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _ink,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  tempSeriesTag,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text(
                                currentTitle.isEmpty
                                    ? l10n.notePlaceholderTitle
                                    : currentTitle,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: _ink,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (subtitleCtrl.text.isNotEmpty ||
                            issueCtrl.text.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            [
                              if (subtitleCtrl.text.isNotEmpty)
                                subtitleCtrl.text,
                              if (issueCtrl.text.isNotEmpty) issueCtrl.text,
                            ].join(' · '),
                            style: const TextStyle(
                              fontSize: 12,
                              color: _primary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        onSaved(
                          subtitle: subtitleCtrl.text.trim(),
                          seriesTag: tempSeriesTag,
                          issueNumber: issueCtrl.text.trim(),
                        );
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _ink,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        l10n.done,
                        style: const TextStyle(
                          color: Colors.white,
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
      },
    ),
  );
}
