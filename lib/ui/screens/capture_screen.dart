/// Kira - The Receipt Saver
///
/// Camera capture screen placeholder. Displays a centered camera icon and
/// placeholder text. The actual camera integration will replace this UI.
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../theme/kira_icons.dart';
import '../theme/kira_theme.dart';

class CaptureScreen extends StatelessWidget {
  const CaptureScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(KiraIcons.arrowBack),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          l10n?.appTitle ?? 'Capture',
          style: theme.textTheme.titleLarge,
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KiraDimens.spacingXl,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Camera icon
              Container(
                width: KiraDimens.iconXl * 3,
                height: KiraDimens.iconXl * 3,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withAlpha(26),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  KiraIcons.camera,
                  size: KiraDimens.iconXl * 1.5,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: KiraDimens.spacingXl),

              // Placeholder text
              Text(
                'Camera capture coming soon',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurface.withAlpha(179),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: KiraDimens.spacingSm),

              Text(
                'Point your camera at a receipt to save it instantly.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withAlpha(128),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
