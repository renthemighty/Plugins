/// Kira - The Receipt Saver
///
/// Main home screen with bottom navigation for Receipts, Reports, and Settings
/// tabs. Includes a floating action button for quick receipt capture and a
/// trial-days-remaining banner for non-upgraded users.
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../core/services/trial_service.dart';
import '../navigation/app_router.dart';
import '../theme/kira_icons.dart';
import '../theme/kira_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  static const List<Widget> _tabs = [
    _ReceiptsTab(),
    _ReportsTab(),
    _SettingsTab(),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final trial = context.watch<TrialService>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Kira',
          style: theme.textTheme.titleLarge?.copyWith(
            color: colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        children: [
          // Trial banner
          if (trial.isTrialActive && !trial.isUpgraded)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: KiraDimens.spacingLg,
                vertical: KiraDimens.spacingSm,
              ),
              color: KiraColors.paleGreen,
              child: Row(
                children: [
                  Icon(
                    KiraIcons.info,
                    size: KiraDimens.iconSm,
                    color: KiraColors.primaryVariantLight,
                  ),
                  const SizedBox(width: KiraDimens.spacingSm),
                  Expanded(
                    child: Text(
                      '${trial.daysRemaining} days left in your free trial',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: KiraColors.primaryVariantLight,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pushNamed(AppRoutes.upgrade);
                    },
                    child: Text(
                      l10n?.appTitle ?? 'Upgrade',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Tab content
          Expanded(child: _tabs[_currentIndex]),
        ],
      ),

      // Capture FAB
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).pushNamed(AppRoutes.capture);
        },
        tooltip: 'Capture receipt',
        child: const Icon(KiraIcons.capture),
      ),

      // Bottom navigation
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(KiraIcons.receipt),
            label: 'Receipts',
          ),
          BottomNavigationBarItem(
            icon: Icon(KiraIcons.reports),
            label: 'Reports',
          ),
          BottomNavigationBarItem(
            icon: Icon(KiraIcons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab placeholders
// ---------------------------------------------------------------------------

class _ReceiptsTab extends StatelessWidget {
  const _ReceiptsTab();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            KiraIcons.receipt,
            size: KiraDimens.iconXl,
            color: theme.colorScheme.primary.withAlpha(128),
          ),
          const SizedBox(height: KiraDimens.spacingLg),
          Text(
            'Your receipts will appear here',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(153),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportsTab extends StatelessWidget {
  const _ReportsTab();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            KiraIcons.chart,
            size: KiraDimens.iconXl,
            color: theme.colorScheme.primary.withAlpha(128),
          ),
          const SizedBox(height: KiraDimens.spacingLg),
          Text(
            'Reports coming soon',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(153),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            KiraIcons.settings,
            size: KiraDimens.iconXl,
            color: theme.colorScheme.primary.withAlpha(128),
          ),
          const SizedBox(height: KiraDimens.spacingLg),
          Text(
            'Settings coming soon',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(153),
            ),
          ),
        ],
      ),
    );
  }
}
