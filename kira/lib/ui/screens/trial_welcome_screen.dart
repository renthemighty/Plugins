/// Kira - The Receipt Saver
///
/// Welcome screen shown during the 7-day free trial. Presents the app name,
/// a tagline, and navigation options for new and returning users.
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../core/services/trial_service.dart';
import '../navigation/app_router.dart';
import '../theme/kira_icons.dart';
import '../theme/kira_theme.dart';

class TrialWelcomeScreen extends StatelessWidget {
  const TrialWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final trial = context.watch<TrialService>();
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

              // App logo placeholder
              Icon(
                KiraIcons.logo,
                size: KiraDimens.iconXl * 2,
                color: colorScheme.primary,
              ),
              const SizedBox(height: KiraDimens.spacingLg),

              // App name
              Text(
                'Kira',
                style: theme.textTheme.headlineLarge?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: KiraDimens.spacingSm),

              // Tagline
              Text(
                l10n?.appTitle ?? 'Save every receipt. Forget nothing.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurface.withAlpha(179),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: KiraDimens.spacingXl),

              // Trial days remaining badge
              if (trial.isTrialActive)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KiraDimens.spacingLg,
                    vertical: KiraDimens.spacingSm,
                  ),
                  decoration: BoxDecoration(
                    color: KiraColors.paleGreen,
                    borderRadius: BorderRadius.circular(KiraDimens.radiusFull),
                  ),
                  child: Text(
                    '${trial.daysRemaining} days remaining in trial',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: KiraColors.primaryVariantLight,
                    ),
                  ),
                ),

              const Spacer(flex: 3),

              // Get Started button (new users -> onboarding)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pushReplacementNamed(
                      AppRoutes.onboardingFlow,
                    );
                  },
                  child: const Text('Get Started'),
                ),
              ),
              const SizedBox(height: KiraDimens.spacingMd),

              // Continue button (returning users -> home)
              if (trial.isUpgraded || trial.canCapture)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).pushReplacementNamed(
                        AppRoutes.home,
                      );
                    },
                    child: const Text('Continue'),
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
