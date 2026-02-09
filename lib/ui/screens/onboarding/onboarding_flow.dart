/// Kira - The Receipt Saver
///
/// Multi-step onboarding flow with a [PageView] containing three placeholder
/// pages: Country Selection, Storage Setup, and Sync Policy. Navigates to
/// the home screen on completion.
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../main.dart';
import '../../navigation/app_router.dart';
import '../../theme/kira_icons.dart';
import '../../theme/kira_theme.dart';

class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const int _totalPages = 3;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _onDone() {
    final appSettings = context.read<AppSettingsProvider>();
    appSettings.setOnboardingComplete(true);
    Navigator.of(context).pushReplacementNamed(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bool isLastPage = _currentPage == _totalPages - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Page indicators
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: KiraDimens.spacingXl,
                vertical: KiraDimens.spacingLg,
              ),
              child: Row(
                children: List.generate(_totalPages, (index) {
                  final bool isActive = index == _currentPage;
                  return Expanded(
                    child: Container(
                      height: 4,
                      margin: const EdgeInsets.symmetric(
                        horizontal: KiraDimens.spacingXxs,
                      ),
                      decoration: BoxDecoration(
                        color: isActive
                            ? colorScheme.primary
                            : colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(
                          KiraDimens.radiusFull,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),

            // Page content
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                children: const [
                  _CountrySelectionPage(),
                  _StorageSetupPage(),
                  _SyncPolicyPage(),
                ],
              ),
            ),

            // Navigation button
            Padding(
              padding: const EdgeInsets.all(KiraDimens.spacingXl),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isLastPage ? _onDone : _nextPage,
                  child: Text(isLastPage ? 'Done' : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Onboarding pages
// ---------------------------------------------------------------------------

class _CountrySelectionPage extends StatelessWidget {
  const _CountrySelectionPage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KiraDimens.spacingXl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            KiraIcons.language,
            size: KiraDimens.iconXl * 2,
            color: colorScheme.primary,
          ),
          const SizedBox(height: KiraDimens.spacingXl),
          Text(
            'Country Selection',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: KiraDimens.spacingMd),
          Text(
            'Choose your country to set up the correct receipt folder '
            'structure and tax formats.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurface.withAlpha(153),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _StorageSetupPage extends StatelessWidget {
  const _StorageSetupPage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KiraDimens.spacingXl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            KiraIcons.cloud,
            size: KiraDimens.iconXl * 2,
            color: colorScheme.primary,
          ),
          const SizedBox(height: KiraDimens.spacingXl),
          Text(
            'Storage Setup',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: KiraDimens.spacingMd),
          Text(
            'Connect a cloud storage provider to automatically back up '
            'your receipts. Choose from Google Drive, Dropbox, OneDrive, '
            'and more.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurface.withAlpha(153),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SyncPolicyPage extends StatelessWidget {
  const _SyncPolicyPage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KiraDimens.spacingXl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            KiraIcons.sync,
            size: KiraDimens.iconXl * 2,
            color: colorScheme.primary,
          ),
          const SizedBox(height: KiraDimens.spacingXl),
          Text(
            'Sync Policy',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: KiraDimens.spacingMd),
          Text(
            'Decide when Kira syncs your receipts. Choose from Wi-Fi only, '
            'always, or manual sync to save data.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurface.withAlpha(153),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
