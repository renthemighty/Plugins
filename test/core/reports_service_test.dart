/// Tests for the Kira ReportsService.
///
/// Since ReportsService runs SQL queries against a real SQLite database, these
/// tests use an in-memory database (via sqflite_common_ffi) to validate
/// aggregation logic end-to-end: daily summaries, monthly totals, quarterly
/// and yearly aggregation, category/region breakdowns, empty ranges, and
/// currency-aware splitting.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kira/core/db/database_helper.dart';
import 'package:kira/core/services/reports_service.dart';

// ---------------------------------------------------------------------------
// Test infrastructure
// ---------------------------------------------------------------------------

/// Opens a fresh in-memory database with the Kira schema and injects it into
/// the shared [DatabaseHelper] singleton so that [ReportsService] queries hit
/// the test database.
Future<Database> _openTestDatabase() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE receipts (
            receipt_id          TEXT PRIMARY KEY,
            captured_at         TEXT NOT NULL,
            timezone            TEXT NOT NULL,
            filename            TEXT NOT NULL,
            amount_tracked      REAL NOT NULL,
            currency_code       TEXT NOT NULL,
            country             TEXT NOT NULL,
            region              TEXT NOT NULL,
            category            TEXT NOT NULL,
            notes               TEXT,
            tax_applicable      INTEGER,
            checksum_sha256     TEXT NOT NULL,
            device_id           TEXT NOT NULL,
            capture_session_id  TEXT NOT NULL,
            source              TEXT NOT NULL DEFAULT 'camera',
            created_at          TEXT NOT NULL,
            updated_at          TEXT NOT NULL,
            conflict            INTEGER NOT NULL DEFAULT 0,
            supersedes_filename TEXT,
            sync_status         TEXT NOT NULL DEFAULT 'local',
            uploaded_at         TEXT,
            indexed_at          TEXT,
            local_path          TEXT,
            remote_path         TEXT,
            expired             INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
    ),
  );

  DatabaseHelper.instance.setTestDatabase(db);
  return db;
}

/// Inserts a minimal receipt row. Only the fields that matter for report
/// aggregation are required; all others use deterministic defaults.
Future<void> _insertReceipt(
  Database db, {
  required String id,
  required String capturedAt,
  required double amount,
  String currency = 'CAD',
  String category = 'meals',
  String region = 'ON',
  String country = 'canada',
  int expired = 0,
}) async {
  await db.insert('receipts', {
    'receipt_id': id,
    'captured_at': capturedAt,
    'timezone': 'America/Toronto',
    'filename': '${capturedAt.substring(0, 10).replaceAll('-', '')}_$id.jpg',
    'amount_tracked': amount,
    'currency_code': currency,
    'country': country,
    'region': region,
    'category': category,
    'checksum_sha256': 'deadbeef' * 8,
    'device_id': 'test-device',
    'capture_session_id': 'test-session',
    'source': 'camera',
    'created_at': '${capturedAt}Z',
    'updated_at': '${capturedAt}Z',
    'conflict': 0,
    'sync_status': 'local',
    'expired': expired,
  });
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late Database db;
  late ReportsService service;

  setUp(() async {
    db = await _openTestDatabase();
    service = ReportsService();
  });

  tearDown(() async {
    await db.close();
    await DatabaseHelper.instance.close();
  });

  group('ReportsService', () {
    // ---------------------------------------------------------------------
    // Daily summary
    // ---------------------------------------------------------------------

    group('getDailySummary', () {
      test('aggregates multiple receipts for the same day', () async {
        await _insertReceipt(db,
            id: 'r1', capturedAt: '2025-06-14T09:00:00', amount: 10.00,
            category: 'meals', region: 'ON');
        await _insertReceipt(db,
            id: 'r2', capturedAt: '2025-06-14T12:30:00', amount: 25.50,
            category: 'transport', region: 'ON');
        await _insertReceipt(db,
            id: 'r3', capturedAt: '2025-06-14T18:00:00', amount: 14.50,
            category: 'meals', region: 'BC');

        final report = await service.getDailySummary(DateTime(2025, 6, 14));

        expect(report.totalAmount, closeTo(50.00, 0.01));
        expect(report.receiptCount, 3);
      });

      test('provides correct category breakdown', () async {
        await _insertReceipt(db,
            id: 'r1', capturedAt: '2025-06-14T09:00:00', amount: 10.00,
            category: 'meals');
        await _insertReceipt(db,
            id: 'r2', capturedAt: '2025-06-14T12:00:00', amount: 20.00,
            category: 'transport');
        await _insertReceipt(db,
            id: 'r3', capturedAt: '2025-06-14T13:00:00', amount: 5.00,
            category: 'meals');

        final report = await service.getDailySummary(DateTime(2025, 6, 14));

        expect(report.categoryBreakdown['meals'], closeTo(15.00, 0.01));
        expect(report.categoryBreakdown['transport'], closeTo(20.00, 0.01));
      });

      test('provides correct region breakdown', () async {
        await _insertReceipt(db,
            id: 'r1', capturedAt: '2025-06-14T09:00:00', amount: 30.00,
            region: 'ON');
        await _insertReceipt(db,
            id: 'r2', capturedAt: '2025-06-14T10:00:00', amount: 20.00,
            region: 'BC');
        await _insertReceipt(db,
            id: 'r3', capturedAt: '2025-06-14T11:00:00', amount: 10.00,
            region: 'ON');

        final report = await service.getDailySummary(DateTime(2025, 6, 14));

        expect(report.regionBreakdown['ON'], closeTo(40.00, 0.01));
        expect(report.regionBreakdown['BC'], closeTo(20.00, 0.01));
      });

      test('excludes expired receipts from totals', () async {
        await _insertReceipt(db,
            id: 'r1', capturedAt: '2025-06-14T09:00:00', amount: 100.00);
        await _insertReceipt(db,
            id: 'r2', capturedAt: '2025-06-14T10:00:00', amount: 50.00,
            expired: 1);

        final report = await service.getDailySummary(DateTime(2025, 6, 14));

        expect(report.totalAmount, closeTo(100.00, 0.01));
        expect(report.receiptCount, 1);
      });

      test('does not include receipts from adjacent days', () async {
        await _insertReceipt(db,
            id: 'r1', capturedAt: '2025-06-13T23:59:59', amount: 100.00);
        await _insertReceipt(db,
            id: 'r2', capturedAt: '2025-06-14T08:00:00', amount: 25.00);
        await _insertReceipt(db,
            id: 'r3', capturedAt: '2025-06-15T00:00:01', amount: 200.00);

        final report = await service.getDailySummary(DateTime(2025, 6, 14));

        expect(report.totalAmount, closeTo(25.00, 0.01));
        expect(report.receiptCount, 1);
      });
    });

    // ---------------------------------------------------------------------
    // Monthly summary
    // ---------------------------------------------------------------------

    group('getMonthlySummary', () {
      test('aggregates receipts across the full month by day', () async {
        await _insertReceipt(db,
            id: 'r1', capturedAt: '2025-06-01T10:00:00', amount: 10.00);
        await _insertReceipt(db,
            id: 'r2', capturedAt: '2025-06-15T10:00:00', amount: 20.00);
        await _insertReceipt(db,
            id: 'r3', capturedAt: '2025-06-30T10:00:00', amount: 30.00);

        final report = await service.getMonthlySummary(2025, 6);

        expect(report.totalAmount, closeTo(60.00, 0.01));
        expect(report.receiptCount, 3);
        expect(report.dailyTotals.length, 3);
        expect(report.dailyTotals['2025-06-01'], closeTo(10.00, 0.01));
        expect(report.dailyTotals['2025-06-15'], closeTo(20.00, 0.01));
        expect(report.dailyTotals['2025-06-30'], closeTo(30.00, 0.01));
      });

      test('provides category breakdown for the full month', () async {
        await _insertReceipt(db,
            id: 'r1', capturedAt: '2025-06-05T10:00:00', amount: 15.00,
            category: 'office');
        await _insertReceipt(db,
            id: 'r2', capturedAt: '2025-06-20T10:00:00', amount: 35.00,
            category: 'travel');
        await _insertReceipt(db,
            id: 'r3', capturedAt: '2025-06-25T10:00:00', amount: 10.00,
            category: 'office');

        final report = await service.getMonthlySummary(2025, 6);

        expect(report.categoryBreakdown['office'], closeTo(25.00, 0.01));
        expect(report.categoryBreakdown['travel'], closeTo(35.00, 0.01));
      });

      test('does not include receipts from outside the month', () async {
        await _insertReceipt(db,
            id: 'r0', capturedAt: '2025-05-31T23:59:59', amount: 999.99);
        await _insertReceipt(db,
            id: 'r1', capturedAt: '2025-06-01T00:00:01', amount: 10.00);
        await _insertReceipt(db,
            id: 'r2', capturedAt: '2025-07-01T00:00:01', amount: 888.88);

        final report = await service.getMonthlySummary(2025, 6);

        expect(report.totalAmount, closeTo(10.00, 0.01));
        expect(report.receiptCount, 1);
      });
    });

    // ---------------------------------------------------------------------
    // Quarterly summary
    // ---------------------------------------------------------------------

    group('getQuarterlySummary', () {
      test('Q1 covers January through March', () async {
        await _insertReceipt(db,
            id: 'r1', capturedAt: '2025-01-15T10:00:00', amount: 100.00);
        await _insertReceipt(db,
            id: 'r2', capturedAt: '2025-02-15T10:00:00', amount: 200.00);
        await _insertReceipt(db,
            id: 'r3', capturedAt: '2025-03-15T10:00:00', amount: 300.00);
        // Q2 - should be excluded.
        await _insertReceipt(db,
            id: 'r4', capturedAt: '2025-04-01T10:00:00', amount: 999.00);

        final report = await service.getQuarterlySummary(2025, 1);

        expect(report.totalAmount, closeTo(600.00, 0.01));
        expect(report.receiptCount, 3);
      });

      test('Q2 covers April through June', () async {
        await _insertReceipt(db,
            id: 'r1', capturedAt: '2025-04-01T10:00:00', amount: 50.00);
        await _insertReceipt(db,
            id: 'r2', capturedAt: '2025-06-30T23:00:00', amount: 50.00);

        final report = await service.getQuarterlySummary(2025, 2);

        expect(report.totalAmount, closeTo(100.00, 0.01));
        expect(report.receiptCount, 2);
      });

      test('Q3 covers July through September', () async {
        await _insertReceipt(db,
            id: 'r1', capturedAt: '2025-07-10T10:00:00', amount: 75.00);
        await _insertReceipt(db,
            id: 'r2', capturedAt: '2025-09-28T10:00:00', amount: 25.00);

        final report = await service.getQuarterlySummary(2025, 3);

        expect(report.totalAmount, closeTo(100.00, 0.01));
        expect(report.receiptCount, 2);
      });

      test('Q4 covers October through December', () async {
        await _insertReceipt(db,
            id: 'r1', capturedAt: '2025-10-01T10:00:00', amount: 40.00);
        await _insertReceipt(db,
            id: 'r2', capturedAt: '2025-12-31T22:00:00', amount: 60.00);

        final report = await service.getQuarterlySummary(2025, 4);

        expect(report.totalAmount, closeTo(100.00, 0.01));
        expect(report.receiptCount, 2);
      });
    });

    // ---------------------------------------------------------------------
    // Yearly summary
    // ---------------------------------------------------------------------

    group('getYearlySummary', () {
      test('aggregates all receipts within the calendar year', () async {
        await _insertReceipt(db,
            id: 'r1', capturedAt: '2025-01-01T00:00:01', amount: 100.00);
        await _insertReceipt(db,
            id: 'r2', capturedAt: '2025-06-15T10:00:00', amount: 200.00);
        await _insertReceipt(db,
            id: 'r3', capturedAt: '2025-12-31T23:00:00', amount: 300.00);
        // Different year - excluded.
        await _insertReceipt(db,
            id: 'r4', capturedAt: '2024-12-31T23:59:59', amount: 999.00);

        final report = await service.getYearlySummary(2025);

        expect(report.totalAmount, closeTo(600.00, 0.01));
        expect(report.receiptCount, 3);
      });

      test('uses monthly buckets for dailyTotals', () async {
        await _insertReceipt(db,
            id: 'r1', capturedAt: '2025-01-10T10:00:00', amount: 10.00);
        await _insertReceipt(db,
            id: 'r2', capturedAt: '2025-01-20T10:00:00', amount: 20.00);
        await _insertReceipt(db,
            id: 'r3', capturedAt: '2025-06-15T10:00:00', amount: 50.00);

        final report = await service.getYearlySummary(2025);

        // Daily totals should be bucketed by YYYY-MM.
        expect(report.dailyTotals.containsKey('2025-01'), isTrue);
        expect(report.dailyTotals['2025-01'], closeTo(30.00, 0.01));
        expect(report.dailyTotals['2025-06'], closeTo(50.00, 0.01));
      });
    });

    // ---------------------------------------------------------------------
    // Category breakdown
    // ---------------------------------------------------------------------

    group('getCategoryBreakdown', () {
      test('returns accurate totals per category', () async {
        await _insertReceipt(db,
            id: 'r1', capturedAt: '2025-06-14T10:00:00', amount: 12.00,
            category: 'meals');
        await _insertReceipt(db,
            id: 'r2', capturedAt: '2025-06-14T11:00:00', amount: 8.00,
            category: 'transport');
        await _insertReceipt(db,
            id: 'r3', capturedAt: '2025-06-14T12:00:00', amount: 30.00,
            category: 'meals');
        await _insertReceipt(db,
            id: 'r4', capturedAt: '2025-06-14T13:00:00', amount: 5.50,
            category: 'office');

        final range = DateRange.singleDay(DateTime(2025, 6, 14));
        final report = await service.getCategoryBreakdown(range);

        expect(report.categoryBreakdown['meals'], closeTo(42.00, 0.01));
        expect(report.categoryBreakdown['transport'], closeTo(8.00, 0.01));
        expect(report.categoryBreakdown['office'], closeTo(5.50, 0.01));
        expect(report.categoryBreakdown.length, 3);
      });

      test('category counts are provided', () async {
        await _insertReceipt(db,
            id: 'r1', capturedAt: '2025-06-14T10:00:00', amount: 10.00,
            category: 'meals');
        await _insertReceipt(db,
            id: 'r2', capturedAt: '2025-06-14T11:00:00', amount: 20.00,
            category: 'meals');
        await _insertReceipt(db,
            id: 'r3', capturedAt: '2025-06-14T12:00:00', amount: 30.00,
            category: 'transport');

        final range = DateRange.singleDay(DateTime(2025, 6, 14));
        final report = await service.getCategoryBreakdown(range);

        expect(report.categoryCounts, isNotNull);
        expect(report.categoryCounts!['meals'], 2);
        expect(report.categoryCounts!['transport'], 1);
      });
    });

    // ---------------------------------------------------------------------
    // Region breakdown
    // ---------------------------------------------------------------------

    group('getRegionBreakdown', () {
      test('returns accurate totals per region', () async {
        await _insertReceipt(db,
            id: 'r1', capturedAt: '2025-06-14T10:00:00', amount: 50.00,
            region: 'ON');
        await _insertReceipt(db,
            id: 'r2', capturedAt: '2025-06-14T11:00:00', amount: 30.00,
            region: 'BC');
        await _insertReceipt(db,
            id: 'r3', capturedAt: '2025-06-14T12:00:00', amount: 20.00,
            region: 'ON');

        final range = DateRange.singleDay(DateTime(2025, 6, 14));
        final report = await service.getRegionBreakdown(range);

        expect(report.regionBreakdown['ON'], closeTo(70.00, 0.01));
        expect(report.regionBreakdown['BC'], closeTo(30.00, 0.01));
        expect(report.regionBreakdown.length, 2);
      });
    });

    // ---------------------------------------------------------------------
    // Empty date range
    // ---------------------------------------------------------------------

    group('empty date range', () {
      test('returns zeroed report when no receipts exist', () async {
        final report = await service.getDailySummary(DateTime(2025, 6, 14));

        expect(report.totalAmount, 0.0);
        expect(report.receiptCount, 0);
        expect(report.categoryBreakdown, isEmpty);
        expect(report.regionBreakdown, isEmpty);
        expect(report.dailyTotals, isEmpty);
      });

      test('returns zeroed report for a month with no data', () async {
        // Insert into a different month.
        await _insertReceipt(db,
            id: 'r1', capturedAt: '2025-05-14T10:00:00', amount: 100.00);

        final report = await service.getMonthlySummary(2025, 6);

        expect(report.totalAmount, 0.0);
        expect(report.receiptCount, 0);
      });

      test('returns zeroed report for a year with no data', () async {
        await _insertReceipt(db,
            id: 'r1', capturedAt: '2024-12-31T10:00:00', amount: 100.00);

        final report = await service.getYearlySummary(2025);

        expect(report.totalAmount, 0.0);
        expect(report.receiptCount, 0);
      });

      test('currency defaults to CAD when no receipts present', () async {
        final report = await service.getDailySummary(DateTime(2025, 6, 14));

        expect(report.currency, 'CAD');
      });
    });

    // ---------------------------------------------------------------------
    // Currency-aware aggregation
    // ---------------------------------------------------------------------

    group('currency-aware aggregation', () {
      test('keeps CAD and USD totals separate in currencyTotals', () async {
        await _insertReceipt(db,
            id: 'r1', capturedAt: '2025-06-14T10:00:00', amount: 50.00,
            currency: 'CAD');
        await _insertReceipt(db,
            id: 'r2', capturedAt: '2025-06-14T11:00:00', amount: 30.00,
            currency: 'USD');
        await _insertReceipt(db,
            id: 'r3', capturedAt: '2025-06-14T12:00:00', amount: 20.00,
            currency: 'CAD');

        final report = await service.getDailySummary(DateTime(2025, 6, 14));

        // When multiple currencies exist, currencyTotals must be populated.
        expect(report.currencyTotals, isNotNull);
        expect(report.currencyTotals!['CAD'], closeTo(70.00, 0.01));
        expect(report.currencyTotals!['USD'], closeTo(30.00, 0.01));
      });

      test('dominant currency is the one with the highest total', () async {
        await _insertReceipt(db,
            id: 'r1', capturedAt: '2025-06-14T10:00:00', amount: 100.00,
            currency: 'USD');
        await _insertReceipt(db,
            id: 'r2', capturedAt: '2025-06-14T11:00:00', amount: 50.00,
            currency: 'CAD');

        final report = await service.getDailySummary(DateTime(2025, 6, 14));

        expect(report.currency, 'USD');
      });

      test('currencyTotals is null when only one currency is present',
          () async {
        await _insertReceipt(db,
            id: 'r1', capturedAt: '2025-06-14T10:00:00', amount: 25.00,
            currency: 'CAD');
        await _insertReceipt(db,
            id: 'r2', capturedAt: '2025-06-14T11:00:00', amount: 75.00,
            currency: 'CAD');

        final report = await service.getDailySummary(DateTime(2025, 6, 14));

        expect(report.currencyTotals, isNull);
        expect(report.currency, 'CAD');
      });

      test('totalAmount sums all currencies together', () async {
        await _insertReceipt(db,
            id: 'r1', capturedAt: '2025-06-14T10:00:00', amount: 40.00,
            currency: 'CAD');
        await _insertReceipt(db,
            id: 'r2', capturedAt: '2025-06-14T11:00:00', amount: 60.00,
            currency: 'USD');

        final report = await service.getDailySummary(DateTime(2025, 6, 14));

        // totalAmount is the raw SQL SUM regardless of currency.
        expect(report.totalAmount, closeTo(100.00, 0.01));
      });
    });

    // ---------------------------------------------------------------------
    // DateRange helpers
    // ---------------------------------------------------------------------

    group('DateRange', () {
      test('singleDay creates a range spanning one calendar day', () {
        final range = DateRange.singleDay(DateTime(2025, 6, 14));

        expect(range.start, DateTime(2025, 6, 14));
        expect(range.end.year, 2025);
        expect(range.end.month, 6);
        expect(range.end.day, 14);
        expect(range.end.hour, 23);
        expect(range.end.minute, 59);
      });

      test('month creates a range spanning the full calendar month', () {
        final range = DateRange.month(2025, 2);

        expect(range.start, DateTime(2025, 2, 1));
        expect(range.end.day, 28); // non-leap year
      });

      test('quarter Q1 spans Jan 1 to Mar 31', () {
        final range = DateRange.quarter(2025, 1);

        expect(range.start.month, 1);
        expect(range.start.day, 1);
        expect(range.end.month, 3);
        expect(range.end.day, 31);
      });

      test('year spans Jan 1 to Dec 31', () {
        final range = DateRange.year(2025);

        expect(range.start, DateTime(2025, 1, 1));
        expect(range.end.month, 12);
        expect(range.end.day, 31);
      });
    });

    // ---------------------------------------------------------------------
    // ReportData model
    // ---------------------------------------------------------------------

    group('ReportData', () {
      test('empty constant has zeroed fields', () {
        expect(ReportData.empty.totalAmount, 0.0);
        expect(ReportData.empty.receiptCount, 0);
        expect(ReportData.empty.categoryBreakdown, isEmpty);
        expect(ReportData.empty.regionBreakdown, isEmpty);
        expect(ReportData.empty.dailyTotals, isEmpty);
        expect(ReportData.empty.currency, 'CAD');
      });

      test('toString includes amount, currency, and receipt count', () {
        const report = ReportData(
          totalAmount: 123.45,
          receiptCount: 7,
          currency: 'USD',
        );
        final str = report.toString();

        expect(str, contains('123.45'));
        expect(str, contains('USD'));
        expect(str, contains('7'));
      });
    });
  });
}
