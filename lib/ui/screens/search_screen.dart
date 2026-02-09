// Kira - The Receipt Saver
// Search screen: calendar/date picker, date range selector, results list
// with receipt cards, filter by category and region.

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../../core/db/receipt_dao.dart';
import '../../core/models/receipt.dart';
import '../theme/kira_icons.dart';
import '../theme/kira_theme.dart';
import 'receipt_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final ReceiptDao _receiptDao = ReceiptDao();

  DateTime? _startDate;
  DateTime? _endDate;
  String? _filterCategory;
  String? _filterRegion;

  List<Receipt> _results = [];
  bool _loading = false;
  bool _hasSearched = false;

  Set<String> _availableCategories = {};
  Set<String> _availableRegions = {};

  Future<void> _pickStartDate() async {
    final l10n = AppLocalizations.of(context);
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: l10n.searchByDate,
    );
    if (picked != null) {
      setState(() => _startDate = picked);
    }
  }

  Future<void> _pickEndDate() async {
    final l10n = AppLocalizations.of(context);
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? DateTime.now(),
      firstDate: _startDate ?? DateTime(2020),
      lastDate: DateTime.now(),
      helpText: l10n.searchByDate,
    );
    if (picked != null) {
      setState(() => _endDate = picked);
    }
  }

  Future<void> _search() async {
    if (_startDate == null || _endDate == null) return;

    setState(() {
      _loading = true;
      _hasSearched = true;
    });

    final start = DateFormat('yyyy-MM-dd').format(_startDate!);
    // End date is exclusive, so add one day.
    final endPlusOne = _endDate!.add(const Duration(days: 1));
    final end = DateFormat('yyyy-MM-dd').format(endPlusOne);

    var results = await _receiptDao.searchByDateRange(start, end);

    // Collect available filter options.
    _availableCategories = results.map((r) => r.category).toSet();
    _availableRegions = results.map((r) => r.region).toSet();

    // Apply filters.
    if (_filterCategory != null) {
      results = results.where((r) => r.category == _filterCategory).toList();
    }
    if (_filterRegion != null) {
      results = results.where((r) => r.region == _filterRegion).toList();
    }

    setState(() {
      _results = results;
      _loading = false;
    });
  }

  void _clearFilters() {
    setState(() {
      _filterCategory = null;
      _filterRegion = null;
    });
    _search();
  }

  String _formatCurrency(double amount, String currencyCode) {
    final format = NumberFormat.currency(
      symbol: currencyCode == 'CAD' ? r'CA$' : r'US$',
      decimalDigits: 2,
    );
    return format.format(amount);
  }

  String _formatDate(String capturedAt) {
    try {
      final dt = DateTime.parse(capturedAt);
      return DateFormat.yMMMd().add_jm().format(dt);
    } catch (_) {
      return capturedAt;
    }
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
        title: Text(l10n.searchByDate),
      ),
      body: Column(
        children: [
          // Date range selectors
          Container(
            padding: const EdgeInsets.all(KiraDimens.spacingLg),
            decoration: BoxDecoration(
              color: colors.surface,
              boxShadow: KiraShadows.soft(),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildDateButton(
                        label: _startDate != null
                            ? DateFormat.yMMMd().format(_startDate!)
                            : l10n.receiptDate,
                        icon: KiraIcons.calendar,
                        onTap: _pickStartDate,
                        colors: colors,
                        text: text,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: KiraDimens.spacingSm,
                      ),
                      child: Icon(Icons.arrow_forward, size: KiraDimens.iconSm),
                    ),
                    Expanded(
                      child: _buildDateButton(
                        label: _endDate != null
                            ? DateFormat.yMMMd().format(_endDate!)
                            : l10n.receiptDate,
                        icon: KiraIcons.dateRange,
                        onTap: _pickEndDate,
                        colors: colors,
                        text: text,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: KiraDimens.spacingMd),

                // Filter chips
                if (_availableCategories.isNotEmpty ||
                    _availableRegions.isNotEmpty)
                  _buildFilterChips(l10n, colors, text),

                const SizedBox(height: KiraDimens.spacingMd),

                // Search button
                ElevatedButton.icon(
                  onPressed:
                      _startDate != null && _endDate != null ? _search : null,
                  icon: const Icon(KiraIcons.search),
                  label: Text(l10n.search),
                ),
              ],
            ),
          ),

          // Results
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : !_hasSearched
                    ? _buildInitialState(l10n, colors, text)
                    : _results.isEmpty
                        ? _buildEmptyResults(l10n, colors, text)
                        : _buildResultsList(l10n),
          ),
        ],
      ),
    );
  }

  Widget _buildDateButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    required ColorScheme colors,
    required TextTheme text,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: KiraDimens.iconSm),
      label: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: text.bodySmall,
      ),
    );
  }

  Widget _buildFilterChips(
    AppLocalizations l10n,
    ColorScheme colors,
    TextTheme text,
  ) {
    return Wrap(
      spacing: KiraDimens.spacingSm,
      runSpacing: KiraDimens.spacingXs,
      children: [
        // Category filter
        if (_availableCategories.isNotEmpty)
          ...[
            Icon(KiraIcons.filter, size: KiraDimens.iconSm, color: colors.outline),
            ..._availableCategories.map(
              (cat) => FilterChip(
                selected: _filterCategory == cat,
                label: Text(cat, style: text.labelSmall),
                avatar: Icon(
                  KiraIcons.categoryIcon(cat),
                  size: KiraDimens.iconSm,
                ),
                onSelected: (selected) {
                  setState(() {
                    _filterCategory = selected ? cat : null;
                  });
                  _search();
                },
              ),
            ),
          ],

        // Region filter
        if (_availableRegions.isNotEmpty)
          ..._availableRegions.map(
            (region) => FilterChip(
              selected: _filterRegion == region,
              label: Text(region, style: text.labelSmall),
              onSelected: (selected) {
                setState(() {
                  _filterRegion = selected ? region : null;
                });
                _search();
              },
            ),
          ),

        // Clear filters
        if (_filterCategory != null || _filterRegion != null)
          ActionChip(
            label: Text(l10n.close, style: text.labelSmall),
            avatar: const Icon(KiraIcons.close, size: KiraDimens.iconSm),
            onPressed: _clearFilters,
          ),
      ],
    );
  }

  Widget _buildInitialState(
    AppLocalizations l10n,
    ColorScheme colors,
    TextTheme text,
  ) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            KiraIcons.search,
            size: KiraDimens.iconXl,
            color: colors.outline,
          ),
          const SizedBox(height: KiraDimens.spacingLg),
          Text(
            l10n.searchByDate,
            style: text.titleMedium?.copyWith(color: colors.outline),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyResults(
    AppLocalizations l10n,
    ColorScheme colors,
    TextTheme text,
  ) {
    return Center(
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
        ],
      ),
    );
  }

  Widget _buildResultsList(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KiraDimens.spacingLg,
            vertical: KiraDimens.spacingSm,
          ),
          child: Text(
            '${l10n.receiptCount}: ${_results.length}',
            style: text.bodySmall,
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(
              vertical: KiraDimens.spacingSm,
            ),
            itemCount: _results.length,
            itemBuilder: (context, index) {
              final receipt = _results[index];
              return Card(
                margin: const EdgeInsets.symmetric(
                  horizontal: KiraDimens.spacingLg,
                  vertical: KiraDimens.spacingXs,
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        colors.primaryContainer,
                    child: Icon(
                      KiraIcons.categoryIcon(receipt.category),
                      color: colors.onPrimaryContainer,
                      size: KiraDimens.iconSm,
                    ),
                  ),
                  title: Text(
                    _formatCurrency(
                      receipt.amountTracked,
                      receipt.currencyCode,
                    ),
                    style: text.titleSmall,
                  ),
                  subtitle: Text(
                    '${receipt.category} - ${_formatDate(receipt.capturedAt)}',
                    style: text.bodySmall,
                  ),
                  trailing: const Icon(
                    KiraIcons.chevronRight,
                    size: KiraDimens.iconMd,
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            ReceiptDetailScreen(receipt: receipt),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
