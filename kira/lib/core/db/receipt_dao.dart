/// Data-access object for the `receipts` table.
///
/// Follows the Kira "no-overwrite" policy: once a receipt row is inserted
/// its core fields are immutable.  Only sync-lifecycle columns
/// (`sync_status`, `uploaded_at`, `indexed_at`, `remote_path`, `expired`)
/// may be updated after creation.
library;

import 'package:sqflite/sqflite.dart';

import '../models/receipt.dart';
import 'database_helper.dart';

class ReceiptDao {
  final DatabaseHelper _dbHelper;

  ReceiptDao([DatabaseHelper? helper]) : _dbHelper = helper ?? DatabaseHelper();

  Future<Database> get _db => _dbHelper.database;

  // ---------------------------------------------------------------------------
  // Insert
  // ---------------------------------------------------------------------------

  /// Inserts a receipt **only if** no row with the same `receipt_id` exists.
  ///
  /// Returns `true` when a new row was created, `false` when the receipt
  /// already existed (Kira never overwrites receipt data).
  Future<bool> insert(Receipt receipt, {String? localPath}) async {
    final db = await _db;
    final existing = await db.query(
      'receipts',
      columns: ['receipt_id'],
      where: 'receipt_id = ?',
      whereArgs: [receipt.receiptId],
      limit: 1,
    );

    if (existing.isNotEmpty) return false;

    final row = receipt.toMap();
    if (localPath != null) {
      row['local_path'] = localPath;
    }
    // Ensure sync-lifecycle defaults are present.
    row.putIfAbsent('sync_status', () => 'local');
    row.putIfAbsent('expired', () => 0);

    await db.insert('receipts', row);
    return true;
  }

  // ---------------------------------------------------------------------------
  // Single-record lookups
  // ---------------------------------------------------------------------------

  /// Returns the receipt matching [receiptId], or `null` if not found.
  Future<Receipt?> getById(String receiptId) async {
    final db = await _db;
    final rows = await db.query(
      'receipts',
      where: 'receipt_id = ?',
      whereArgs: [receiptId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Receipt.fromMap(rows.first);
  }

  // ---------------------------------------------------------------------------
  // Date-based queries
  // ---------------------------------------------------------------------------

  /// Returns receipts whose `captured_at` starts with [dateString]
  /// (e.g. `"2025-06-14"`).
  Future<List<Receipt>> getByDate(String dateString) async {
    final db = await _db;
    final rows = await db.query(
      'receipts',
      where: 'captured_at LIKE ?',
      whereArgs: ['$dateString%'],
      orderBy: 'captured_at DESC',
    );
    return rows.map(Receipt.fromMap).toList();
  }

  /// Returns receipts captured between [startDate] (inclusive) and [endDate]
  /// (exclusive).  Both parameters should be ISO-8601 date strings
  /// (e.g. `"2025-06-01"`).
  Future<List<Receipt>> getByDateRange(
    String startDate,
    String endDate,
  ) async {
    final db = await _db;
    final rows = await db.query(
      'receipts',
      where: 'captured_at >= ? AND captured_at < ?',
      whereArgs: [startDate, endDate],
      orderBy: 'captured_at DESC',
    );
    return rows.map(Receipt.fromMap).toList();
  }

  /// Alias for [getByDate] -- returns receipts for a specific day.
  Future<List<Receipt>> getReceiptsForDay(String dateString) =>
      getByDate(dateString);

  /// Returns receipts for the given month (format `"YYYY-MM"`).
  Future<List<Receipt>> getReceiptsForMonth(String yearMonth) async {
    final db = await _db;
    final rows = await db.query(
      'receipts',
      where: 'captured_at LIKE ?',
      whereArgs: ['$yearMonth%'],
      orderBy: 'captured_at DESC',
    );
    return rows.map(Receipt.fromMap).toList();
  }

  /// Returns receipts for the given year (format `"YYYY"`).
  Future<List<Receipt>> getReceiptsForYear(String year) async {
    final db = await _db;
    final rows = await db.query(
      'receipts',
      where: 'captured_at LIKE ?',
      whereArgs: ['$year%'],
      orderBy: 'captured_at DESC',
    );
    return rows.map(Receipt.fromMap).toList();
  }

  // ---------------------------------------------------------------------------
  // Filtered queries
  // ---------------------------------------------------------------------------

  /// Returns receipts matching the given [category].
  Future<List<Receipt>> getByCategory(String category) async {
    final db = await _db;
    final rows = await db.query(
      'receipts',
      where: 'category = ?',
      whereArgs: [category],
      orderBy: 'captured_at DESC',
    );
    return rows.map(Receipt.fromMap).toList();
  }

  /// Returns receipts matching the given [region] (province / state code).
  Future<List<Receipt>> getByRegion(String region) async {
    final db = await _db;
    final rows = await db.query(
      'receipts',
      where: 'region = ?',
      whereArgs: [region],
      orderBy: 'captured_at DESC',
    );
    return rows.map(Receipt.fromMap).toList();
  }

  // ---------------------------------------------------------------------------
  // Sync-related queries
  // ---------------------------------------------------------------------------

  /// Returns all receipts whose `sync_status` is `'local'` (never uploaded).
  Future<List<Receipt>> getUnsyncedReceipts() async {
    final db = await _db;
    final rows = await db.query(
      'receipts',
      where: "sync_status = 'local'",
      orderBy: 'captured_at ASC',
    );
    return rows.map(Receipt.fromMap).toList();
  }

  /// Marks a receipt as uploaded.
  Future<void> markSynced(String receiptId, {String? remotePath}) async {
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'receipts',
      {
        'sync_status': 'synced',
        'uploaded_at': now,
        if (remotePath != null) 'remote_path': remotePath,
      },
      where: 'receipt_id = ?',
      whereArgs: [receiptId],
    );
  }

  /// Marks a receipt as indexed (its metadata has been written to the cloud
  /// index file).
  Future<void> markIndexed(String receiptId) async {
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'receipts',
      {
        'sync_status': 'indexed',
        'indexed_at': now,
      },
      where: 'receipt_id = ?',
      whereArgs: [receiptId],
    );
  }

  // ---------------------------------------------------------------------------
  // Trial expiration
  // ---------------------------------------------------------------------------

  /// Returns trial receipts that have expired: captured more than 7 days ago
  /// while the user has **not** upgraded.
  ///
  /// The caller must supply [isUpgraded]; if `true` the method returns an
  /// empty list immediately (upgraded users never have expired receipts).
  Future<List<Receipt>> getExpiredTrialReceipts({
    required bool isUpgraded,
  }) async {
    if (isUpgraded) return [];
    final db = await _db;
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 7))
        .toIso8601String();
    final rows = await db.query(
      'receipts',
      where: 'captured_at < ? AND expired = 0',
      whereArgs: [cutoff],
      orderBy: 'captured_at ASC',
    );
    return rows.map(Receipt.fromMap).toList();
  }

  /// Deletes trial receipts older than 7 days (for non-upgraded users).
  ///
  /// Returns the number of rows deleted.
  Future<int> deleteExpiredTrialReceipts({
    required bool isUpgraded,
  }) async {
    if (isUpgraded) return 0;
    final db = await _db;
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 7))
        .toIso8601String();
    return db.delete(
      'receipts',
      where: 'captured_at < ? AND expired = 0',
      whereArgs: [cutoff],
    );
  }

  // ---------------------------------------------------------------------------
  // Aggregate queries
  // ---------------------------------------------------------------------------

  /// Number of receipts captured on [dateString] (e.g. `"2025-06-14"`).
  Future<int> getCountByDate(String dateString) async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM receipts WHERE captured_at LIKE ?',
      ['$dateString%'],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Sum of `amount_tracked` for receipts captured on [dateString].
  Future<double> getTotalByDate(String dateString) async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(amount_tracked), 0.0) AS total '
      'FROM receipts WHERE captured_at LIKE ?',
      ['$dateString%'],
    );
    final value = result.first['total'];
    if (value is int) return value.toDouble();
    return (value as double?) ?? 0.0;
  }

  /// Sum of `amount_tracked` grouped by category.
  ///
  /// Returns a map of `{ category: totalAmount }`.
  Future<Map<String, double>> getTotalByCategory() async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT category, COALESCE(SUM(amount_tracked), 0.0) AS total '
      'FROM receipts GROUP BY category ORDER BY total DESC',
    );
    final map = <String, double>{};
    for (final row in rows) {
      final category = row['category'] as String;
      final total = row['total'];
      map[category] =
          total is int ? total.toDouble() : (total as double?) ?? 0.0;
    }
    return map;
  }

  /// Sum of `amount_tracked` grouped by region.
  ///
  /// Returns a map of `{ region: totalAmount }`.
  Future<Map<String, double>> getTotalByRegion() async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT region, COALESCE(SUM(amount_tracked), 0.0) AS total '
      'FROM receipts GROUP BY region ORDER BY total DESC',
    );
    final map = <String, double>{};
    for (final row in rows) {
      final region = row['region'] as String;
      final total = row['total'];
      map[region] =
          total is int ? total.toDouble() : (total as double?) ?? 0.0;
    }
    return map;
  }

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  /// Full-text-ish search across date range.
  ///
  /// [startDate] and [endDate] are ISO-8601 date strings.  [endDate] is
  /// exclusive.
  Future<List<Receipt>> searchByDateRange(
    String startDate,
    String endDate,
  ) =>
      getByDateRange(startDate, endDate);

  // ---------------------------------------------------------------------------
  // Backfill helpers
  // ---------------------------------------------------------------------------

  /// Returns every receipt with `sync_status = 'local'` — i.e. receipts that
  /// were captured before the user connected a cloud storage provider.
  Future<List<Receipt>> getAllLocal() async {
    final db = await _db;
    final rows = await db.query(
      'receipts',
      where: "sync_status = 'local'",
      orderBy: 'captured_at ASC',
    );
    return rows.map(Receipt.fromMap).toList();
  }

  /// Returns the count and the cumulative on-disk size (in bytes) of all
  /// local-only receipts.
  ///
  /// The size is estimated from `local_path` — if a path is `null` the
  /// receipt is excluded from the byte count.  (Actual file-system stat is
  /// done by the caller to keep the DAO layer free of `dart:io`.)
  Future<({int count, List<String> localPaths})>
      getReceiptCountAndSize() async {
    final db = await _db;
    final rows = await db.query(
      'receipts',
      columns: ['local_path'],
      where: "sync_status = 'local'",
    );
    final paths = <String>[];
    for (final row in rows) {
      final path = row['local_path'] as String?;
      if (path != null && path.isNotEmpty) {
        paths.add(path);
      }
    }
    return (count: rows.length, localPaths: paths);
  }

  // ---------------------------------------------------------------------------
  // Bulk / listing
  // ---------------------------------------------------------------------------

  /// Returns all receipts, ordered by capture time descending.
  Future<List<Receipt>> getAll() async {
    final db = await _db;
    final rows = await db.query(
      'receipts',
      orderBy: 'captured_at DESC',
    );
    return rows.map(Receipt.fromMap).toList();
  }

  /// Returns the total number of receipts in the database.
  Future<int> getTotalCount() async {
    final db = await _db;
    final result =
        await db.rawQuery('SELECT COUNT(*) AS cnt FROM receipts');
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
