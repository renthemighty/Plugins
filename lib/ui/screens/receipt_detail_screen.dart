// Kira - The Receipt Saver
// Receipt detail screen: full-size stamped image viewer, all metadata,
// sync status, checksum, conflict indicator. Notes/category are editable.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../../core/models/receipt.dart';
import '../theme/kira_icons.dart';
import '../theme/kira_theme.dart';

class ReceiptDetailScreen extends StatefulWidget {
  final Receipt receipt;

  const ReceiptDetailScreen({super.key, required this.receipt});

  @override
  State<ReceiptDetailScreen> createState() => _ReceiptDetailScreenState();
}

class _ReceiptDetailScreenState extends State<ReceiptDetailScreen> {
  late Receipt _receipt;
  late TextEditingController _notesController;
  late String _selectedCategory;
  bool _isEditing = false;

  static const List<String> _categories = [
    'Meals',
    'Travel',
    'Office',
    'Supplies',
    'Fuel',
    'Lodging',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _receipt = widget.receipt;
    _notesController = TextEditingController(text: _receipt.notes ?? '');
    _selectedCategory = _receipt.category;
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  String _formatCurrency(double amount, String currencyCode) {
    final format = NumberFormat.currency(
      symbol: currencyCode == 'CAD' ? r'CA$' : r'US$',
      decimalDigits: 2,
    );
    return format.format(amount);
  }

  String _formatDateTime(String isoString) {
    try {
      final dt = DateTime.parse(isoString);
      return DateFormat.yMMMMd().add_jm().format(dt);
    } catch (_) {
      return isoString;
    }
  }

  Color _syncStatusColor(String syncStatus) {
    switch (syncStatus) {
      case 'synced':
      case 'indexed':
        return KiraColors.syncedGreen;
      case 'local':
        return KiraColors.pendingAmber;
      default:
        return KiraColors.failedRed;
    }
  }

  String _syncStatusLabel(AppLocalizations l10n, String syncStatus) {
    switch (syncStatus) {
      case 'synced':
      case 'indexed':
        return l10n.storageConnected;
      case 'local':
        return l10n.offlineMode;
      default:
        return l10n.syncStatusError;
    }
  }

  void _toggleEdit() {
    setState(() {
      if (_isEditing) {
        // Save changes.
        _receipt = _receipt.copyWith(
          category: _selectedCategory,
          notes: () => _notesController.text.isEmpty
              ? null
              : _notesController.text,
          updatedAt: DateTime.now().toUtc().toIso8601String(),
        );
        // TODO: Persist via ReceiptDao.
      }
      _isEditing = !_isEditing;
    });
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
        title: Text(l10n.receiptDetail),
        actions: [
          IconButton(
            icon: Icon(_isEditing ? KiraIcons.save : KiraIcons.edit),
            onPressed: _toggleEdit,
            tooltip: _isEditing ? l10n.save : l10n.receiptNotes,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Full-size image viewer (immutable)
            _buildImageViewer(colors),
            const SizedBox(height: KiraDimens.spacingLg),

            // Conflict banner
            if (_receipt.conflict) _buildConflictBanner(l10n, colors, text),

            // Amount and currency
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: KiraDimens.spacingLg,
              ),
              child: Text(
                _formatCurrency(
                  _receipt.amountTracked,
                  _receipt.currencyCode,
                ),
                style: text.headlineMedium?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: KiraDimens.spacingXl),

            // Metadata sections
            _buildMetadataSection(l10n, colors, text),
            const Divider(height: KiraDimens.spacingXxl),

            // Sync status
            _buildSyncSection(l10n, colors, text),
            const Divider(height: KiraDimens.spacingXxl),

            // Checksum
            _buildChecksumSection(l10n, colors, text),
            const SizedBox(height: KiraDimens.spacingXxxl),
          ],
        ),
      ),
    );
  }

  Widget _buildImageViewer(ColorScheme colors) {
    // The stamped image is immutable -- display only.
    return Container(
      height: 280,
      width: double.infinity,
      color: colors.surfaceContainerHighest,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              KiraIcons.image,
              size: KiraDimens.iconXl * 1.5,
              color: colors.outline,
            ),
            const SizedBox(height: KiraDimens.spacingSm),
            Text(
              _receipt.filename,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConflictBanner(
    AppLocalizations l10n,
    ColorScheme colors,
    TextTheme text,
  ) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: KiraDimens.spacingLg),
      padding: const EdgeInsets.symmetric(
        horizontal: KiraDimens.spacingLg,
        vertical: KiraDimens.spacingMd,
      ),
      color: KiraColors.pendingAmber.withAlpha(30),
      child: Row(
        children: [
          const Icon(
            KiraIcons.warning,
            color: KiraColors.pendingAmber,
            size: KiraDimens.iconMd,
          ),
          const SizedBox(width: KiraDimens.spacingSm),
          Expanded(
            child: Text(
              l10n.warning,
              style: text.bodyMedium?.copyWith(
                color: KiraColors.pendingAmber,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataSection(
    AppLocalizations l10n,
    ColorScheme colors,
    TextTheme text,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KiraDimens.spacingLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date
          _buildMetadataRow(
            icon: KiraIcons.calendar,
            label: l10n.receiptDate,
            value: _formatDateTime(_receipt.capturedAt),
            colors: colors,
            text: text,
          ),
          const SizedBox(height: KiraDimens.spacingMd),

          // Category (editable)
          _buildMetadataRow(
            icon: KiraIcons.category,
            label: l10n.receiptCategory,
            value: _receipt.category,
            colors: colors,
            text: text,
            editWidget: _isEditing
                ? DropdownButton<String>(
                    value: _selectedCategory,
                    isExpanded: true,
                    underline: const SizedBox(),
                    items: _categories
                        .map((c) => DropdownMenuItem(
                              value: c,
                              child: Text(c, style: text.bodyMedium),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedCategory = val);
                      }
                    },
                  )
                : null,
          ),
          const SizedBox(height: KiraDimens.spacingMd),

          // Region
          _buildMetadataRow(
            icon: KiraIcons.business,
            label: l10n.receiptRegion,
            value: _receipt.region,
            colors: colors,
            text: text,
          ),
          const SizedBox(height: KiraDimens.spacingMd),

          // Currency
          _buildMetadataRow(
            icon: KiraIcons.currency,
            label: l10n.currencyCAD,
            value: _receipt.currencyCode,
            colors: colors,
            text: text,
          ),
          const SizedBox(height: KiraDimens.spacingMd),

          // Tax applicable
          _buildMetadataRow(
            icon: KiraIcons.receipt,
            label: l10n.taxApplicable,
            value: _receipt.taxApplicable == null
                ? '--'
                : _receipt.taxApplicable!
                    ? l10n.yes
                    : l10n.no,
            colors: colors,
            text: text,
          ),
          const SizedBox(height: KiraDimens.spacingMd),

          // Source
          _buildMetadataRow(
            icon: KiraIcons.camera,
            label: l10n.receiptSource,
            value: l10n.receiptSourceCamera,
            colors: colors,
            text: text,
          ),
          const SizedBox(height: KiraDimens.spacingMd),

          // Notes (editable)
          _buildNotesRow(l10n, colors, text),
        ],
      ),
    );
  }

  Widget _buildMetadataRow({
    required IconData icon,
    required String label,
    required String value,
    required ColorScheme colors,
    required TextTheme text,
    Widget? editWidget,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: KiraDimens.iconSm, color: colors.outline),
        const SizedBox(width: KiraDimens.spacingSm),
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: editWidget ??
              Text(
                value,
                style: text.bodyMedium,
              ),
        ),
      ],
    );
  }

  Widget _buildNotesRow(
    AppLocalizations l10n,
    ColorScheme colors,
    TextTheme text,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(KiraIcons.edit, size: KiraDimens.iconSm, color: colors.outline),
        const SizedBox(width: KiraDimens.spacingSm),
        SizedBox(
          width: 100,
          child: Text(
            l10n.receiptNotes,
            style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: _isEditing
              ? TextField(
                  controller: _notesController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: l10n.notes,
                    isDense: true,
                  ),
                )
              : Text(
                  _receipt.notes ?? '--',
                  style: text.bodyMedium,
                ),
        ),
      ],
    );
  }

  Widget _buildSyncSection(
    AppLocalizations l10n,
    ColorScheme colors,
    TextTheme text,
  ) {
    // We infer sync status from what we know. The Receipt model does not
    // carry sync_status directly, but the DAO extends it. For UI purposes
    // we show the source and created/updated timestamps.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KiraDimens.spacingLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.syncStatus,
            style: text.titleSmall,
          ),
          const SizedBox(height: KiraDimens.spacingSm),
          Row(
            children: [
              Icon(
                KiraIcons.syncStatusIcon('pending'),
                size: KiraDimens.iconMd,
                color: KiraColors.pendingAmber,
              ),
              const SizedBox(width: KiraDimens.spacingSm),
              Text(
                l10n.syncStatusIdle,
                style: text.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: KiraDimens.spacingSm),
          Text(
            '${l10n.receiptDate}: ${_formatDateTime(_receipt.createdAt)}',
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildChecksumSection(
    AppLocalizations l10n,
    ColorScheme colors,
    TextTheme text,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KiraDimens.spacingLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SHA-256',
            style: text.titleSmall,
          ),
          const SizedBox(height: KiraDimens.spacingSm),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  _receipt.checksumSha256,
                  style: text.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(KiraIcons.copy, size: KiraDimens.iconSm),
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(text: _receipt.checksumSha256),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.success)),
                  );
                },
                tooltip: l10n.done,
              ),
            ],
          ),
          const SizedBox(height: KiraDimens.spacingSm),
          Row(
            children: [
              Icon(
                KiraIcons.shield,
                size: KiraDimens.iconSm,
                color: colors.primary,
              ),
              const SizedBox(width: KiraDimens.spacingXs),
              Text(
                l10n.noOverwritePolicy,
                style: text.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
