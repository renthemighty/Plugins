/// Integrity auditing engine for the Kira receipt storage system.
///
/// Scans local receipt files and index entries to detect:
/// - Orphan files (not referenced by any index)
/// - Orphan index entries (referenced file is missing)
/// - Checksum mismatches (file content does not match stored digest)
/// - Invalid filenames
/// - Files in wrong date folders
/// - Unexpected file types in receipt directories
///
/// Runs: at launch, after each sync cycle, periodically while active,
/// in background when allowed (paid cloud modes).
///
/// NEVER auto-deletes anything. Alerts are persisted in SQLite and surfaced
/// in the Alerts tab.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../db/database_helper.dart';
import '../services/filename_allocator.dart';

// ---------------------------------------------------------------------------
// Alert model
// ---------------------------------------------------------------------------

enum AlertSeverity { info, warning, critical }

enum IntegrityAlertType {
  orphanFile,
  orphanEntry,
  invalidFilename,
  folderMismatch,
  checksumMismatch,
  unexpectedFile,
}

class IntegrityAlert {
  final int? id;
  final String? receiptId;
  final String alertType;
  final String description;
  final String? filePath;
  final AlertSeverity severity;
  final bool resolved;
  final String createdAt;
  final String? resolvedAt;
  final String? recommendedAction;

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
    this.recommendedAction,
  });

  factory IntegrityAlert.fromMap(Map<String, dynamic> map) {
    return IntegrityAlert(
      id: map['id'] as int?,
      receiptId: map['receipt_id'] as String?,
      alertType: map['alert_type'] as String,
      description: map['description'] as String,
      filePath: map['file_path'] as String?,
      severity: _parseSeverity(map['severity'] as String? ?? 'warning'),
      resolved: (map['resolved'] as int? ?? 0) == 1,
      createdAt: map['created_at'] as String,
      resolvedAt: map['resolved_at'] as String?,
      recommendedAction: map['recommended_action'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'receipt_id': receiptId,
        'alert_type': alertType,
        'description': description,
        'file_path': filePath,
        'severity': severity.name,
        'resolved': resolved ? 1 : 0,
        'created_at': createdAt,
        'resolved_at': resolvedAt,
        'recommended_action': recommendedAction,
      };

  static AlertSeverity _parseSeverity(String value) {
    switch (value) {
      case 'critical':
        return AlertSeverity.critical;
      case 'info':
        return AlertSeverity.info;
      default:
        return AlertSeverity.warning;
    }
  }
}

// ---------------------------------------------------------------------------
// IntegrityAuditor
// ---------------------------------------------------------------------------

class IntegrityAuditor extends ChangeNotifier {
  final DatabaseHelper _dbHelper;

  List<IntegrityAlert> _alerts = [];
  bool _isRunning = false;
  bool _initialized = false;

  IntegrityAuditor([DatabaseHelper? dbHelper])
      : _dbHelper = dbHelper ?? DatabaseHelper();

  // -------------------------------------------------------------------------
  // Public getters
  // -------------------------------------------------------------------------

  bool get initialized => _initialized;
  bool get isRunning => _isRunning;
  List<IntegrityAlert> get alerts => List.unmodifiable(_alerts);
  int get activeAlertCount => _alerts.where((a) => !a.resolved).length;
  bool get hasActiveAlerts => activeAlertCount > 0;

  // -------------------------------------------------------------------------
  // Initialization
  // -------------------------------------------------------------------------

  Future<void> initialize() async {
    await _loadAlerts();
    _initialized = true;
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Convenience audit (fire-and-forget from main)
  // -------------------------------------------------------------------------

  /// Fire-and-forget audit that resolves the local receipts root automatically.
  ///
  /// Called from `main()` at launch.  Errors are silently caught so the app
  /// always boots.
  Future<void> runAudit() async {
    try {
      final dir = await _resolveLocalReceiptsRoot();
      if (dir != null) {
        await runQuickAudit(dir);
      }
    } catch (_) {
      // Non-blocking -- never prevent app launch.
    }
  }

  Future<String?> _resolveLocalReceiptsRoot() async {
    try {
      // Use path_provider to find app documents directory.
      // Import is already available in this file through dart:io.
      final baseDir = Directory.current.path;
      // Look for a Receipts folder under the app's documents.
      final receiptsDir = Directory('$baseDir/Receipts');
      if (await receiptsDir.exists()) return receiptsDir.path;
      return null;
    } catch (_) {
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // Full audit
  // -------------------------------------------------------------------------

  /// Runs a comprehensive integrity audit scanning all local receipt folders.
  Future<List<IntegrityAlert>> runFullAudit(String localReceiptsRoot) async {
    if (_isRunning) return _alerts;
    _isRunning = true;
    notifyListeners();

    final newAlerts = <IntegrityAlert>[];

    try {
      final rootDir = Directory(localReceiptsRoot);
      if (!await rootDir.exists()) {
        _isRunning = false;
        notifyListeners();
        return _alerts;
      }

      // Walk: Receipts/<Country>/<YYYY>/<YYYY-MM>/<YYYY-MM-DD>/
      await for (final countryEntity in rootDir.list()) {
        if (countryEntity is! Directory) continue;
        final countryName = p.basename(countryEntity.path);

        await for (final yearEntity in countryEntity.list()) {
          if (yearEntity is! Directory) continue;

          await for (final monthEntity in yearEntity.list()) {
            if (monthEntity is! Directory) continue;
            final monthName = p.basename(monthEntity.path);

            await for (final dayEntity in monthEntity.list()) {
              if (dayEntity is! Directory) continue;
              final dayName = p.basename(dayEntity.path);
              if (dayName == '_Quarantine') continue;

              final dayAlerts = await _auditDayFolder(
                dayEntity.path,
                dayName,
                monthName,
                countryName,
              );
              newAlerts.addAll(dayAlerts);
            }
          }
        }
      }

      // Persist new alerts
      for (final alert in newAlerts) {
        await addAlert(alert);
      }
    } finally {
      _isRunning = false;
      await _loadAlerts();
      notifyListeners();
    }

    return _alerts;
  }

  /// Quick audit: skip checksum verification for speed.
  Future<List<IntegrityAlert>> runQuickAudit(String localReceiptsRoot) async {
    if (_isRunning) return _alerts;
    _isRunning = true;
    notifyListeners();

    final newAlerts = <IntegrityAlert>[];

    try {
      final rootDir = Directory(localReceiptsRoot);
      if (!await rootDir.exists()) {
        _isRunning = false;
        notifyListeners();
        return _alerts;
      }

      await for (final countryEntity in rootDir.list()) {
        if (countryEntity is! Directory) continue;
        final countryName = p.basename(countryEntity.path);

        await for (final yearEntity in countryEntity.list()) {
          if (yearEntity is! Directory) continue;

          await for (final monthEntity in yearEntity.list()) {
            if (monthEntity is! Directory) continue;
            final monthName = p.basename(monthEntity.path);

            await for (final dayEntity in monthEntity.list()) {
              if (dayEntity is! Directory) continue;
              final dayName = p.basename(dayEntity.path);
              if (dayName == '_Quarantine') continue;

              final dayAlerts = await _auditDayFolder(
                dayEntity.path,
                dayName,
                monthName,
                countryName,
                skipChecksums: true,
              );
              newAlerts.addAll(dayAlerts);
            }
          }
        }
      }

      for (final alert in newAlerts) {
        await addAlert(alert);
      }
    } finally {
      _isRunning = false;
      await _loadAlerts();
      notifyListeners();
    }

    return _alerts;
  }

  // -------------------------------------------------------------------------
  // Day folder audit
  // -------------------------------------------------------------------------

  Future<List<IntegrityAlert>> _auditDayFolder(
    String dayPath,
    String dayName,
    String monthName,
    String countryName, {
    bool skipChecksums = false,
  }) async {
    final alerts = <IntegrityAlert>[];
    final now = DateTime.now().toUtc().toIso8601String();

    // Load day index if present
    Map<String, Map<String, dynamic>>? indexEntries;
    final indexFile = File(p.join(dayPath, 'index.json'));
    if (await indexFile.exists()) {
      try {
        final content = await indexFile.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final receipts = json['receipts'] as List<dynamic>? ?? [];
        indexEntries = {
          for (final r in receipts)
            (r as Map<String, dynamic>)['filename'] as String: r,
        };
      } catch (_) {
        alerts.add(IntegrityAlert(
          alertType: IntegrityAlertType.unexpectedFile.name,
          description: 'Corrupted index.json in $dayPath',
          filePath: indexFile.path,
          severity: AlertSeverity.critical,
          createdAt: now,
          recommendedAction: 'Rebuild index from receipt database',
        ));
      }
    }

    // List all files in day folder
    final dir = Directory(dayPath);
    final files = <String>[];
    await for (final entity in dir.list()) {
      if (entity is File) {
        files.add(p.basename(entity.path));
      }
    }

    // 1. Check for unexpected file types
    for (final filename in files) {
      if (filename == 'index.json') continue;
      if (!filename.endsWith('.jpg')) {
        alerts.add(IntegrityAlert(
          alertType: IntegrityAlertType.unexpectedFile.name,
          description: 'Unexpected file type in receipt folder: $filename',
          filePath: p.join(dayPath, filename),
          severity: AlertSeverity.warning,
          createdAt: now,
          recommendedAction: 'Review and remove if not a receipt',
        ));
        continue;
      }

      // 2. Validate filename format
      if (!FilenameAllocator.validateFilename(filename)) {
        alerts.add(IntegrityAlert(
          alertType: IntegrityAlertType.invalidFilename.name,
          description: 'Invalid filename format: $filename',
          filePath: p.join(dayPath, filename),
          severity: AlertSeverity.warning,
          createdAt: now,
          recommendedAction: 'Rename to match YYYY-MM-DD_N.jpg pattern',
        ));
      }

      // 3. Check folder/date mismatch
      if (filename.length >= 10) {
        final fileDate = filename.substring(0, 10);
        if (fileDate != dayName) {
          alerts.add(IntegrityAlert(
            alertType: IntegrityAlertType.folderMismatch.name,
            description:
                'File $filename is in folder $dayName but dates don\'t match',
            filePath: p.join(dayPath, filename),
            severity: AlertSeverity.warning,
            createdAt: now,
            recommendedAction: 'Move file to correct date folder',
          ));
        }
      }

      // 4. Orphan file check (file exists but not in index)
      if (indexEntries != null && !indexEntries.containsKey(filename)) {
        alerts.add(IntegrityAlert(
          alertType: IntegrityAlertType.orphanFile.name,
          description: 'File $filename not referenced in day index',
          filePath: p.join(dayPath, filename),
          severity: AlertSeverity.warning,
          createdAt: now,
          recommendedAction: 'Add to index or investigate origin',
        ));
      }

      // 5. Checksum verification (full audit only)
      if (!skipChecksums && indexEntries != null) {
        final entry = indexEntries[filename];
        if (entry != null) {
          final expectedChecksum = entry['checksum_sha256'] as String?;
          if (expectedChecksum != null) {
            try {
              final fileBytes =
                  await File(p.join(dayPath, filename)).readAsBytes();
              final actualChecksum = sha256.convert(fileBytes).toString();
              if (actualChecksum != expectedChecksum) {
                alerts.add(IntegrityAlert(
                  alertType: IntegrityAlertType.checksumMismatch.name,
                  description:
                      'Checksum mismatch for $filename — possible tampering',
                  filePath: p.join(dayPath, filename),
                  severity: AlertSeverity.critical,
                  createdAt: now,
                  recommendedAction:
                      'Verify file integrity; re-download from cloud if available',
                ));
              }
            } catch (_) {
              // File read error
            }
          }
        }
      }
    }

    // 6. Orphan index entries (index references file that doesn't exist)
    if (indexEntries != null) {
      final jpgFiles = files.where((f) => f.endsWith('.jpg')).toSet();
      for (final indexedFilename in indexEntries.keys) {
        if (!jpgFiles.contains(indexedFilename)) {
          final entry = indexEntries[indexedFilename]!;
          alerts.add(IntegrityAlert(
            receiptId: entry['receipt_id'] as String?,
            alertType: IntegrityAlertType.orphanEntry.name,
            description:
                'Index references missing file: $indexedFilename',
            filePath: p.join(dayPath, indexedFilename),
            severity: AlertSeverity.warning,
            createdAt: now,
            recommendedAction:
                'Re-download from cloud or remove index entry after review',
          ));
        }
      }
    }

    return alerts;
  }

  // -------------------------------------------------------------------------
  // Alert management
  // -------------------------------------------------------------------------

  Future<void> addAlert(IntegrityAlert alert) async {
    final db = await _dbHelper.database;

    // Avoid duplicate alerts for same path and type
    final existing = await db.query(
      'integrity_alerts',
      where: 'file_path = ? AND alert_type = ? AND resolved = 0',
      whereArgs: [alert.filePath, alert.alertType],
    );
    if (existing.isNotEmpty) return;

    await db.insert('integrity_alerts', alert.toMap());
    await _loadAlerts();
    notifyListeners();
  }

  Future<void> dismissAlert(int alertId) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'integrity_alerts',
      {'resolved': 1, 'resolved_at': now},
      where: 'id = ?',
      whereArgs: [alertId],
    );
    await _loadAlerts();
    notifyListeners();
  }

  /// Moves the offending file to `<YYYY-MM>/_Quarantine/` and resolves the
  /// alert. Requires explicit user action — never auto-deletes.
  Future<void> quarantineFile(int alertId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'integrity_alerts',
      where: 'id = ?',
      whereArgs: [alertId],
    );
    if (rows.isEmpty) return;

    final alert = IntegrityAlert.fromMap(rows.first);
    if (alert.filePath == null) {
      await dismissAlert(alertId);
      return;
    }

    final file = File(alert.filePath!);
    if (await file.exists()) {
      // Determine quarantine: go up to month folder, add _Quarantine
      final dayDir = p.dirname(alert.filePath!);
      final monthDir = p.dirname(dayDir);
      final quarantineDir = Directory(p.join(monthDir, '_Quarantine'));
      await quarantineDir.create(recursive: true);

      final quarantinePath = p.join(
        quarantineDir.path,
        p.basename(alert.filePath!),
      );
      await file.rename(quarantinePath);

      // Log the quarantine action
      await db.insert('integrity_alerts', IntegrityAlert(
        alertType: 'quarantine_action',
        description:
            'File moved to quarantine: ${p.basename(alert.filePath!)}',
        filePath: quarantinePath,
        severity: AlertSeverity.info,
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ).toMap());
    }

    await dismissAlert(alertId);
  }

  // -------------------------------------------------------------------------
  // Internal
  // -------------------------------------------------------------------------

  Future<void> _loadAlerts() async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'integrity_alerts',
      where: 'resolved = 0',
      orderBy: 'created_at DESC',
    );
    _alerts = rows.map(IntegrityAlert.fromMap).toList();
  }
}
