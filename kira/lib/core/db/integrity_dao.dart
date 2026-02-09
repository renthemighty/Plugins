/// Data-access object for the `integrity_alerts` table.
///
/// Integrity alerts are created by the background integrity-check service
/// when it detects orphan files, checksum mismatches, filename-format
/// violations, or folder-placement errors.  The UI displays them in the
/// Alerts tab, where the user can dismiss or quarantine the offending item.
library;

import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';

// ---------------------------------------------------------------------------
// Alert-type constants
// ---------------------------------------------------------------------------

/// Well-known `alert_type` values written to the database.
abstract final class IntegrityAlertType {
  static const String orphanFile = 'orphan_file';
  static const String orphanEntry = 'orphan_entry';
  static const String invalidFilename = 'invalid_filename';
  static const String folderMismatch = 'folder_mismatch';
  static const String checksumMismatch = 'checksum_mismatch';
  static const String unexpectedFile = 'unexpected_file';
}

/// Well-known `severity` values.
abstract final class AlertSeverity {
  static const String info = 'info';
  static const String warning = 'warning';
  static const String critical = 'critical';
}

// ---------------------------------------------------------------------------
// Value object
// ---------------------------------------------------------------------------

class IntegrityAlert {
  final int? id;
  final String? receiptId;
  final String alertType;
  final String description;
  final String? filePath;
  final String severity;
  final bool resolved;
  final String createdAt;
  final String? resolvedAt;

  const IntegrityAlert({
    this.id,
    this.receiptId,
    required this.alertType,
    required this.description,
    this.filePath,
    this.severity = AlertSeverity.warning,
    this.resolved = false,
    required this.createdAt,
    this.resolvedAt,
  });

  factory IntegrityAlert.fromMap(Map<String, dynamic> map) {
    return IntegrityAlert(
      id: map['id'] as int?,
      receiptId: map['receipt_id'] as String?,
      alertType: map['alert_type'] as String,
      description: map['description'] as String,
      filePath: map['file_path'] as String?,
      severity: map['severity'] as String? ?? AlertSeverity.warning,
      resolved: (map['resolved'] as int? ?? 0) == 1,
      createdAt: map['created_at'] as String,
      resolvedAt: map['resolved_at'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      if (id != null) 'id': id,
      'receipt_id': receiptId,
      'alert_type': alertType,
      'description': description,
      'file_path': filePath,
      'severity': severity,
      'resolved': resolved ? 1 : 0,
      'created_at': createdAt,
      'resolved_at': resolvedAt,
    };
  }

  @override
  String toString() =>
      'IntegrityAlert(id: $id, type: $alertType, severity: $severity, '
      'resolved: $resolved)';
}

// ---------------------------------------------------------------------------
// DAO
// ---------------------------------------------------------------------------

class IntegrityDao {
  final DatabaseHelper _dbHelper;

  IntegrityDao([DatabaseHelper? helper])
      : _dbHelper = helper ?? DatabaseHelper();

  Future<Database> get _db => _dbHelper.database;

  // ---------------------------------------------------------------------------
  // Create
  // ---------------------------------------------------------------------------

  /// Inserts a new integrity alert.  Returns the auto-generated row id.
  Future<int> insert(IntegrityAlert alert) async {
    final db = await _db;
    return db.insert('integrity_alerts', alert.toMap());
  }

  /// Convenience factory for quickly logging an alert from raw parameters.
  Future<int> createAlert({
    String? receiptId,
    required String alertType,
    required String description,
    String? filePath,
    String severity = AlertSeverity.warning,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    return insert(IntegrityAlert(
      receiptId: receiptId,
      alertType: alertType,
      description: description,
      filePath: filePath,
      severity: severity,
      createdAt: now,
    ));
  }

  // ---------------------------------------------------------------------------
  // Read
  // ---------------------------------------------------------------------------

  /// Returns the alert with [id], or `null`.
  Future<IntegrityAlert?> getById(int id) async {
    final db = await _db;
    final rows = await db.query(
      'integrity_alerts',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return IntegrityAlert.fromMap(rows.first);
  }

  /// Returns all unresolved alerts, newest first.
  Future<List<IntegrityAlert>> getUnresolved() async {
    final db = await _db;
    final rows = await db.query(
      'integrity_alerts',
      where: 'resolved = 0',
      orderBy: 'created_at DESC',
    );
    return rows.map(IntegrityAlert.fromMap).toList();
  }

  /// Returns all alerts (both resolved and unresolved), newest first.
  Future<List<IntegrityAlert>> getAll() async {
    final db = await _db;
    final rows = await db.query(
      'integrity_alerts',
      orderBy: 'created_at DESC',
    );
    return rows.map(IntegrityAlert.fromMap).toList();
  }

  /// Returns alerts matching the given [alertType].
  Future<List<IntegrityAlert>> getByType(String alertType) async {
    final db = await _db;
    final rows = await db.query(
      'integrity_alerts',
      where: 'alert_type = ?',
      whereArgs: [alertType],
      orderBy: 'created_at DESC',
    );
    return rows.map(IntegrityAlert.fromMap).toList();
  }

  /// Returns alerts associated with the given [receiptId].
  Future<List<IntegrityAlert>> getByReceiptId(String receiptId) async {
    final db = await _db;
    final rows = await db.query(
      'integrity_alerts',
      where: 'receipt_id = ?',
      whereArgs: [receiptId],
      orderBy: 'created_at DESC',
    );
    return rows.map(IntegrityAlert.fromMap).toList();
  }

  /// Returns the count of unresolved alerts.
  Future<int> getUnresolvedCount() async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM integrity_alerts WHERE resolved = 0',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ---------------------------------------------------------------------------
  // Update
  // ---------------------------------------------------------------------------

  /// Marks the alert with [id] as resolved.
  Future<void> resolve(int id) async {
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'integrity_alerts',
      {'resolved': 1, 'resolved_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Marks all unresolved alerts as resolved in a single batch.
  Future<int> resolveAll() async {
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();
    return db.update(
      'integrity_alerts',
      {'resolved': 1, 'resolved_at': now},
      where: 'resolved = 0',
    );
  }

  // ---------------------------------------------------------------------------
  // Delete
  // ---------------------------------------------------------------------------

  /// Deletes a single alert.
  Future<void> delete(int id) async {
    final db = await _db;
    await db.delete('integrity_alerts', where: 'id = ?', whereArgs: [id]);
  }

  /// Removes all resolved alerts older than [before] (ISO-8601 string).
  Future<int> deleteResolvedBefore(String before) async {
    final db = await _db;
    return db.delete(
      'integrity_alerts',
      where: 'resolved = 1 AND resolved_at < ?',
      whereArgs: [before],
    );
  }
}
