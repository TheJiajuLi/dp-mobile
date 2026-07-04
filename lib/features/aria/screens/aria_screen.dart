import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';

class AriaScreen extends StatelessWidget {
  const AriaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('ARIA')),
      body: Center(
        child: Text(
          l10n.pageUnderDevelopment('ARIA'),
          style: const TextStyle(color: AppColors.textMuted),
        ),
      ),
    );
  }
}
