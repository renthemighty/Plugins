/// Tests for the Kira integrity auditor.
///
/// The integrity auditor scans local and remote storage for anomalies
/// including orphan files, orphan entries, invalid filenames, folder/date
/// mismatches, checksum mismatches, and unexpected file types. It never
/// auto-deletes files; it only reports findings and can quarantine them
/// when instructed.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:kira/core/models/integrity_alert.dart';
import 'package:kira/core/models/day_index.dart';

// ---------------------------------------------------------------------------
// Auditor abstractions (under test)
// ---------------------------------------------------------------------------

/// Represents the filesystem interface the auditor depends on.
abstract class AuditFileSystem {
  /// Lists all image filenames in a day folder on disk.
  Future<List<String>> listDayFolderFiles(String dayFolder);

  /// Returns the SHA-256 checksum of a file.
  Future<String> computeChecksum(String filePath);

  /// Returns true if the file exists at the given path.
  Future<bool> fileExists(String path);

  /// Moves a file to the quarantine folder and returns the quarantine path.
  Future<String> quarantineFile(String sourcePath);
}

class MockAuditFileSystem extends Mock implements AuditFileSystem {}

/// Represents the index reader the auditor uses to obtain day index data.
abstract class AuditIndexReader {
  /// Returns the DayIndex for the given date folder, or null if absent.
  Future<DayIndex?> readDayIndex(String dayFolder);
}

class MockAuditIndexReader extends Mock implements AuditIndexReader {}

/// The integrity auditor that detects anomalies in the receipt storage.
///
/// This is the specification-driven implementation used to validate the
/// test expectations.
class IntegrityAuditor {
  final AuditFileSystem _fs;
  final AuditIndexReader _indexReader;
  final List<IntegrityAlert> _alerts = [];
  final List<String> _actionLog = [];

  IntegrityAuditor(this._fs, this._indexReader);

  List<IntegrityAlert> get alerts => List.unmodifiable(_alerts);
  List<String> get actionLog => List.unmodifiable(_actionLog);

  /// Filename pattern that all receipt images must match.
  static final RegExp validFilenamePattern =
      RegExp(r'^\d{4}-\d{2}-\d{2}_[1-9]\d*\.jpg$');

  /// Allowed file extensions in receipt day folders.
  static const Set<String> allowedExtensions = {'.jpg', '.json'};

  /// Audits a single day folder for integrity issues.
  Future<List<IntegrityAlert>> auditDayFolder(String dayFolder) async {
    _alerts.clear();
    _actionLog.clear();

    final filesOnDisk = await _fs.listDayFolderFiles(dayFolder);
    final dayIndex = await _indexReader.readDayIndex(dayFolder);

    final indexedFilenames = <String>{};
    if (dayIndex != null) {
      for (final entry in dayIndex.receipts) {
        indexedFilenames.add(entry.filename);
      }
    }

    // Check each file on disk.
    for (final file in filesOnDisk) {
      // Skip index.json itself.
      if (file == 'index.json') continue;

      // Check for unexpected file types.
      final ext = _extensionOf(file);
      if (!allowedExtensions.contains(ext)) {
        _addAlert(
          type: IntegrityAlertType.unexpectedFile,
          path: '$dayFolder/$file',
          description: 'Unexpected file type: $ext',
          recommendedAction: 'Review and remove or quarantine the file.',
        );
        continue;
      }

      // Check filename validity (only for .jpg files).
      if (ext == '.jpg' && !validFilenamePattern.hasMatch(file)) {
        _addAlert(
          type: IntegrityAlertType.invalidFilename,
          path: '$dayFolder/$file',
          description: 'Filename does not match expected pattern: $file',
          recommendedAction: 'Rename or quarantine the file.',
        );
        continue;
      }

      // Check for orphan files (image not in index).
      if (ext == '.jpg' && !indexedFilenames.contains(file)) {
        _addAlert(
          type: IntegrityAlertType.orphanFile,
          path: '$dayFolder/$file',
          description: 'Image file exists but has no index entry.',
          recommendedAction: 'Add to index or quarantine.',
        );
      }

      // Check folder/date mismatch.
      if (ext == '.jpg' && validFilenamePattern.hasMatch(file)) {
        final dateFromFilename = file.substring(0, 10); // YYYY-MM-DD
        if (!dayFolder.endsWith(dateFromFilename)) {
          _addAlert(
            type: IntegrityAlertType.folderMismatch,
            path: '$dayFolder/$file',
            description:
                'File date $dateFromFilename does not match folder $dayFolder.',
            recommendedAction: 'Move file to the correct folder.',
          );
        }
      }
    }

    // Check for orphan entries (index references missing file).
    if (dayIndex != null) {
      for (final entry in dayIndex.receipts) {
        final fileOnDisk = filesOnDisk.contains(entry.filename);
        if (!fileOnDisk) {
          _addAlert(
            type: IntegrityAlertType.orphanEntry,
            path: '$dayFolder/${entry.filename}',
            description:
                'Index entry references file ${entry.filename} which is missing.',
            recommendedAction: 'Re-download or remove the index entry.',
          );
        }
      }

      // Check checksum mismatches.
      for (final entry in dayIndex.receipts) {
        if (filesOnDisk.contains(entry.filename)) {
          final filePath = '$dayFolder/${entry.filename}';
          final actualChecksum = await _fs.computeChecksum(filePath);
          if (actualChecksum != entry.checksumSha256) {
            _addAlert(
              type: IntegrityAlertType.checksumMismatch,
              path: filePath,
              description:
                  'Checksum mismatch: expected ${entry.checksumSha256}, '
                  'got $actualChecksum.',
              recommendedAction: 'Re-download the file or quarantine.',
            );
          }
        }
      }
    }

    return List.unmodifiable(_alerts);
  }

  /// Quarantines a file referenced by an alert. Does NOT delete it.
  Future<void> quarantine(IntegrityAlert alert) async {
    final quarantinePath = await _fs.quarantineFile(alert.path);
    _actionLog.add(
      'QUARANTINE: ${alert.path} -> $quarantinePath '
      '(type: ${alert.type}, id: ${alert.id})',
    );
  }

  void _addAlert({
    required IntegrityAlertType type,
    required String path,
    required String description,
    required String recommendedAction,
  }) {
    _alerts.add(IntegrityAlert(
      id: 'alert-${_alerts.length + 1}',
      type: type,
      path: path,
      description: description,
      recommendedAction: recommendedAction,
      detectedAt: DateTime.now().toUtc().toIso8601String(),
    ));
  }

  String _extensionOf(String filename) {
    final dot = filename.lastIndexOf('.');
    if (dot == -1) return '';
    return filename.substring(dot);
  }
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

ReceiptIndexEntry _makeEntry({
  required String receiptId,
  required String filename,
  String checksumSha256 = 'abc123def456',
  String capturedAt = '2025-06-14T09:00:00',
  String updatedAt = '2025-06-14T09:00:00Z',
}) {
  return ReceiptIndexEntry(
    receiptId: receiptId,
    filename: filename,
    amountTracked: 25.00,
    currencyCode: 'CAD',
    category: 'meals',
    checksumSha256: checksumSha256,
    capturedAt: capturedAt,
    updatedAt: updatedAt,
  );
}

DayIndex _makeDayIndex({
  String date = '2025-06-14',
  required List<ReceiptIndexEntry> receipts,
}) {
  return DayIndex(
    date: date,
    lastUpdated: '2025-06-14T10:00:00Z',
    receipts: receipts,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockAuditFileSystem mockFs;
  late MockAuditIndexReader mockIndexReader;
  late IntegrityAuditor auditor;

  setUp(() {
    mockFs = MockAuditFileSystem();
    mockIndexReader = MockAuditIndexReader();
    auditor = IntegrityAuditor(mockFs, mockIndexReader);
  });

  group('IntegrityAuditor', () {
    group('detection of orphan files (image not in index)', () {
      test('detects file on disk not present in any index entry', () async {
        when(mockFs.listDayFolderFiles('2025/06/14'))
            .thenAnswer((_) async => ['2025-06-14_1.jpg', '2025-06-14_2.jpg']);
        when(mockIndexReader.readDayIndex('2025/06/14'))
            .thenAnswer((_) async => _makeDayIndex(
                  receipts: [
                    _makeEntry(
                        receiptId: 'r1', filename: '2025-06-14_1.jpg'),
                  ],
                ));
        when(mockFs.computeChecksum(any))
            .thenAnswer((_) async => 'abc123def456');

        final alerts = await auditor.auditDayFolder('2025/06/14');

        final orphanFiles = alerts
            .where((a) => a.type == IntegrityAlertType.orphanFile)
            .toList();
        expect(orphanFiles.length, 1);
        expect(orphanFiles.first.path, contains('2025-06-14_2.jpg'));
      });

      test('no orphan alert when all files are in the index', () async {
        when(mockFs.listDayFolderFiles('2025/06/14'))
            .thenAnswer((_) async => ['2025-06-14_1.jpg', 'index.json']);
        when(mockIndexReader.readDayIndex('2025/06/14'))
            .thenAnswer((_) async => _makeDayIndex(
                  receipts: [
                    _makeEntry(
                        receiptId: 'r1', filename: '2025-06-14_1.jpg'),
                  ],
                ));
        when(mockFs.computeChecksum(any))
            .thenAnswer((_) async => 'abc123def456');

        final alerts = await auditor.auditDayFolder('2025/06/14');

        final orphanFiles = alerts
            .where((a) => a.type == IntegrityAlertType.orphanFile)
            .toList();
        expect(orphanFiles, isEmpty);
      });
    });

    group('detection of orphan entries (index references missing file)', () {
      test('detects index entry pointing to non-existent file', () async {
        when(mockFs.listDayFolderFiles('2025/06/14'))
            .thenAnswer((_) async => ['index.json']);
        when(mockIndexReader.readDayIndex('2025/06/14'))
            .thenAnswer((_) async => _makeDayIndex(
                  receipts: [
                    _makeEntry(
                        receiptId: 'r1', filename: '2025-06-14_1.jpg'),
                  ],
                ));

        final alerts = await auditor.auditDayFolder('2025/06/14');

        final orphanEntries = alerts
            .where((a) => a.type == IntegrityAlertType.orphanEntry)
            .toList();
        expect(orphanEntries.length, 1);
        expect(orphanEntries.first.path, contains('2025-06-14_1.jpg'));
      });

      test('no orphan entry alert when all indexed files exist', () async {
        when(mockFs.listDayFolderFiles('2025/06/14'))
            .thenAnswer((_) async => ['2025-06-14_1.jpg']);
        when(mockIndexReader.readDayIndex('2025/06/14'))
            .thenAnswer((_) async => _makeDayIndex(
                  receipts: [
                    _makeEntry(
                        receiptId: 'r1', filename: '2025-06-14_1.jpg'),
                  ],
                ));
        when(mockFs.computeChecksum(any))
            .thenAnswer((_) async => 'abc123def456');

        final alerts = await auditor.auditDayFolder('2025/06/14');

        final orphanEntries = alerts
            .where((a) => a.type == IntegrityAlertType.orphanEntry)
            .toList();
        expect(orphanEntries, isEmpty);
      });
    });

    group('detection of invalid filenames', () {
      test('detects filename that does not match the expected pattern',
          () async {
        when(mockFs.listDayFolderFiles('2025/06/14')).thenAnswer(
          (_) async => ['bad_filename.jpg', '2025-06-14_1.jpg'],
        );
        when(mockIndexReader.readDayIndex('2025/06/14'))
            .thenAnswer((_) async => _makeDayIndex(
                  receipts: [
                    _makeEntry(
                        receiptId: 'r1', filename: '2025-06-14_1.jpg'),
                  ],
                ));
        when(mockFs.computeChecksum(any))
            .thenAnswer((_) async => 'abc123def456');

        final alerts = await auditor.auditDayFolder('2025/06/14');

        final invalidNames = alerts
            .where((a) => a.type == IntegrityAlertType.invalidFilename)
            .toList();
        expect(invalidNames.length, 1);
        expect(invalidNames.first.path, contains('bad_filename.jpg'));
      });

      test('detects filename with _0 suffix as invalid', () async {
        when(mockFs.listDayFolderFiles('2025/06/14')).thenAnswer(
          (_) async => ['2025-06-14_0.jpg'],
        );
        when(mockIndexReader.readDayIndex('2025/06/14'))
            .thenAnswer((_) async => _makeDayIndex(receipts: []));

        final alerts = await auditor.auditDayFolder('2025/06/14');

        final invalidNames = alerts
            .where((a) => a.type == IntegrityAlertType.invalidFilename)
            .toList();
        expect(invalidNames.length, 1);
      });
    });

    group('detection of folder/date mismatch', () {
      test('detects file in wrong date folder', () async {
        // File is named 2025-06-15 but in the 2025/06/14 folder.
        when(mockFs.listDayFolderFiles('2025/06/14')).thenAnswer(
          (_) async => ['2025-06-15_1.jpg'],
        );
        when(mockIndexReader.readDayIndex('2025/06/14'))
            .thenAnswer((_) async => _makeDayIndex(receipts: []));

        final alerts = await auditor.auditDayFolder('2025/06/14');

        final mismatches = alerts
            .where((a) => a.type == IntegrityAlertType.folderMismatch)
            .toList();
        expect(mismatches.length, 1);
        expect(mismatches.first.description, contains('2025-06-15'));
      });

      test('no mismatch when file date matches folder', () async {
        when(mockFs.listDayFolderFiles('Receipts/Canada/2025/2025-06/2025-06-14'))
            .thenAnswer((_) async => ['2025-06-14_1.jpg']);
        when(mockIndexReader
                .readDayIndex('Receipts/Canada/2025/2025-06/2025-06-14'))
            .thenAnswer((_) async => _makeDayIndex(
                  receipts: [
                    _makeEntry(
                        receiptId: 'r1', filename: '2025-06-14_1.jpg'),
                  ],
                ));
        when(mockFs.computeChecksum(any))
            .thenAnswer((_) async => 'abc123def456');

        final alerts = await auditor
            .auditDayFolder('Receipts/Canada/2025/2025-06/2025-06-14');

        final mismatches = alerts
            .where((a) => a.type == IntegrityAlertType.folderMismatch)
            .toList();
        expect(mismatches, isEmpty);
      });
    });

    group('checksum mismatch detection (tampering)', () {
      test('detects file whose checksum does not match index entry', () async {
        when(mockFs.listDayFolderFiles('2025/06/14'))
            .thenAnswer((_) async => ['2025-06-14_1.jpg']);
        when(mockIndexReader.readDayIndex('2025/06/14'))
            .thenAnswer((_) async => _makeDayIndex(
                  receipts: [
                    _makeEntry(
                      receiptId: 'r1',
                      filename: '2025-06-14_1.jpg',
                      checksumSha256: 'expected_checksum_abc',
                    ),
                  ],
                ));
        when(mockFs.computeChecksum('2025/06/14/2025-06-14_1.jpg'))
            .thenAnswer((_) async => 'actual_checksum_xyz'); // different

        final alerts = await auditor.auditDayFolder('2025/06/14');

        final checksumAlerts = alerts
            .where((a) => a.type == IntegrityAlertType.checksumMismatch)
            .toList();
        expect(checksumAlerts.length, 1);
        expect(checksumAlerts.first.description, contains('expected_checksum_abc'));
        expect(checksumAlerts.first.description, contains('actual_checksum_xyz'));
      });

      test('no alert when checksum matches', () async {
        when(mockFs.listDayFolderFiles('2025/06/14'))
            .thenAnswer((_) async => ['2025-06-14_1.jpg']);
        when(mockIndexReader.readDayIndex('2025/06/14'))
            .thenAnswer((_) async => _makeDayIndex(
                  receipts: [
                    _makeEntry(
                      receiptId: 'r1',
                      filename: '2025-06-14_1.jpg',
                      checksumSha256: 'matching_checksum',
                    ),
                  ],
                ));
        when(mockFs.computeChecksum('2025/06/14/2025-06-14_1.jpg'))
            .thenAnswer((_) async => 'matching_checksum');

        final alerts = await auditor.auditDayFolder('2025/06/14');

        final checksumAlerts = alerts
            .where((a) => a.type == IntegrityAlertType.checksumMismatch)
            .toList();
        expect(checksumAlerts, isEmpty);
      });
    });

    group('unexpected file type detection', () {
      test('detects non-jpg/non-json files in day folder', () async {
        when(mockFs.listDayFolderFiles('2025/06/14')).thenAnswer(
          (_) async => [
            '2025-06-14_1.jpg',
            'index.json',
            'notes.txt', // unexpected
            'photo.png', // unexpected
          ],
        );
        when(mockIndexReader.readDayIndex('2025/06/14'))
            .thenAnswer((_) async => _makeDayIndex(
                  receipts: [
                    _makeEntry(
                        receiptId: 'r1', filename: '2025-06-14_1.jpg'),
                  ],
                ));
        when(mockFs.computeChecksum(any))
            .thenAnswer((_) async => 'abc123def456');

        final alerts = await auditor.auditDayFolder('2025/06/14');

        final unexpectedFiles = alerts
            .where((a) => a.type == IntegrityAlertType.unexpectedFile)
            .toList();
        expect(unexpectedFiles.length, 2);
      });

      test('no unexpected file alert for .jpg and .json', () async {
        when(mockFs.listDayFolderFiles('2025/06/14')).thenAnswer(
          (_) async => ['2025-06-14_1.jpg', 'index.json'],
        );
        when(mockIndexReader.readDayIndex('2025/06/14'))
            .thenAnswer((_) async => _makeDayIndex(
                  receipts: [
                    _makeEntry(
                        receiptId: 'r1', filename: '2025-06-14_1.jpg'),
                  ],
                ));
        when(mockFs.computeChecksum(any))
            .thenAnswer((_) async => 'abc123def456');

        final alerts = await auditor.auditDayFolder('2025/06/14');

        final unexpectedFiles = alerts
            .where((a) => a.type == IntegrityAlertType.unexpectedFile)
            .toList();
        expect(unexpectedFiles, isEmpty);
      });
    });

    group('auditor never auto-deletes', () {
      test('no calls to delete or remove files during audit', () async {
        when(mockFs.listDayFolderFiles('2025/06/14')).thenAnswer(
          (_) async => [
            '2025-06-14_1.jpg',
            'bad_file.txt',
            '2025-06-14_2.jpg',
          ],
        );
        when(mockIndexReader.readDayIndex('2025/06/14'))
            .thenAnswer((_) async => _makeDayIndex(
                  receipts: [
                    _makeEntry(
                        receiptId: 'r1', filename: '2025-06-14_1.jpg'),
                  ],
                ));
        when(mockFs.computeChecksum(any))
            .thenAnswer((_) async => 'abc123def456');

        await auditor.auditDayFolder('2025/06/14');

        // quarantineFile should never be called during audit -- only during
        // an explicit quarantine action.
        verifyNever(mockFs.quarantineFile(any));
      });

      test('audit only produces alerts, never modifies data', () async {
        when(mockFs.listDayFolderFiles('2025/06/14')).thenAnswer(
          (_) async => ['orphan_file.jpg'],
        );
        when(mockIndexReader.readDayIndex('2025/06/14'))
            .thenAnswer((_) async => _makeDayIndex(receipts: []));

        final alerts = await auditor.auditDayFolder('2025/06/14');

        // Alert is produced but no file operations happen.
        expect(alerts, isNotEmpty);
        verifyNever(mockFs.quarantineFile(any));
      });
    });

    group('quarantine action logs properly', () {
      test('quarantine moves file and logs the action', () async {
        when(mockFs.quarantineFile('2025/06/14/orphan.jpg'))
            .thenAnswer((_) async => 'quarantine/orphan.jpg');

        final alert = IntegrityAlert(
          id: 'alert-1',
          type: IntegrityAlertType.orphanFile,
          path: '2025/06/14/orphan.jpg',
          description: 'Orphan file detected.',
          recommendedAction: 'Quarantine the file.',
          detectedAt: '2025-06-14T10:00:00Z',
        );

        await auditor.quarantine(alert);

        verify(mockFs.quarantineFile('2025/06/14/orphan.jpg')).called(1);
        expect(auditor.actionLog.length, 1);
        expect(auditor.actionLog.first, contains('QUARANTINE'));
        expect(auditor.actionLog.first, contains('2025/06/14/orphan.jpg'));
        expect(auditor.actionLog.first, contains('quarantine/orphan.jpg'));
      });

      test('quarantine log includes alert type and id', () async {
        when(mockFs.quarantineFile(any))
            .thenAnswer((_) async => 'quarantine/file.jpg');

        final alert = IntegrityAlert(
          id: 'alert-42',
          type: IntegrityAlertType.checksumMismatch,
          path: 'some/path/file.jpg',
          description: 'Checksum mismatch.',
          recommendedAction: 'Quarantine.',
          detectedAt: '2025-06-14T10:00:00Z',
        );

        await auditor.quarantine(alert);

        expect(auditor.actionLog.first,
            contains('IntegrityAlertType.checksumMismatch'));
        expect(auditor.actionLog.first, contains('alert-42'));
      });
    });

    group('IntegrityAlert model', () {
      test('fromJson / toJson round-trip', () {
        final alert = IntegrityAlert(
          id: 'a1',
          type: IntegrityAlertType.orphanFile,
          path: '/path/to/file.jpg',
          description: 'Test alert',
          recommendedAction: 'Fix it',
          detectedAt: '2025-06-14T10:00:00Z',
          dismissed: true,
          quarantined: false,
        );

        final json = alert.toJson();
        final restored = IntegrityAlert.fromJson(json);

        expect(restored.id, alert.id);
        expect(restored.type, alert.type);
        expect(restored.path, alert.path);
        expect(restored.description, alert.description);
        expect(restored.recommendedAction, alert.recommendedAction);
        expect(restored.detectedAt, alert.detectedAt);
        expect(restored.dismissed, alert.dismissed);
        expect(restored.quarantined, alert.quarantined);
      });

      test('fromMap / toMap round-trip (SQLite)', () {
        final alert = IntegrityAlert(
          id: 'a2',
          type: IntegrityAlertType.checksumMismatch,
          path: '/some/path',
          description: 'Checksum mismatch',
          recommendedAction: 'Re-download',
          detectedAt: '2025-06-14T10:00:00Z',
          dismissed: false,
          quarantined: true,
        );

        final map = alert.toMap();
        final restored = IntegrityAlert.fromMap(map);

        expect(restored.id, alert.id);
        expect(restored.type, alert.type);
        expect(restored.quarantined, isTrue);
        expect(restored.dismissed, isFalse);
      });

      test('copyWith produces modified copy', () {
        final alert = IntegrityAlert(
          id: 'a1',
          type: IntegrityAlertType.orphanFile,
          path: '/path',
          description: 'desc',
          recommendedAction: 'action',
          detectedAt: '2025-06-14T10:00:00Z',
        );

        final dismissed = alert.copyWith(dismissed: true);

        expect(dismissed.dismissed, isTrue);
        expect(dismissed.id, alert.id);
        expect(dismissed.type, alert.type);
      });

      test('all IntegrityAlertType values are handled', () {
        // Verify all enum values round-trip through JSON.
        for (final type in IntegrityAlertType.values) {
          final alert = IntegrityAlert(
            id: 'test',
            type: type,
            path: '/test',
            description: 'test',
            recommendedAction: 'test',
            detectedAt: '2025-06-14T10:00:00Z',
          );

          final json = alert.toJson();
          final restored = IntegrityAlert.fromJson(json);
          expect(restored.type, type);
        }
      });
    });
  });
}
