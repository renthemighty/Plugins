// Kira - The Receipt Saver
// Reports dashboard: Daily, Monthly, Quarterly, Yearly tabs with charts,
// category/region breakdowns, and CSV/Tax Package export. All data from
// local DB (works offline). Uses fl_chart for visualizations.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../../core/db/receipt_dao.dart';
import '../../core/models/receipt.dart';
import '../theme/kira_icons.dart';
import '../theme/kira_theme.dart';

// ---------------------------------------------------------------------------
// Main screen
// ---------------------------------------------------------------------------

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ReceiptDao _receiptDao = ReceiptDao();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(KiraIcons.arrowBack),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: l10n.back,
        ),
        title: Text(l10n.reports),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: l10n.dailySummary),
            Tab(text: l10n.monthlySummary),
            Tab(text: l10n.quarterlySummary),
            Tab(text: l10n.yearlySummary),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _DailyReportTab(receiptDao: _receiptDao),
          _MonthlyReportTab(receiptDao: _receiptDao),
          _QuarterlyReportTab(receiptDao: _receiptDao),
          _YearlyReportTab(receiptDao: _receiptDao),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _fmtCurrency(double amount, String currencyCode) {
  final format = NumberFormat.currency(
    symbol: currencyCode == 'CAD' ? r'CA$' : r'US$',
    decimalDigits: 2,
  );
  return format.format(amount);
}

Map<String, double> _groupByCategory(List<Receipt> receipts) {
  final map = <String, double>{};
  for (final r in receipts) {
    map[r.category] = (map[r.category] ?? 0) + r.amountTracked;
  }
  return map;
}

Map<String, double> _groupByRegion(List<Receipt> receipts) {
  final map = <String, double>{};
  for (final r in receipts) {
    map[r.region] = (map[r.region] ?? 0) + r.amountTracked;
  }
  return map;
}

Color _chartColor(int index) {
  const palette = [
    KiraColors.categoryMeals,
    KiraColors.categoryTravel,
    KiraColors.categoryOffice,
    KiraColors.categorySupplies,
    KiraColors.categoryFuel,
    KiraColors.categoryLodging,
    KiraColors.categoryOther,
    KiraColors.softBlue,
    KiraColors.lavender,
  ];
  return palette[index % palette.length];
}

Widget _buildExportButtons(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: KiraDimens.spacingLg,
      vertical: KiraDimens.spacingMd,
    ),
    child: Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              // TODO: Implement CSV export.
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.exportCsv)),
              );
            },
            icon: const Icon(KiraIcons.csv, size: KiraDimens.iconSm),
            label: Text(l10n.exportCsv),
          ),
        ),
        const SizedBox(width: KiraDimens.spacingSm),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () {
              // TODO: Implement Tax Package export.
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.exportTaxPackage)),
              );
            },
            icon: const Icon(KiraIcons.exportIcon, size: KiraDimens.iconSm),
            label: Text(l10n.exportTaxPackage),
          ),
        ),
      ],
    ),
  );
}

Widget _buildCategoryBreakdown(
  BuildContext context,
  Map<String, double> byCategory,
) {
  final l10n = AppLocalizations.of(context);
  final text = Theme.of(context).textTheme;
  final colors = Theme.of(context).colorScheme;

  if (byCategory.isEmpty) return const SizedBox.shrink();

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: KiraDimens.spacingLg),
        child: Text(l10n.byCategory, style: text.titleSmall),
      ),
      const SizedBox(height: KiraDimens.spacingSm),
      ...byCategory.entries.map((e) {
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KiraDimens.spacingLg,
            vertical: KiraDimens.spacingXxs,
          ),
          child: Row(
            children: [
              Icon(
                KiraIcons.categoryIcon(e.key),
                size: KiraDimens.iconSm,
                color: colors.primary,
              ),
              const SizedBox(width: KiraDimens.spacingSm),
              Expanded(child: Text(e.key, style: text.bodyMedium)),
              Text(
                _fmtCurrency(e.value, 'CAD'),
                style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
      }),
    ],
  );
}

Widget _buildRegionBreakdown(
  BuildContext context,
  Map<String, double> byRegion,
) {
  final l10n = AppLocalizations.of(context);
  final text = Theme.of(context).textTheme;

  if (byRegion.isEmpty) return const SizedBox.shrink();

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: KiraDimens.spacingLg),
        child: Text(l10n.byRegion, style: text.titleSmall),
      ),
      const SizedBox(height: KiraDimens.spacingSm),
      ...byRegion.entries.map((e) {
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KiraDimens.spacingLg,
            vertical: KiraDimens.spacingXxs,
          ),
          child: Row(
            children: [
              const SizedBox(width: KiraDimens.spacingXl),
              Expanded(child: Text(e.key, style: Theme.of(context).textTheme.bodyMedium)),
              Text(
                _fmtCurrency(e.value, 'CAD'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        );
      }),
    ],
  );
}

Widget _buildSummaryCards(
  BuildContext context, {
  required double total,
  required int count,
  required String currencyCode,
}) {
  final l10n = AppLocalizations.of(context);
  final text = Theme.of(context).textTheme;
  final colors = Theme.of(context).colorScheme;

  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: KiraDimens.spacingLg),
    child: Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(KiraDimens.spacingLg),
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(KiraDimens.radiusMd),
            ),
            child: Column(
              children: [
                Text(
                  l10n.totalTracked,
                  style: text.labelSmall?.copyWith(
                    color: colors.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: KiraDimens.spacingXs),
                Text(
                  _fmtCurrency(total, currencyCode),
                  style: text.titleLarge?.copyWith(
                    color: colors.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: KiraDimens.spacingMd),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(KiraDimens.spacingLg),
            decoration: BoxDecoration(
              color: colors.secondaryContainer,
              borderRadius: BorderRadius.circular(KiraDimens.radiusMd),
            ),
            child: Column(
              children: [
                Text(
                  l10n.receiptCount,
                  style: text.labelSmall?.copyWith(
                    color: colors.onSecondaryContainer,
                  ),
                ),
                const SizedBox(height: KiraDimens.spacingXs),
                Text(
                  '$count',
                  style: text.titleLarge?.copyWith(
                    color: colors.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Daily tab
// ---------------------------------------------------------------------------

class _DailyReportTab extends StatefulWidget {
  final ReceiptDao receiptDao;

  const _DailyReportTab({required this.receiptDao});

  @override
  State<_DailyReportTab> createState() => _DailyReportTabState();
}

class _DailyReportTabState extends State<_DailyReportTab> {
  DateTime _selectedDate = DateTime.now();
  List<Receipt> _receipts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final receipts = await widget.receiptDao.getByDate(dateStr);
    setState(() {
      _receipts = receipts;
      _loading = false;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      _selectedDate = picked;
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final total = _receipts.fold(0.0, (s, r) => s + r.amountTracked);
    final byCategory = _groupByCategory(_receipts);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: KiraDimens.spacingLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Date picker
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: KiraDimens.spacingLg),
            child: OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(KiraIcons.calendar),
              label: Text(DateFormat.yMMMMd().format(_selectedDate)),
            ),
          ),
          const SizedBox(height: KiraDimens.spacingLg),

          _buildSummaryCards(
            context,
            total: total,
            count: _receipts.length,
            currencyCode: _receipts.isNotEmpty
                ? _receipts.first.currencyCode
                : 'CAD',
          ),
          const SizedBox(height: KiraDimens.spacingXl),

          // Bar chart by category
          if (byCategory.isNotEmpty) ...[
            SizedBox(
              height: 200,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: KiraDimens.spacingLg,
                ),
                child: BarChart(
                  BarChartData(
                    barGroups: byCategory.entries.toList().asMap().entries.map(
                      (e) {
                        return BarChartGroupData(
                          x: e.key,
                          barRods: [
                            BarChartRodData(
                              toY: e.value.value,
                              color: _chartColor(e.key),
                              width: 20,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(KiraDimens.radiusSm),
                              ),
                            ),
                          ],
                        );
                      },
                    ).toList(),
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            final entries = byCategory.entries.toList();
                            final idx = value.toInt();
                            if (idx < 0 || idx >= entries.length) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                entries[idx].key.substring(
                                      0,
                                      entries[idx].key.length > 4
                                          ? 4
                                          : entries[idx].key.length,
                                    ),
                                style:
                                    Theme.of(context).textTheme.labelSmall,
                              ),
                            );
                          },
                        ),
                      ),
                      leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    gridData: const FlGridData(show: false),
                  ),
                ),
              ),
            ),
            const SizedBox(height: KiraDimens.spacingXl),
          ],

          _buildCategoryBreakdown(context, byCategory),
          const SizedBox(height: KiraDimens.spacingLg),
          _buildRegionBreakdown(context, _groupByRegion(_receipts)),
          const SizedBox(height: KiraDimens.spacingLg),
          _buildExportButtons(context),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Monthly tab
// ---------------------------------------------------------------------------

class _MonthlyReportTab extends StatefulWidget {
  final ReceiptDao receiptDao;

  const _MonthlyReportTab({required this.receiptDao});

  @override
  State<_MonthlyReportTab> createState() => _MonthlyReportTabState();
}

class _MonthlyReportTabState extends State<_MonthlyReportTab> {
  late DateTime _selectedMonth;
  List<Receipt> _receipts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final yearMonth = DateFormat('yyyy-MM').format(_selectedMonth);
    final receipts = await widget.receiptDao.getReceiptsForMonth(yearMonth);
    setState(() {
      _receipts = receipts;
      _loading = false;
    });
  }

  void _previousMonth() {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month - 1,
      );
    });
    _load();
  }

  void _nextMonth() {
    final now = DateTime.now();
    final next = DateTime(
      _selectedMonth.year,
      _selectedMonth.month + 1,
    );
    if (next.isAfter(DateTime(now.year, now.month + 1))) return;
    setState(() => _selectedMonth = next);
    _load();
  }

  /// Groups receipts by day and returns daily totals.
  Map<int, double> _dailyTotals() {
    final map = <int, double>{};
    for (final r in _receipts) {
      try {
        final day = DateTime.parse(r.capturedAt).day;
        map[day] = (map[day] ?? 0) + r.amountTracked;
      } catch (_) {}
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final total = _receipts.fold(0.0, (s, r) => s + r.amountTracked);
    final byCategory = _groupByCategory(_receipts);
    final dailyTotals = _dailyTotals();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: KiraDimens.spacingLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Month selector
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: KiraDimens.spacingLg),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(KiraIcons.chevronLeft),
                  onPressed: _previousMonth,
                ),
                Text(
                  DateFormat.yMMMM().format(_selectedMonth),
                  style: text.titleMedium,
                ),
                IconButton(
                  icon: const Icon(KiraIcons.chevronRight),
                  onPressed: _nextMonth,
                ),
              ],
            ),
          ),
          const SizedBox(height: KiraDimens.spacingLg),

          _buildSummaryCards(
            context,
            total: total,
            count: _receipts.length,
            currencyCode: _receipts.isNotEmpty
                ? _receipts.first.currencyCode
                : 'CAD',
          ),
          const SizedBox(height: KiraDimens.spacingXl),

          // Line chart of daily totals
          if (dailyTotals.isNotEmpty) ...[
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: KiraDimens.spacingLg),
              child: Text(l10n.dailySummary, style: text.titleSmall),
            ),
            const SizedBox(height: KiraDimens.spacingSm),
            SizedBox(
              height: 200,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: KiraDimens.spacingLg,
                ),
                child: LineChart(
                  LineChartData(
                    lineBarsData: [
                      LineChartBarData(
                        spots: dailyTotals.entries
                            .map((e) =>
                                FlSpot(e.key.toDouble(), e.value))
                            .toList()
                          ..sort((a, b) => a.x.compareTo(b.x)),
                        isCurved: true,
                        color: colors.primary,
                        barWidth: 2,
                        dotData: const FlDotData(show: true),
                        belowBarData: BarAreaData(
                          show: true,
                          color: colors.primary.withAlpha(30),
                        ),
                      ),
                    ],
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: 5,
                          getTitlesWidget: (value, _) => Text(
                            '${value.toInt()}',
                            style: text.labelSmall,
                          ),
                        ),
                      ),
                      leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    gridData: const FlGridData(show: false),
                  ),
                ),
              ),
            ),
            const SizedBox(height: KiraDimens.spacingXl),
          ],

          _buildCategoryBreakdown(context, byCategory),
          const SizedBox(height: KiraDimens.spacingLg),
          _buildExportButtons(context),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quarterly tab
// ---------------------------------------------------------------------------

class _QuarterlyReportTab extends StatefulWidget {
  final ReceiptDao receiptDao;

  const _QuarterlyReportTab({required this.receiptDao});

  @override
  State<_QuarterlyReportTab> createState() => _QuarterlyReportTabState();
}

class _QuarterlyReportTabState extends State<_QuarterlyReportTab> {
  int _selectedYear = DateTime.now().year;
  List<Receipt> _receipts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final receipts =
        await widget.receiptDao.getReceiptsForYear('$_selectedYear');
    setState(() {
      _receipts = receipts;
      _loading = false;
    });
  }

  /// Returns receipts for a given quarter (1-4).
  List<Receipt> _quarterReceipts(int quarter) {
    final startMonth = (quarter - 1) * 3 + 1;
    final endMonth = startMonth + 3;
    return _receipts.where((r) {
      try {
        final month = DateTime.parse(r.capturedAt).month;
        return month >= startMonth && month < endMonth;
      } catch (_) {
        return false;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Quarterly totals
    final quarterData = <int, double>{};
    for (var q = 1; q <= 4; q++) {
      final qReceipts = _quarterReceipts(q);
      quarterData[q] = qReceipts.fold(0.0, (s, r) => s + r.amountTracked);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: KiraDimens.spacingLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Year selector
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: KiraDimens.spacingLg),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(KiraIcons.chevronLeft),
                  onPressed: () {
                    setState(() => _selectedYear--);
                    _load();
                  },
                ),
                Text('$_selectedYear', style: text.titleMedium),
                IconButton(
                  icon: const Icon(KiraIcons.chevronRight),
                  onPressed: () {
                    if (_selectedYear < DateTime.now().year) {
                      setState(() => _selectedYear++);
                      _load();
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: KiraDimens.spacingLg),

          // Comparison bar chart
          SizedBox(
            height: 200,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: KiraDimens.spacingLg,
              ),
              child: BarChart(
                BarChartData(
                  barGroups: quarterData.entries.map((e) {
                    return BarChartGroupData(
                      x: e.key,
                      barRods: [
                        BarChartRodData(
                          toY: e.value,
                          color: _chartColor(e.key - 1),
                          width: 32,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(KiraDimens.radiusSm),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, _) => Text(
                          'Q${value.toInt()}',
                          style: text.labelMedium,
                        ),
                      ),
                    ),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(show: false),
                ),
              ),
            ),
          ),
          const SizedBox(height: KiraDimens.spacingXl),

          // Per-quarter details
          ...List.generate(4, (i) {
            final q = i + 1;
            final qReceipts = _quarterReceipts(q);
            final qTotal =
                qReceipts.fold(0.0, (s, r) => s + r.amountTracked);
            final byCat = _groupByCategory(qReceipts);

            return ExpansionTile(
              title: Text('Q$q', style: text.titleSmall),
              subtitle: Text(
                '${_fmtCurrency(qTotal, 'CAD')} -- ${qReceipts.length} ${l10n.receiptList}',
                style: text.bodySmall,
              ),
              children: [
                _buildCategoryBreakdown(context, byCat),
                const SizedBox(height: KiraDimens.spacingSm),
              ],
            );
          }),
          const SizedBox(height: KiraDimens.spacingLg),
          _buildExportButtons(context),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Yearly tab
// ---------------------------------------------------------------------------

class _YearlyReportTab extends StatefulWidget {
  final ReceiptDao receiptDao;

  const _YearlyReportTab({required this.receiptDao});

  @override
  State<_YearlyReportTab> createState() => _YearlyReportTabState();
}

class _YearlyReportTabState extends State<_YearlyReportTab> {
  int _selectedYear = DateTime.now().year;
  List<Receipt> _receipts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final receipts =
        await widget.receiptDao.getReceiptsForYear('$_selectedYear');
    setState(() {
      _receipts = receipts;
      _loading = false;
    });
  }

  /// Group by month for trends.
  Map<int, double> _monthlyTotals() {
    final map = <int, double>{};
    for (final r in _receipts) {
      try {
        final month = DateTime.parse(r.capturedAt).month;
        map[month] = (map[month] ?? 0) + r.amountTracked;
      } catch (_) {}
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final total = _receipts.fold(0.0, (s, r) => s + r.amountTracked);
    final byCategory = _groupByCategory(_receipts);
    final byRegion = _groupByRegion(_receipts);
    final monthlyTotals = _monthlyTotals();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: KiraDimens.spacingLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Year selector
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: KiraDimens.spacingLg),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(KiraIcons.chevronLeft),
                  onPressed: () {
                    setState(() => _selectedYear--);
                    _load();
                  },
                ),
                Text(
                  '${l10n.yearlySummary} $_selectedYear',
                  style: text.titleMedium,
                ),
                IconButton(
                  icon: const Icon(KiraIcons.chevronRight),
                  onPressed: () {
                    if (_selectedYear < DateTime.now().year) {
                      setState(() => _selectedYear++);
                      _load();
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: KiraDimens.spacingLg),

          _buildSummaryCards(
            context,
            total: total,
            count: _receipts.length,
            currencyCode: _receipts.isNotEmpty
                ? _receipts.first.currencyCode
                : 'CAD',
          ),
          const SizedBox(height: KiraDimens.spacingXl),

          // Trends line chart
          if (monthlyTotals.isNotEmpty) ...[
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: KiraDimens.spacingLg),
              child: Text(l10n.monthlySummary, style: text.titleSmall),
            ),
            const SizedBox(height: KiraDimens.spacingSm),
            SizedBox(
              height: 200,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: KiraDimens.spacingLg,
                ),
                child: LineChart(
                  LineChartData(
                    lineBarsData: [
                      LineChartBarData(
                        spots: monthlyTotals.entries
                            .map((e) =>
                                FlSpot(e.key.toDouble(), e.value))
                            .toList()
                          ..sort((a, b) => a.x.compareTo(b.x)),
                        isCurved: true,
                        color: colors.primary,
                        barWidth: 2.5,
                        dotData: const FlDotData(show: true),
                        belowBarData: BarAreaData(
                          show: true,
                          color: colors.primary.withAlpha(25),
                        ),
                      ),
                    ],
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: 1,
                          getTitlesWidget: (value, _) {
                            final m = value.toInt();
                            if (m < 1 || m > 12) {
                              return const SizedBox.shrink();
                            }
                            return Text(
                              DateFormat.MMM()
                                  .format(DateTime(2000, m))
                                  .substring(0, 3),
                              style: text.labelSmall,
                            );
                          },
                        ),
                      ),
                      leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    gridData: const FlGridData(show: false),
                  ),
                ),
              ),
            ),
            const SizedBox(height: KiraDimens.spacingXl),
          ],

          _buildCategoryBreakdown(context, byCategory),
          const SizedBox(height: KiraDimens.spacingLg),
          _buildRegionBreakdown(context, byRegion),
          const SizedBox(height: KiraDimens.spacingLg),
          _buildExportButtons(context),
        ],
      ),
    );
  }
}
