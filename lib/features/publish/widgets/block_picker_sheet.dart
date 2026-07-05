import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../models/block_model.dart';

const _primary = Color(0xFF6366F1);

IconData blockTypeIcon(BlockType type) => switch (type) {
  BlockType.text => Icons.text_fields,
  BlockType.heading => Icons.title,
  BlockType.code => Icons.code,
  BlockType.latex => Icons.functions,
  BlockType.image => Icons.image_outlined,
  BlockType.file => Icons.attach_file,
  BlockType.audio => Icons.music_note_outlined,
  BlockType.video => Icons.videocam_outlined,
  BlockType.link => Icons.link,
  BlockType.callout => Icons.format_quote_outlined,
};

String blockTypeLabel(AppLocalizations l10n, BlockType type) => switch (type) {
  BlockType.text => l10n.blockTypeText,
  BlockType.heading => l10n.blockTypeHeading,
  BlockType.code => l10n.blockTypeCode,
  BlockType.latex => l10n.blockTypeLatex,
  BlockType.image => l10n.blockTypeImage,
  BlockType.file => l10n.blockTypeFile,
  BlockType.audio => l10n.blockTypeAudio,
  BlockType.video => l10n.blockTypeVideo,
  BlockType.link => l10n.blockTypeLink,
  BlockType.callout => l10n.blockTypeCallout,
};

class BlockPickerSheet extends StatelessWidget {
  final void Function(BlockType type) onSelect;
  const BlockPickerSheet({super.key, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.addBlockSheetTitle,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
          const SizedBox(height: 16),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.05,
            children: BlockType.values
                .map(
                  (type) => GestureDetector(
                    onTap: () => onSelect(type),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(blockTypeIcon(type), color: _primary, size: 24),
                          const SizedBox(height: 6),
                          Text(
                            blockTypeLabel(l10n, type),
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).textTheme.bodyLarge?.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}
