// Kira - The Receipt Saver
// Integrity alerts screen: list of active integrity alerts with quarantine
// and dismiss actions, pull-to-refresh, and empty state.

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../../core/models/integrity_alert.dart';
import '../theme/kira_icons.dart';
import '../theme/kira_theme.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  List<IntegrityAlert> _alerts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAlerts();
  }

  Future<void> _loadAlerts() async {
    setState(() => _loading = true);
    // TODO: Load from integrity checker / DAO.
    // For now, display empty.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    setState(() {
      _loading = false;
    });
  }

  List<IntegrityAlert> get _activeAlerts =>
      _alerts.where((a) => !a.dismissed && !a.quarantined).toList();

  IconData _alertTypeIcon(IntegrityAlertType type) {
    switch (type) {
      case IntegrityAlertType.orphanFile:
        return KiraIcons.folder;
      case IntegrityAlertType.orphanEntry:
        return KiraIcons.receipt;
      case IntegrityAlertType.invalidFilename:
        return KiraIcons.error;
      case IntegrityAlertType.folderMismatch:
        return KiraIcons.folderOpen;
      case IntegrityAlertType.checksumMismatch:
        return KiraIcons.shield;
      case IntegrityAlertType.unexpectedFile:
        return KiraIcons.warning;
    }
  }

  Color _alertTypeColor(IntegrityAlertType type) {
    switch (type) {
      case IntegrityAlertType.checksumMismatch:
        return KiraColors.failedRed;
      case IntegrityAlertType.orphanFile:
      case IntegrityAlertType.orphanEntry:
      case IntegrityAlertType.folderMismatch:
        return KiraColors.pendingAmber;
      case IntegrityAlertType.invalidFilename:
      case IntegrityAlertType.unexpectedFile:
        return KiraColors.infoBlue;
    }
  }

  String _alertTypeLabel(AppLocalizations l10n, IntegrityAlertType type) {
    switch (type) {
      case IntegrityAlertType.orphanFile:
        return l10n.integrityOrphanFile;
      case IntegrityAlertType.orphanEntry:
        return l10n.integrityOrphanEntry;
      case IntegrityAlertType.invalidFilename:
        return l10n.integrityInvalidFilename;
      case IntegrityAlertType.folderMismatch:
        return l10n.integrityFolderMismatch;
      case IntegrityAlertType.checksumMismatch:
        return l10n.integrityChecksumMismatch;
      case IntegrityAlertType.unexpectedFile:
        return l10n.integrityUnexpectedFile;
    }
  }

  Future<void> _quarantineAlert(IntegrityAlert alert) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.integrityQuarantine),
        content: Text(alert.description),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        final idx = _alerts.indexOf(alert);
        if (idx >= 0) {
          _alerts[idx] = alert.copyWith(quarantined: true);
        }
      });
      // TODO: Persist quarantine via DAO and move file.
    }
  }

  void _dismissAlert(IntegrityAlert alert) {
    setState(() {
      final idx = _alerts.indexOf(alert);
      if (idx >= 0) {
        _alerts[idx] = alert.copyWith(dismissed: true);
      }
    });
    // TODO: Persist dismissal.
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;
    final active = _activeAlerts;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(KiraIcons.arrowBack),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: l10n.back,
        ),
        title: Text(l10n.integrityAlerts),
      ),
      body: RefreshIndicator(
        onRefresh: _loadAlerts,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : active.isEmpty
                ? _buildEmptyState(l10n, colors, text)
                : _buildAlertList(l10n, active, colors, text),
      ),
    );
  }

  Widget _buildEmptyState(
    AppLocalizations l10n,
    ColorScheme colors,
    TextTheme text,
  ) {
    return ListView(
      // ListView so pull-to-refresh still works on empty state.
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  KiraIcons.integrity,
                  size: KiraDimens.iconXl * 1.5,
                  color: KiraColors.syncedGreen,
                ),
                const SizedBox(height: KiraDimens.spacingLg),
                Text(
                  l10n.integrityNoAlerts,
                  style: text.titleMedium?.copyWith(
                    color: KiraColors.syncedGreen,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAlertList(
    AppLocalizations l10n,
    List<IntegrityAlert> active,
    ColorScheme colors,
    TextTheme text,
  ) {
    return Column(
      children: [
        // Active alerts banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: KiraDimens.spacingLg,
            vertical: KiraDimens.spacingMd,
          ),
          color: KiraColors.failedRed.withAlpha(25),
          child: Row(
            children: [
              const Icon(
                KiraIcons.warning,
                color: KiraColors.failedRed,
                size: KiraDimens.iconMd,
              ),
              const SizedBox(width: KiraDimens.spacingSm),
              Expanded(
                child: Text(
                  '${active.length} ${l10n.integrityAlerts}',
                  style: text.titleSmall?.copyWith(
                    color: KiraColors.failedRed,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Alert cards
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(
              vertical: KiraDimens.spacingSm,
            ),
            itemCount: active.length,
            itemBuilder: (context, index) =>
                _buildAlertCard(l10n, active[index], colors, text),
          ),
        ),
      ],
    );
  }

  Widget _buildAlertCard(
    AppLocalizations l10n,
    IntegrityAlert alert,
    ColorScheme colors,
    TextTheme text,
  ) {
    final typeColor = _alertTypeColor(alert.type);
    final typeIcon = _alertTypeIcon(alert.type);

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: KiraDimens.spacingLg,
        vertical: KiraDimens.spacingXs,
      ),
      child: Padding(
        padding: const EdgeInsets.all(KiraDimens.spacingLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(typeIcon, color: typeColor, size: KiraDimens.iconMd),
                const SizedBox(width: KiraDimens.spacingSm),
                Expanded(
                  child: Text(
                    _alertTypeLabel(l10n, alert.type),
                    style: text.titleSmall?.copyWith(color: typeColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: KiraDimens.spacingSm),

            // Description
            Text(alert.description, style: text.bodyMedium),
            const SizedBox(height: KiraDimens.spacingXs),

            // Path
            Row(
              children: [
                Icon(
                  KiraIcons.folder,
                  size: KiraDimens.iconSm,
                  color: colors.outline,
                ),
                const SizedBox(width: KiraDimens.spacingXs),
                Expanded(
                  child: Text(
                    alert.path,
                    style: text.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: KiraDimens.spacingSm),

            // Recommended action
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(KiraDimens.spacingSm),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(KiraDimens.radiusSm),
              ),
              child: Text(
                alert.recommendedAction,
                style: text.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            const SizedBox(height: KiraDimens.spacingMd),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _dismissAlert(alert),
                  child: Text(l10n.integrityDismiss),
                ),
                const SizedBox(width: KiraDimens.spacingSm),
                ElevatedButton.icon(
                  onPressed: () => _quarantineAlert(alert),
                  icon: const Icon(
                    KiraIcons.quarantine,
                    size: KiraDimens.iconSm,
                  ),
                  label: Text(l10n.integrityQuarantine),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: typeColor,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
