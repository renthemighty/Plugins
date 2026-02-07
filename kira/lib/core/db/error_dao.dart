/// Data-access object for the `error_records` table.
///
/// Every unhandled exception or notable failure in the app is persisted here
/// so that:
///   1. The admin panel can surface error metrics.
///   2. The support team can export a CSV of recent errors for diagnosis.
///   3. Resolved vs. unresolved errors can be tracked over time.
library;

import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';

// ---------------------------------------------------------------------------
// Well-known error types
// ---------------------------------------------------------------------------

/// Suggested `error_type` values.  Callers may use arbitrary strings, but
/// these constants cover the most common categories.
abstract final class ErrorType {
  static const String upload = 'upload';
  static const String download = 'download';
  static const String integrity = 'integrity';
  static const String database = 'database';
  static const String camera = 'camera';
  static const String auth = 'auth';
  static const String sync = 'sync';
  static const String network = 'network';
  static const String unknown = 'unknown';
}

// ---------------------------------------------------------------------------
// Value object
// ---------------------------------------------------------------------------

class ErrorRecord {
  final int? id;
  final String errorType;
  final String message;
  final String? stackTrace;
  final String? context;
  final String? deviceId;
  final String? appVersion;
  final bool resolved;
  final String createdAt;

  const ErrorRecord({
    this.id,
    required this.errorType,
    required this.message,
    this.stackTrace,
    this.context,
    this.deviceId,
    this.appVersion,
    this.resolved = false,
    required this.createdAt,
  });

  factory ErrorRecord.fromMap(Map<String, dynamic> map) {
    return ErrorRecord(
      id: map['id'] as int?,
      errorType: map['error_type'] as String,
      message: map['message'] as String,
      stackTrace: map['stack_trace'] as String?,
      context: map['context'] as String?,
      deviceId: map['device_id'] as String?,
      appVersion: map['app_version'] as String?,
      resolved: (map['resolved'] as int? ?? 0) == 1,
      createdAt: map['created_at'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      if (id != null) 'id': id,
      'error_type': errorType,
      'message': message,
      'stack_trace': stackTrace,
      'context': context,
      'device_id': deviceId,
      'app_version': appVersion,
      'resolved': resolved ? 1 : 0,
      'created_at': createdAt,
    };
  }

  @override
  String toString() =>
      'ErrorRecord(id: $id, type: $errorType, resolved: $resolved)';
}

// ---------------------------------------------------------------------------
// DAO
// ---------------------------------------------------------------------------

class ErrorDao {
  final DatabaseHelper _dbHelper;

  ErrorDao([DatabaseHelper? helper]) : _dbHelper = helper ?? DatabaseHelper();

  Future<Database> get _db => _dbHelper.database;

  // ---------------------------------------------------------------------------
  // Create
  // ---------------------------------------------------------------------------

  /// Inserts a new error record.  Returns the auto-generated row id.
  Future<int> insert(ErrorRecord record) async {
    final db = await _db;
    return db.insert('error_records', record.toMap());
  }

  /// Convenience shorthand for logging an error from raw parameters.
  Future<int> logError({
    required String errorType,
    required String message,
    String? stackTrace,
    String? context,
    String? deviceId,
    String? appVersion,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    return insert(ErrorRecord(
      errorType: errorType,
      message: message,
      stackTrace: stackTrace,
      context: context,
      deviceId: deviceId,
      appVersion: appVersion,
      createdAt: now,
    ));
  }

  // ---------------------------------------------------------------------------
  // Read
  // ---------------------------------------------------------------------------

  /// Returns the error with [id], or `null`.
  Future<ErrorRecord?> getById(int id) async {
    final db = await _db;
    final rows = await db.query(
      'error_records',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ErrorRecord.fromMap(rows.first);
  }

  /// Returns all error records, newest first.  Optionally limited to [limit]
  /// rows.
  Future<List<ErrorRecord>> getAll({int? limit}) async {
    final db = await _db;
    final rows = await db.query(
      'error_records',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(ErrorRecord.fromMap).toList();
  }

  /// Returns unresolved errors, newest first.
  Future<List<ErrorRecord>> getUnresolved({int? limit}) async {
    final db = await _db;
    final rows = await db.query(
      'error_records',
      where: 'resolved = 0',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(ErrorRecord.fromMap).toList();
  }

  /// Returns errors of the given [errorType], newest first.
  Future<List<ErrorRecord>> getByType(
    String errorType, {
    int? limit,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'error_records',
      where: 'error_type = ?',
      whereArgs: [errorType],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(ErrorRecord.fromMap).toList();
  }

  /// Returns the total number of error records.
  Future<int> getTotalCount() async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM error_records',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Returns the count of unresolved errors.
  Future<int> getUnresolvedCount() async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM error_records WHERE resolved = 0',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Returns the count of errors grouped by `error_type`.
  Future<Map<String, int>> getCountByType() async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT error_type, COUNT(*) AS cnt FROM error_records '
      'GROUP BY error_type ORDER BY cnt DESC',
    );
    final map = <String, int>{};
    for (final row in rows) {
      map[row['error_type'] as String] = row['cnt'] as int;
    }
    return map;
  }

  /// Returns errors created within the given date range.
  Future<List<ErrorRecord>> getByDateRange(
    String startDate,
    String endDate,
  ) async {
    final db = await _db;
    final rows = await db.query(
      'error_records',
      where: 'created_at >= ? AND created_at < ?',
      whereArgs: [startDate, endDate],
      orderBy: 'created_at DESC',
    );
    return rows.map(ErrorRecord.fromMap).toList();
  }

  // ---------------------------------------------------------------------------
  // Update
  // ---------------------------------------------------------------------------

  /// Marks the error with [id] as resolved.
  Future<void> resolve(int id) async {
    final db = await _db;
    await db.update(
      'error_records',
      {'resolved': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Marks all unresolved errors as resolved.
  Future<int> resolveAll() async {
    final db = await _db;
    return db.update(
      'error_records',
      {'resolved': 1},
      where: 'resolved = 0',
    );
  }

  // ---------------------------------------------------------------------------
  // Delete
  // ---------------------------------------------------------------------------

  /// Deletes a single error record.
  Future<void> delete(int id) async {
    final db = await _db;
    await db.delete('error_records', where: 'id = ?', whereArgs: [id]);
  }

  /// Deletes resolved error records older than [before] (ISO-8601 string).
  Future<int> deleteResolvedBefore(String before) async {
    final db = await _db;
    return db.delete(
      'error_records',
      where: 'resolved = 1 AND created_at < ?',
      whereArgs: [before],
    );
  }

  /// Deletes all error records.  Intended for development / admin use.
  Future<int> deleteAll() async {
    final db = await _db;
    return db.delete('error_records');
  }
}
