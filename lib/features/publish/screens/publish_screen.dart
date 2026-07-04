import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';

class PublishScreen extends StatelessWidget {
  const PublishScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: Text(l10n.publish)),
      body: Center(
        child: Text(
          l10n.pageUnderDevelopment(l10n.publish),
          style: const TextStyle(color: AppColors.textMuted),
        ),
      ),
    );
  }
}
