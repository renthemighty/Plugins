/// Kira - The Receipt Saver
///
/// Upgrade wall screen shown when the 7-day trial has expired. Prompts the
/// user to upgrade in order to continue capturing and syncing receipts.
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../theme/kira_icons.dart';
import '../theme/kira_theme.dart';

class UpgradeWallScreen extends StatelessWidget {
  const UpgradeWallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KiraDimens.spacingXl,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),

              // Warning icon
              Container(
                width: KiraDimens.iconXl * 2,
                height: KiraDimens.iconXl * 2,
                decoration: BoxDecoration(
                  color: KiraColors.blushPink.withAlpha(77),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  KiraIcons.warning,
                  size: KiraDimens.iconXl,
                  color: KiraColors.secondaryLight,
                ),
              ),
              const SizedBox(height: KiraDimens.spacingXl),

              // Title
              Text(
                'Trial Expired',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: KiraDimens.spacingLg),

              // Body text
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: KiraDimens.spacingLg,
                ),
                child: Text(
                  'Your 7-day free trial has ended. Upgrade to continue '
                  'capturing receipts, syncing to cloud storage, and '
                  'generating reports.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurface.withAlpha(179),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              const Spacer(flex: 3),

              // Upgrade button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Coming soon'),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(
                      vertical: KiraDimens.spacingLg,
                    ),
                  ),
                  child: const Text('Upgrade'),
                ),
              ),
              const SizedBox(height: KiraDimens.spacingMd),

              // Learn More link
              TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Coming soon'),
                    ),
                  );
                },
                child: Text(
                  'Learn More',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.primary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),

              const SizedBox(height: KiraDimens.spacingXxl),
            ],
          ),
        ),
      ),
    );
  }
}
