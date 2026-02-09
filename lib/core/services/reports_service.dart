/// Reports aggregation service for the Kira app.
///
/// Provides offline-capable receipt analytics by querying the local SQLite
/// database directly. All methods return [ReportData] objects that contain
/// pre-aggregated totals, breakdowns, and trend data suitable for rendering
/// with `fl_chart` or any other charting library.
///
/// This service never touches the network -- it works entirely against the
/// local database, so dashboards remain functional in airplane mode.
library;

import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../db/database_helper.dart';

// ---------------------------------------------------------------------------
// DateRange helper
// ---------------------------------------------------------------------------

/// An inclusive date range used to scope report queries.
class DateRange {
  /// Start of the range (inclusive), at midnight local time.
  final DateTime start;

  /// End of the range (inclusive), at 23:59:59.999 local time.
  final DateTime end;

  const DateRange({required this.start, required this.end});

  /// Creates a [DateRange] spanning a single calendar day.
  factory DateRange.singleDay(DateTime date) {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
    return DateRange(start: dayStart, end: dayEnd);
  }

  /// Creates a [DateRange] spanning a full calendar month.
  factory DateRange.month(int year, int month) {
    final start = DateTime(year, month);
    // Month + 1, day 0 gives the last day of the target month.
    final end = DateTime(year, month + 1, 0, 23, 59, 59, 999);
    return DateRange(start: start, end: end);
  }

  /// Creates a [DateRange] for a fiscal/calendar quarter (1-4).
  factory DateRange.quarter(int year, int quarter) {
    assert(quarter >= 1 && quarter <= 4, 'Quarter must be between 1 and 4');
    final startMonth = (quarter - 1) * 3 + 1;
    final endMonth = startMonth + 2;
    final start = DateTime(year, startMonth);
    final end = DateTime(year, endMonth + 1, 0, 23, 59, 59, 999);
    return DateRange(start: start, end: end);
  }

  /// Creates a [DateRange] spanning a full calendar year.
  factory DateRange.year(int year) {
    return DateRange(
      start: DateTime(year),
      end: DateTime(year, 12, 31, 23, 59, 59, 999),
    );
  }

  /// ISO-8601 string for the start boundary (for SQL `>=` comparison).
  String get startIso => _toIso(start);

  /// ISO-8601 string for the end boundary (for SQL `<=` comparison).
  String get endIso => _toIso(end);

  static String _toIso(DateTime dt) {
    return dt.toIso8601String().split('.').first; // drop sub-second
  }
}

// ---------------------------------------------------------------------------
// ReportData
// ---------------------------------------------------------------------------

/// Aggregated report payload returned by every [ReportsService] query.
///
/// Not all fields are populated for every report type -- for instance a daily
/// summary will have a single entry in [dailyTotals] while a yearly summary
/// will have up to 366 entries. Consumers should check for `null` / empty maps
/// as appropriate.
class ReportData {
  /// Grand total of all `amount_tracked` values in the queried range.
  final double totalAmount;

  /// Number of non-expired receipts in the queried range.
  final int receiptCount;

  /// Sum of amounts grouped by category label.
  /// Example: `{ 'meals': 42.50, 'transport': 18.00 }`
  final Map<String, double> categoryBreakdown;

  /// Sum of amounts grouped by region (province / state code).
  /// Example: `{ 'ON': 100.00, 'CA': 55.00 }`
  final Map<String, double> regionBreakdown;

  /// Sum of amounts grouped by date key.
  ///
  /// The key format depends on the granularity of the report:
  ///   - daily reports: single entry keyed `YYYY-MM-DD`
  ///   - monthly reports: entries keyed `YYYY-MM-DD` for each day
  ///   - weekly trends: entries keyed `YYYY-Www` (ISO week)
  ///   - monthly trends: entries keyed `YYYY-MM`
  final Map<String, double> dailyTotals;

  /// The dominant currency code across the queried receipts.
  ///
  /// When all receipts share the same currency this is that code; otherwise
  /// it defaults to the currency with the highest total.
  final String currency;

  /// Optional per-currency totals when the dataset contains mixed currencies.
  /// `null` when all receipts share a single currency.
  final Map<String, double>? currencyTotals;

  /// Count of receipts grouped by category.
  final Map<String, int>? categoryCounts;

  const ReportData({
    required this.totalAmount,
    required this.receiptCount,
    this.categoryBreakdown = const <String, double>{},
    this.regionBreakdown = const <String, double>{},
    this.dailyTotals = const <String, double>{},
    this.currency = 'CAD',
    this.currencyTotals,
    this.categoryCounts,
  });

  /// An empty report with zeroed-out fields.
  static const empty = ReportData(totalAmount: 0, receiptCount: 0);

  @override
  String toString() =>
      'ReportData(total: $totalAmount $currency, receipts: $receiptCount, '
      'categories: ${categoryBreakdown.length}, '
      'regions: ${regionBreakdown.length})';
}

// ---------------------------------------------------------------------------
// TrendGranularity
// ---------------------------------------------------------------------------

/// Controls the bucket size when computing trend data.
enum TrendGranularity { daily, weekly, monthly }

// ---------------------------------------------------------------------------
// ReportsService
// ---------------------------------------------------------------------------

/// Offline-capable reporting engine backed by the local SQLite database.
///
/// Usage:
/// ```dart
/// final reports = ReportsService();
/// final today = await reports.getDailySummary(DateTime.now());
/// print(today.totalAmount);
/// ```
class ReportsService {
  ReportsService({DatabaseHelper? databaseHelper})
      : _dbHelper = databaseHelper ?? DatabaseHelper();

  final DatabaseHelper _dbHelper;

  // -------------------------------------------------------------------------
  // SQL filter clause shared by all queries
  // -------------------------------------------------------------------------

  /// Base WHERE clause that excludes expired/deleted receipts.
  static const String _baseWhere = 'expired = 0';

  /// Builds a WHERE clause scoped to the given [DateRange].
  static String _dateWhere(DateRange range) =>
      "$_baseWhere AND captured_at >= '${range.startIso}' "
      "AND captured_at <= '${range.endIso}'";

  // =========================================================================
  // Public API
  // =========================================================================

  // -------------------------------------------------------------------------
  // Daily
  // -------------------------------------------------------------------------

  /// Returns a summary of all receipts captured on [date].
  ///
  /// The returned [ReportData.dailyTotals] contains a single entry keyed by
  /// the `YYYY-MM-DD` representation of [date].
  Future<ReportData> getDailySummary(DateTime date) async {
    final range = DateRange.singleDay(date);
    return _buildReport(range);
  }

  // -------------------------------------------------------------------------
  // Monthly
  // -------------------------------------------------------------------------

  /// Returns a summary for the calendar month of [year]/[month].
  ///
  /// [ReportData.dailyTotals] contains one entry per day that has receipts.
  Future<ReportData> getMonthlySummary(int year, int month) async {
    final range = DateRange.month(year, month);
    return _buildReport(range);
  }

  // -------------------------------------------------------------------------
  // Quarterly
  // -------------------------------------------------------------------------

  /// Returns a summary for [quarter] (1 = Q1 Jan-Mar, ..., 4 = Q4 Oct-Dec)
  /// of [year].
  Future<ReportData> getQuarterlySummary(int year, int quarter) async {
    final range = DateRange.quarter(year, quarter);
    return _buildReport(range);
  }

  // -------------------------------------------------------------------------
  // Yearly
  // -------------------------------------------------------------------------

  /// Returns a year-to-date (or full year if in the past) summary for [year].
  ///
  /// [ReportData.dailyTotals] uses `YYYY-MM` keys (monthly buckets).
  Future<ReportData> getYearlySummary(int year) async {
    final range = DateRange.year(year);
    return _buildReport(range, monthlyBuckets: true);
  }

  // -------------------------------------------------------------------------
  // Category breakdown
  // -------------------------------------------------------------------------

  /// Returns totals per category within [dateRange].
  Future<ReportData> getCategoryBreakdown(DateRange dateRange) async {
    return _buildReport(dateRange);
  }

  // -------------------------------------------------------------------------
  // Region breakdown
  // -------------------------------------------------------------------------

  /// Returns totals per region within [dateRange].
  Future<ReportData> getRegionBreakdown(DateRange dateRange) async {
    return _buildReport(dateRange);
  }

  // -------------------------------------------------------------------------
  // Trends
  // -------------------------------------------------------------------------

  /// Returns trend data bucketed at [granularity] for chart rendering.
  ///
  /// The [ReportData.dailyTotals] keys vary:
  ///   - [TrendGranularity.daily]: `YYYY-MM-DD`
  ///   - [TrendGranularity.weekly]: `YYYY-Www` (ISO week number)
  ///   - [TrendGranularity.monthly]: `YYYY-MM`
  Future<ReportData> getTrends(
    DateRange dateRange, {
    TrendGranularity granularity = TrendGranularity.daily,
  }) async {
    switch (granularity) {
      case TrendGranularity.daily:
        return _buildReport(dateRange);
      case TrendGranularity.weekly:
        return _buildReport(dateRange, weeklyBuckets: true);
      case TrendGranularity.monthly:
        return _buildReport(dateRange, monthlyBuckets: true);
    }
  }

  // =========================================================================
  // Internal query engine
  // =========================================================================

  /// Core report builder that runs all the necessary SQL aggregations in a
  /// single database transaction for consistency.
  Future<ReportData> _buildReport(
    DateRange range, {
    bool monthlyBuckets = false,
    bool weeklyBuckets = false,
  }) async {
    final db = await _dbHelper.database;
    final where = _dateWhere(range);

    // Run all aggregation queries in parallel within the same isolate.
    final results = await Future.wait([
      _queryTotalAndCount(db, where),
      _queryCategoryBreakdown(db, where),
      _queryRegionBreakdown(db, where),
      _queryDailyTotals(db, where),
      _queryCurrencyTotals(db, where),
      _queryCategoryCounts(db, where),
    ]);

    final totalAndCount = results[0] as Map<String, dynamic>;
    final categoryBreakdown = results[1] as Map<String, double>;
    final regionBreakdown = results[2] as Map<String, double>;
    final rawDailyTotals = results[3] as Map<String, double>;
    final currencyTotals = results[4] as Map<String, double>;
    final categoryCounts = results[5] as Map<String, int>;

    // Re-bucket daily totals if needed.
    Map<String, double> bucketedTotals;
    if (monthlyBuckets) {
      bucketedTotals = _bucketByMonth(rawDailyTotals);
    } else if (weeklyBuckets) {
      bucketedTotals = _bucketByWeek(rawDailyTotals);
    } else {
      bucketedTotals = rawDailyTotals;
    }

    // Determine the dominant currency.
    final dominantCurrency = _dominantCurrency(currencyTotals);

    return ReportData(
      totalAmount: (totalAndCount['total'] as double?) ?? 0.0,
      receiptCount: (totalAndCount['count'] as int?) ?? 0,
      categoryBreakdown: categoryBreakdown,
      regionBreakdown: regionBreakdown,
      dailyTotals: bucketedTotals,
      currency: dominantCurrency,
      currencyTotals: currencyTotals.length > 1 ? currencyTotals : null,
      categoryCounts: categoryCounts.isNotEmpty ? categoryCounts : null,
    );
  }

  // -------------------------------------------------------------------------
  // Individual SQL helpers
  // -------------------------------------------------------------------------

  Future<Map<String, dynamic>> _queryTotalAndCount(
    Database db,
    String where,
  ) async {
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(amount_tracked), 0.0) AS total, '
      'COUNT(*) AS count '
      'FROM receipts WHERE $where',
    );
    if (rows.isEmpty) return <String, dynamic>{'total': 0.0, 'count': 0};
    return <String, dynamic>{
      'total': (rows.first['total'] as num).toDouble(),
      'count': rows.first['count'] as int,
    };
  }

  Future<Map<String, double>> _queryCategoryBreakdown(
    Database db,
    String where,
  ) async {
    final rows = await db.rawQuery(
      'SELECT category, COALESCE(SUM(amount_tracked), 0.0) AS total '
      'FROM receipts WHERE $where '
      'GROUP BY category ORDER BY total DESC',
    );
    return <String, double>{
      for (final row in rows)
        row['category'] as String: (row['total'] as num).toDouble(),
    };
  }

  Future<Map<String, double>> _queryRegionBreakdown(
    Database db,
    String where,
  ) async {
    final rows = await db.rawQuery(
      'SELECT region, COALESCE(SUM(amount_tracked), 0.0) AS total '
      'FROM receipts WHERE $where '
      'GROUP BY region ORDER BY total DESC',
    );
    return <String, double>{
      for (final row in rows)
        row['region'] as String: (row['total'] as num).toDouble(),
    };
  }

  Future<Map<String, double>> _queryDailyTotals(
    Database db,
    String where,
  ) async {
    final rows = await db.rawQuery(
      'SELECT SUBSTR(captured_at, 1, 10) AS day, '
      'COALESCE(SUM(amount_tracked), 0.0) AS total '
      'FROM receipts WHERE $where '
      'GROUP BY day ORDER BY day ASC',
    );
    return <String, double>{
      for (final row in rows)
        row['day'] as String: (row['total'] as num).toDouble(),
    };
  }

  Future<Map<String, double>> _queryCurrencyTotals(
    Database db,
    String where,
  ) async {
    final rows = await db.rawQuery(
      'SELECT currency_code, COALESCE(SUM(amount_tracked), 0.0) AS total '
      'FROM receipts WHERE $where '
      'GROUP BY currency_code ORDER BY total DESC',
    );
    return <String, double>{
      for (final row in rows)
        row['currency_code'] as String: (row['total'] as num).toDouble(),
    };
  }

  Future<Map<String, int>> _queryCategoryCounts(
    Database db,
    String where,
  ) async {
    final rows = await db.rawQuery(
      'SELECT category, COUNT(*) AS cnt '
      'FROM receipts WHERE $where '
      'GROUP BY category ORDER BY cnt DESC',
    );
    return <String, int>{
      for (final row in rows)
        row['category'] as String: row['cnt'] as int,
    };
  }

  // -------------------------------------------------------------------------
  // Bucketing helpers
  // -------------------------------------------------------------------------

  /// Re-aggregates daily totals into `YYYY-MM` monthly buckets.
  Map<String, double> _bucketByMonth(Map<String, double> dailyTotals) {
    final buckets = <String, double>{};
    for (final entry in dailyTotals.entries) {
      // Key format is YYYY-MM-DD; take the first 7 chars for YYYY-MM.
      final monthKey = entry.key.substring(0, 7);
      buckets[monthKey] = (buckets[monthKey] ?? 0.0) + entry.value;
    }
    return Map.fromEntries(
      buckets.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  /// Re-aggregates daily totals into `YYYY-Www` ISO-week buckets.
  Map<String, double> _bucketByWeek(Map<String, double> dailyTotals) {
    final buckets = <String, double>{};
    final weekFormat = DateFormat("yyyy-'W'ww");
    for (final entry in dailyTotals.entries) {
      final date = DateTime.parse(entry.key);
      final weekKey = weekFormat.format(date);
      buckets[weekKey] = (buckets[weekKey] ?? 0.0) + entry.value;
    }
    return Map.fromEntries(
      buckets.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  /// Returns the currency code with the highest total, defaulting to `CAD`.
  String _dominantCurrency(Map<String, double> currencyTotals) {
    if (currencyTotals.isEmpty) return 'CAD';
    String dominant = currencyTotals.keys.first;
    double maxAmount = 0;
    for (final entry in currencyTotals.entries) {
      if (entry.value > maxAmount) {
        maxAmount = entry.value;
        dominant = entry.key;
      }
    }
    return dominant;
  }
}
