import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../models/block_model.dart';

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
  BlockType.markdown => Icons.notes,
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
  BlockType.markdown => 'Markdown',
};
