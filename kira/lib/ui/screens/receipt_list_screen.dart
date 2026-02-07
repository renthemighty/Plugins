// Kira - The Receipt Saver
// Day receipt list screen: shows all receipts for a selected day with
// date picker, category icons, thumbnails, and sort-by-time ordering.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../../core/db/receipt_dao.dart';
import '../../core/models/receipt.dart';
import '../theme/kira_icons.dart';
import '../theme/kira_theme.dart';
import 'receipt_detail_screen.dart';

class ReceiptListScreen extends StatefulWidget {
  /// If provided the screen opens to this date; otherwise today.
  final DateTime? initialDate;

  const ReceiptListScreen({super.key, this.initialDate});

  @override
  State<ReceiptListScreen> createState() => _ReceiptListScreenState();
}

class _ReceiptListScreenState extends State<ReceiptListScreen> {
  final ReceiptDao _receiptDao = ReceiptDao();

  late DateTime _selectedDate;
  List<Receipt> _receipts = [];
  bool _loading = true;
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now();
    _loadReceipts();
  }

  Future<void> _loadReceipts() async {
    setState(() => _loading = true);
    final dateString = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final receipts = await _receiptDao.getByDate(dateString);
    setState(() {
      _receipts = receipts;
      _sortReceipts();
      _loading = false;
    });
  }

  void _sortReceipts() {
    _receipts.sort((a, b) {
      final cmp = a.capturedAt.compareTo(b.capturedAt);
      return _sortAscending ? cmp : -cmp;
    });
  }

  Future<void> _pickDate() async {
    final l10n = AppLocalizations.of(context);
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: l10n.searchByDate,
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _loadReceipts();
    }
  }

  void _toggleSortOrder() {
    setState(() {
      _sortAscending = !_sortAscending;
      _sortReceipts();
    });
  }

  String _formatCurrency(double amount, String currencyCode) {
    final format = NumberFormat.currency(
      symbol: currencyCode == 'CAD' ? r'CA$' : r'US$',
      decimalDigits: 2,
    );
    return format.format(amount);
  }

  String _formatTime(String capturedAt) {
    try {
      final dt = DateTime.parse(capturedAt);
      return DateFormat.jm().format(dt);
    } catch (_) {
      return capturedAt;
    }
  }

  Color _categoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'meals':
        return KiraColors.categoryMeals;
      case 'travel':
        return KiraColors.categoryTravel;
      case 'office':
        return KiraColors.categoryOffice;
      case 'supplies':
        return KiraColors.categorySupplies;
      case 'fuel':
        return KiraColors.categoryFuel;
      case 'lodging':
        return KiraColors.categoryLodging;
      default:
        return KiraColors.categoryOther;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;
    final dateLabel = DateFormat.yMMMMd().format(_selectedDate);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(KiraIcons.arrowBack),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: l10n.back,
        ),
        title: Text(l10n.receiptList),
        actions: [
          IconButton(
            icon: Icon(
              _sortAscending ? KiraIcons.sort : KiraIcons.sort,
            ),
            tooltip: _sortAscending
                ? l10n.receiptDate
                : l10n.receiptDate,
            onPressed: _toggleSortOrder,
          ),
        ],
      ),
      body: Column(
        children: [
          // Date selector bar
          InkWell(
            onTap: _pickDate,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: KiraDimens.spacingLg,
                vertical: KiraDimens.spacingMd,
              ),
              decoration: BoxDecoration(
                color: colors.surface,
                boxShadow: KiraShadows.soft(),
              ),
              child: Row(
                children: [
                  Icon(
                    KiraIcons.calendar,
                    color: colors.primary,
                    size: KiraDimens.iconMd,
                  ),
                  const SizedBox(width: KiraDimens.spacingMd),
                  Expanded(
                    child: Text(
                      dateLabel,
                      style: text.titleMedium,
                    ),
                  ),
                  Icon(
                    KiraIcons.chevronRight,
                    color: colors.outline,
                    size: KiraDimens.iconMd,
                  ),
                ],
              ),
            ),
          ),

          // Receipt count summary
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KiraDimens.spacingLg,
              vertical: KiraDimens.spacingSm,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${l10n.receiptCount}: ${_receipts.length}',
                  style: text.bodySmall,
                ),
                if (_receipts.isNotEmpty)
                  Text(
                    '${l10n.totalTracked}: ${_formatCurrency(
                      _receipts.fold(0.0, (sum, r) => sum + r.amountTracked),
                      _receipts.first.currencyCode,
                    )}',
                    style: text.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Receipt list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _receipts.isEmpty
                    ? _buildEmptyState(l10n, colors, text)
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          vertical: KiraDimens.spacingSm,
                        ),
                        itemCount: _receipts.length,
                        itemBuilder: (context, index) =>
                            _buildReceiptCard(_receipts[index]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(
    AppLocalizations l10n,
    ColorScheme colors,
    TextTheme text,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KiraDimens.spacingXxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              KiraIcons.receipt,
              size: KiraDimens.iconXl,
              color: colors.outline,
            ),
            const SizedBox(height: KiraDimens.spacingLg),
            Text(
              l10n.noReceipts,
              style: text.titleMedium?.copyWith(color: colors.outline),
            ),
            const SizedBox(height: KiraDimens.spacingSm),
            Text(
              l10n.noReceiptsDescription,
              style: text.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptCard(Receipt receipt) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;
    final catColor = _categoryColor(receipt.category);

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: KiraDimens.spacingLg,
        vertical: KiraDimens.spacingXs,
      ),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ReceiptDetailScreen(receipt: receipt),
            ),
          );
        },
        borderRadius: BorderRadius.circular(KiraDimens.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(KiraDimens.spacingMd),
          child: Row(
            children: [
              // Thumbnail
              _buildThumbnail(receipt),
              const SizedBox(width: KiraDimens.spacingMd),

              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          KiraIcons.categoryIcon(receipt.category),
                          color: catColor,
                          size: KiraDimens.iconSm,
                        ),
                        const SizedBox(width: KiraDimens.spacingXs),
                        Expanded(
                          child: Text(
                            receipt.category,
                            style: text.titleSmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (receipt.conflict)
                          Tooltip(
                            message: l10n.warning,
                            child: Icon(
                              KiraIcons.warning,
                              color: KiraColors.pendingAmber,
                              size: KiraDimens.iconSm,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: KiraDimens.spacingXs),
                    Text(
                      _formatCurrency(
                        receipt.amountTracked,
                        receipt.currencyCode,
                      ),
                      style: text.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(height: KiraDimens.spacingXxs),
                    Row(
                      children: [
                        Icon(
                          KiraIcons.clock,
                          size: KiraDimens.iconSm,
                          color: colors.outline,
                        ),
                        const SizedBox(width: KiraDimens.spacingXxs),
                        Text(
                          _formatTime(receipt.capturedAt),
                          style: text.bodySmall,
                        ),
                        const SizedBox(width: KiraDimens.spacingMd),
                        Text(
                          receipt.region,
                          style: text.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              Icon(
                KiraIcons.chevronRight,
                color: colors.outline,
                size: KiraDimens.iconMd,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(Receipt receipt) {
    final colors = Theme.of(context).colorScheme;

    // Attempt to show thumbnail from local path.
    final localPath = receipt.filename;
    // Try constructing a path (the DAO stores local_path in the extended map,
    // but we work with what we have from the Receipt model).
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(KiraDimens.radiusSm),
        color: colors.surfaceContainerHighest,
      ),
      clipBehavior: Clip.antiAlias,
      child: Icon(
        KiraIcons.receipt,
        color: colors.outline,
        size: KiraDimens.iconLg,
      ),
    );
  }
}
