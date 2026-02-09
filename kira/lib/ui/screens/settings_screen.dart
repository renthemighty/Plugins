// Kira - The Receipt Saver
// Settings screen: language selector, categories editor, sync preferences,
// low data mode, background uploads, app lock, storage status, sync now,
// legal section with pricing disclaimer, about section.

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../navigation/app_router.dart';
import '../theme/kira_icons.dart';
import '../theme/kira_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Language
  String _selectedLanguage = 'en';

  // Categories
  List<String> _categories = [
    'Meals',
    'Travel',
    'Office',
    'Supplies',
    'Fuel',
    'Lodging',
    'Other',
  ];

  // Sync
  String _syncPreference = 'wifi_only'; // wifi_only | wifi_cellular
  bool _lowDataMode = false;
  bool _backgroundUploads = true;

  // App lock
  bool _appLockEnabled = false;

  // Storage
  String _storageStatus = 'connected'; // connected | disconnected

  // Legal
  bool _pricingAcknowledged = false;

  // Version
  static const String _appVersion = '1.0.0';

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
        title: Text(l10n.settings),
      ),
      body: ListView(
        children: [
          // ---------------------------------------------------------------
          // Language selector
          // ---------------------------------------------------------------
          _buildSectionHeader(l10n.settingsLanguage, KiraIcons.language, text),
          _buildLanguageTile(l10n, colors, text),
          const Divider(),

          // ---------------------------------------------------------------
          // Categories editor
          // ---------------------------------------------------------------
          _buildSectionHeader(
            l10n.settingsCategories,
            KiraIcons.category,
            text,
          ),
          _buildCategoriesEditor(l10n, colors, text),
          const Divider(),

          // ---------------------------------------------------------------
          // Sync preferences
          // ---------------------------------------------------------------
          _buildSectionHeader(
            l10n.settingsSyncPreferences,
            KiraIcons.sync,
            text,
          ),
          _buildSyncPreferenceTile(l10n, colors, text),
          const Divider(),

          // ---------------------------------------------------------------
          // Low Data Mode
          // ---------------------------------------------------------------
          _buildToggleTile(
            icon: KiraIcons.syncOffline,
            title: l10n.settingsLowDataMode,
            subtitle: l10n.syncLowDataModeDescription,
            value: _lowDataMode,
            onChanged: (val) => setState(() => _lowDataMode = val),
          ),
          const Divider(),

          // ---------------------------------------------------------------
          // Background uploads
          // ---------------------------------------------------------------
          _buildToggleTile(
            icon: KiraIcons.syncPending,
            title: l10n.settingsBackgroundUploads,
            subtitle: _backgroundUploads
                ? l10n.backgroundSyncEnabled
                : l10n.backgroundSyncDisabled,
            value: _backgroundUploads,
            onChanged: (val) => setState(() => _backgroundUploads = val),
          ),
          const Divider(),

          // ---------------------------------------------------------------
          // App Lock (biometric/PIN) - for paid mode
          // ---------------------------------------------------------------
          _buildToggleTile(
            icon: KiraIcons.fingerprint,
            title: l10n.settingsAppLock,
            subtitle: l10n.settingsAppLockBiometric,
            value: _appLockEnabled,
            onChanged: (val) => setState(() => _appLockEnabled = val),
          ),
          const Divider(),

          // ---------------------------------------------------------------
          // Storage connection status
          // ---------------------------------------------------------------
          _buildSectionHeader(
            l10n.syncStatus,
            KiraIcons.cloud,
            text,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KiraDimens.spacingLg,
              vertical: KiraDimens.spacingSm,
            ),
            child: Row(
              children: [
                Icon(
                  _storageStatus == 'connected'
                      ? KiraIcons.syncDone
                      : KiraIcons.syncFailed,
                  color: _storageStatus == 'connected'
                      ? KiraColors.syncedGreen
                      : KiraColors.failedRed,
                  size: KiraDimens.iconMd,
                ),
                const SizedBox(width: KiraDimens.spacingSm),
                Text(
                  _storageStatus == 'connected'
                      ? l10n.storageConnected
                      : l10n.storageDisconnected,
                  style: text.bodyMedium,
                ),
              ],
            ),
          ),

          // Sync Now button
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KiraDimens.spacingLg,
              vertical: KiraDimens.spacingSm,
            ),
            child: ElevatedButton.icon(
              onPressed: () {
                // TODO: Trigger manual sync.
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.syncNow)),
                );
              },
              icon: const Icon(KiraIcons.sync, size: KiraDimens.iconSm),
              label: Text(l10n.syncNow),
            ),
          ),
          const Divider(),

          // ---------------------------------------------------------------
          // Legal section
          // ---------------------------------------------------------------
          _buildSectionHeader(l10n.settingsLegal, KiraIcons.shield, text),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KiraDimens.spacingLg,
              vertical: KiraDimens.spacingSm,
            ),
            child: Text(
              l10n.kiraStoragePricingDisclaimer,
              style: text.bodySmall?.copyWith(fontStyle: FontStyle.italic),
            ),
          ),
          CheckboxListTile(
            value: _pricingAcknowledged,
            onChanged: (val) =>
                setState(() => _pricingAcknowledged = val ?? false),
            title: Text(
              l10n.kiraStoragePricingAck,
              style: text.bodyMedium,
            ),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: KiraDimens.spacingLg,
            ),
          ),
          const Divider(),

          // ---------------------------------------------------------------
          // About Kira
          // ---------------------------------------------------------------
          _buildSectionHeader(l10n.settingsAbout, KiraIcons.about, text),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KiraDimens.spacingLg,
              vertical: KiraDimens.spacingSm,
            ),
            child: Row(
              children: [
                Icon(
                  KiraIcons.logo,
                  color: colors.primary,
                  size: KiraDimens.iconLg,
                ),
                const SizedBox(width: KiraDimens.spacingSm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${l10n.appName} - ${l10n.appTagline}',
                      style: text.titleSmall,
                    ),
                    Text(
                      l10n.settingsVersion(_appVersion),
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
          // ---------------------------------------------------------------
          // Admin Panel
          // ---------------------------------------------------------------
          _buildSectionHeader(
            l10n.adminPanel,
            KiraIcons.admin,
            text,
          ),
          ListTile(
            leading: const Icon(KiraIcons.admin, size: KiraDimens.iconMd),
            title: Text(l10n.adminPanel, style: text.bodyMedium),
            subtitle: Text(l10n.adminMetrics, style: text.bodySmall),
            trailing: const Icon(KiraIcons.chevronRight, size: KiraDimens.iconSm),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: KiraDimens.spacingLg,
            ),
            onTap: () {
              Navigator.of(context).pushNamed(AppRoutes.adminPanel);
            },
          ),
          ListTile(
            leading: const Icon(KiraIcons.error, size: KiraDimens.iconMd),
            title: Text(l10n.adminErrorPanel, style: text.bodyMedium),
            subtitle: Text(l10n.adminExportErrors, style: text.bodySmall),
            trailing: const Icon(KiraIcons.chevronRight, size: KiraDimens.iconSm),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: KiraDimens.spacingLg,
            ),
            onTap: () {
              Navigator.of(context).pushNamed(AppRoutes.adminErrors);
            },
          ),
          const Divider(),

          const SizedBox(height: KiraDimens.spacingXxxl),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Section header
  // -----------------------------------------------------------------------

  Widget _buildSectionHeader(String title, IconData icon, TextTheme text) {
    return Padding(
      padding: const EdgeInsets.only(
        left: KiraDimens.spacingLg,
        right: KiraDimens.spacingLg,
        top: KiraDimens.spacingXl,
        bottom: KiraDimens.spacingXs,
      ),
      child: Row(
        children: [
          Icon(icon, size: KiraDimens.iconSm),
          const SizedBox(width: KiraDimens.spacingSm),
          Text(title, style: text.titleSmall),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Language tile
  // -----------------------------------------------------------------------

  Widget _buildLanguageTile(
    AppLocalizations l10n,
    ColorScheme colors,
    TextTheme text,
  ) {
    final languages = <String, String>{
      'en': 'English',
      'fr_CA': 'Francais (Canada)',
      'es_US': 'Espanol (US)',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KiraDimens.spacingLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: languages.entries.map((entry) {
          return RadioListTile<String>(
            value: entry.key,
            groupValue: _selectedLanguage,
            title: Text(entry.value, style: text.bodyMedium),
            onChanged: (val) {
              if (val != null) {
                setState(() => _selectedLanguage = val);
                // TODO: Apply locale change.
              }
            },
            contentPadding: EdgeInsets.zero,
            dense: true,
          );
        }).toList(),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Categories editor
  // -----------------------------------------------------------------------

  Widget _buildCategoriesEditor(
    AppLocalizations l10n,
    ColorScheme colors,
    TextTheme text,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KiraDimens.spacingLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _categories.length,
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex--;
                final item = _categories.removeAt(oldIndex);
                _categories.insert(newIndex, item);
              });
            },
            itemBuilder: (context, index) {
              final cat = _categories[index];
              return ListTile(
                key: ValueKey(cat),
                leading: Icon(
                  KiraIcons.categoryIcon(cat),
                  size: KiraDimens.iconSm,
                  color: colors.primary,
                ),
                title: Text(cat, style: text.bodyMedium),
                trailing: IconButton(
                  icon: Icon(
                    KiraIcons.remove,
                    size: KiraDimens.iconSm,
                    color: colors.error,
                  ),
                  onPressed: () {
                    setState(() => _categories.removeAt(index));
                  },
                  tooltip: l10n.delete,
                ),
                dense: true,
                contentPadding: EdgeInsets.zero,
              );
            },
          ),
          TextButton.icon(
            onPressed: () => _showAddCategoryDialog(l10n),
            icon: const Icon(KiraIcons.add, size: KiraDimens.iconSm),
            label: Text(l10n.category),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddCategoryDialog(AppLocalizations l10n) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.category),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.category),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(l10n.save),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      setState(() => _categories.add(result));
    }
    controller.dispose();
  }

  // -----------------------------------------------------------------------
  // Sync preference tile
  // -----------------------------------------------------------------------

  Widget _buildSyncPreferenceTile(
    AppLocalizations l10n,
    ColorScheme colors,
    TextTheme text,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KiraDimens.spacingLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RadioListTile<String>(
            value: 'wifi_only',
            groupValue: _syncPreference,
            title: Text(l10n.syncWifiOnly, style: text.bodyMedium),
            onChanged: (val) {
              if (val != null) setState(() => _syncPreference = val);
            },
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
          RadioListTile<String>(
            value: 'wifi_cellular',
            groupValue: _syncPreference,
            title: Text(l10n.syncWifiAndCellular, style: text.bodyMedium),
            onChanged: (val) {
              if (val != null) setState(() => _syncPreference = val);
            },
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Toggle tile
  // -----------------------------------------------------------------------

  Widget _buildToggleTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      secondary: Icon(icon, size: KiraDimens.iconMd),
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: KiraDimens.spacingLg,
      ),
    );
  }
}
