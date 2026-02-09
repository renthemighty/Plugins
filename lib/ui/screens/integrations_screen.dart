// Kira - The Receipt Saver
// Integrations screen: QuickBooks Online connect/disconnect, TurboTax export,
// roadmap for upcoming integrations, CRA/IRS recordkeeping note.

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../theme/kira_icons.dart';
import '../theme/kira_theme.dart';

class IntegrationsScreen extends StatefulWidget {
  const IntegrationsScreen({super.key});

  @override
  State<IntegrationsScreen> createState() => _IntegrationsScreenState();
}

class _IntegrationsScreenState extends State<IntegrationsScreen> {
  // QuickBooks state
  bool _quickBooksConnected = false;
  bool _quickBooksLoading = false;

  // Upcoming integrations roadmap
  static const _roadmapItems = [
    'Xero',
    'FreshBooks',
    'Zoho Books',
    'Sage',
  ];

  Future<void> _toggleQuickBooks() async {
    setState(() => _quickBooksLoading = true);

    // Simulate OAuth flow delay.
    await Future<void>.delayed(const Duration(seconds: 1));

    setState(() {
      _quickBooksConnected = !_quickBooksConnected;
      _quickBooksLoading = false;
    });

    if (mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _quickBooksConnected
                ? l10n.storageConnected
                : l10n.storageDisconnected,
          ),
        ),
      );
    }
  }

  Future<void> _exportTurboTax() async {
    final l10n = AppLocalizations.of(context);
    // TODO: Generate TurboTax-compatible export package.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.exportTaxPackage)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(KiraIcons.arrowBack),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: l10n.back,
        ),
        title: Text(l10n.integrationsTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: KiraDimens.spacingLg),
        children: [
          // -----------------------------------------------------------------
          // QuickBooks Online
          // -----------------------------------------------------------------
          _buildIntegrationCard(
            context: context,
            icon: KiraIcons.integrations,
            title: l10n.integrationsQuickBooks,
            connected: _quickBooksConnected,
            loading: _quickBooksLoading,
            onToggle: _toggleQuickBooks,
            colors: colors,
            text: text,
            l10n: l10n,
          ),
          const SizedBox(height: KiraDimens.spacingMd),

          // -----------------------------------------------------------------
          // TurboTax Export
          // -----------------------------------------------------------------
          Card(
            margin: const EdgeInsets.symmetric(
              horizontal: KiraDimens.spacingLg,
            ),
            child: Padding(
              padding: const EdgeInsets.all(KiraDimens.spacingLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        KiraIcons.exportIcon,
                        color: colors.primary,
                        size: KiraDimens.iconMd,
                      ),
                      const SizedBox(width: KiraDimens.spacingSm),
                      Expanded(
                        child: Text(
                          l10n.integrationsTurboTax,
                          style: text.titleSmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: KiraDimens.spacingMd),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _exportTurboTax,
                      icon: const Icon(
                        KiraIcons.exportIcon,
                        size: KiraDimens.iconSm,
                      ),
                      label: Text(l10n.exportTaxPackage),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: KiraDimens.spacingXl),

          // -----------------------------------------------------------------
          // Roadmap
          // -----------------------------------------------------------------
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KiraDimens.spacingLg,
            ),
            child: Row(
              children: [
                Icon(
                  KiraIcons.info,
                  size: KiraDimens.iconSm,
                  color: colors.outline,
                ),
                const SizedBox(width: KiraDimens.spacingSm),
                Text(
                  'Roadmap',
                  style: text.titleSmall?.copyWith(color: colors.outline),
                ),
              ],
            ),
          ),
          const SizedBox(height: KiraDimens.spacingSm),
          ..._roadmapItems.map((name) {
            return ListTile(
              leading: Icon(
                KiraIcons.link,
                color: colors.outline,
                size: KiraDimens.iconSm,
              ),
              title: Text(name, style: text.bodyMedium),
              subtitle: Text(
                'Coming soon',
                style: text.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
              dense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: KiraDimens.spacingLg,
              ),
            );
          }),
          const Divider(height: KiraDimens.spacingXxl),

          // -----------------------------------------------------------------
          // CRA/IRS note
          // -----------------------------------------------------------------
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KiraDimens.spacingLg,
            ),
            child: Container(
              padding: const EdgeInsets.all(KiraDimens.spacingLg),
              decoration: BoxDecoration(
                color: KiraColors.infoBlue.withAlpha(20),
                borderRadius: BorderRadius.circular(KiraDimens.radiusMd),
                border: Border.all(
                  color: KiraColors.infoBlue.withAlpha(60),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    KiraIcons.info,
                    color: KiraColors.infoBlue,
                    size: KiraDimens.iconMd,
                  ),
                  const SizedBox(width: KiraDimens.spacingSm),
                  Expanded(
                    child: Text(
                      'Kira helps with recordkeeping and exports. '
                      'Kira is not a tax advisor. Consult a qualified '
                      'professional for tax advice.',
                      style: text.bodySmall?.copyWith(
                        color: KiraColors.infoBlue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: KiraDimens.spacingXxxl),
        ],
      ),
    );
  }

  Widget _buildIntegrationCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required bool connected,
    required bool loading,
    required VoidCallback onToggle,
    required ColorScheme colors,
    required TextTheme text,
    required AppLocalizations l10n,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: KiraDimens.spacingLg),
      child: Padding(
        padding: const EdgeInsets.all(KiraDimens.spacingLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: colors.primary, size: KiraDimens.iconMd),
                const SizedBox(width: KiraDimens.spacingSm),
                Expanded(
                  child: Text(title, style: text.titleSmall),
                ),
                // Status chip
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KiraDimens.spacingSm,
                    vertical: KiraDimens.spacingXxs,
                  ),
                  decoration: BoxDecoration(
                    color: connected
                        ? KiraColors.syncedGreen.withAlpha(25)
                        : colors.surfaceContainerHighest,
                    borderRadius:
                        BorderRadius.circular(KiraDimens.radiusFull),
                  ),
                  child: Text(
                    connected
                        ? l10n.storageConnected
                        : l10n.storageDisconnected,
                    style: text.labelSmall?.copyWith(
                      color: connected
                          ? KiraColors.syncedGreen
                          : colors.outline,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: KiraDimens.spacingMd),
            SizedBox(
              width: double.infinity,
              child: loading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(KiraDimens.spacingSm),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : connected
                      ? OutlinedButton.icon(
                          onPressed: onToggle,
                          icon: const Icon(
                            KiraIcons.unlink,
                            size: KiraDimens.iconSm,
                          ),
                          label: Text(l10n.integrationsDisconnect),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colors.error,
                            side: BorderSide(color: colors.error),
                          ),
                        )
                      : ElevatedButton.icon(
                          onPressed: onToggle,
                          icon: const Icon(
                            KiraIcons.link,
                            size: KiraDimens.iconSm,
                          ),
                          label: Text(l10n.integrationsConnect),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
