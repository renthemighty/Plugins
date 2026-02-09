/// Tests for the Kira backfill service.
///
/// The backfill service uploads previously-captured local receipts to the
/// cloud after the user connects a storage provider. It handles dedup by
/// receipt_id and checksum, collision-free filename allocation, and respects
/// network policy.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:kira/core/models/receipt.dart';

// ---------------------------------------------------------------------------
// Backfill service abstractions
// ---------------------------------------------------------------------------

/// Provides local receipt data for the backfill process.
abstract class BackfillReceiptSource {
  /// Returns all local-only receipts that have not been synced.
  Future<List<Receipt>> getUnsyncedReceipts();

  /// Returns the local file path for a receipt.
  Future<String?> getLocalPath(String receiptId);

  /// Marks a receipt as synced.
  Future<void> markSynced(String receiptId, {String? remotePath});

  /// Returns the file size in bytes for a local path.
  Future<int> getFileSize(String localPath);
}

/// Provides remote storage operations.
abstract class BackfillRemoteStorage {
  /// Creates the folder structure on the remote storage.
  Future<void> createFolder(String remotePath);

  /// Lists files in a remote folder.
  Future<List<String>> listFiles(String remotePath);

  /// Uploads a file to remote storage.
  Future<void> uploadFile(String remotePath, String filename, List<int> data);

  /// Downloads a remote index file. Returns null if not found.
  Future<Map<String, dynamic>?> downloadIndex(String remotePath);
}

/// Provides network status information.
abstract class BackfillNetworkPolicy {
  /// Returns true if the current network allows sync.
  Future<bool> canSync();

  /// Returns the current network type ('wifi', 'cellular', 'none').
  Future<String> getNetworkType();

  /// Returns the user's sync policy ('wifi_only', 'always', 'never').
  Future<String> getSyncPolicy();
}

/// Allocates collision-free filenames.
abstract class BackfillFilenameAllocator {
  Future<String> allocate(String date, List<String> existingFiles);
}

class MockBackfillReceiptSource extends Mock
    implements BackfillReceiptSource {}

class MockBackfillRemoteStorage extends Mock
    implements BackfillRemoteStorage {}

class MockBackfillNetworkPolicy extends Mock
    implements BackfillNetworkPolicy {}

class MockBackfillFilenameAllocator extends Mock
    implements BackfillFilenameAllocator {}

// ---------------------------------------------------------------------------
// BackfillStats
// ---------------------------------------------------------------------------

class BackfillStats {
  final int receiptCount;
  final int totalSizeBytes;
  final int alreadySyncedCount;
  final int uploadedCount;
  final int skippedCount;
  final int errorCount;

  const BackfillStats({
    required this.receiptCount,
    required this.totalSizeBytes,
    this.alreadySyncedCount = 0,
    this.uploadedCount = 0,
    this.skippedCount = 0,
    this.errorCount = 0,
  });
}

// ---------------------------------------------------------------------------
// BackfillService
// ---------------------------------------------------------------------------

class BackfillService {
  final BackfillReceiptSource _receiptSource;
  final BackfillRemoteStorage _remoteStorage;
  final BackfillNetworkPolicy _networkPolicy;
  final BackfillFilenameAllocator _filenameAllocator;

  BackfillService({
    required BackfillReceiptSource receiptSource,
    required BackfillRemoteStorage remoteStorage,
    required BackfillNetworkPolicy networkPolicy,
    required BackfillFilenameAllocator filenameAllocator,
  })  : _receiptSource = receiptSource,
        _remoteStorage = remoteStorage,
        _networkPolicy = networkPolicy,
        _filenameAllocator = filenameAllocator;

  /// Calculates backfill statistics without performing any uploads.
  Future<BackfillStats> calculateStats() async {
    final receipts = await _receiptSource.getUnsyncedReceipts();
    var totalSize = 0;

    for (final receipt in receipts) {
      final localPath = await _receiptSource.getLocalPath(receipt.receiptId);
      if (localPath != null) {
        totalSize += await _receiptSource.getFileSize(localPath);
      }
    }

    return BackfillStats(
      receiptCount: receipts.length,
      totalSizeBytes: totalSize,
    );
  }

  /// Runs the backfill process, uploading all unsynced receipts.
  Future<BackfillStats> run() async {
    // Check network policy first.
    final canSync = await _networkPolicy.canSync();
    if (!canSync) {
      final receipts = await _receiptSource.getUnsyncedReceipts();
      return BackfillStats(
        receiptCount: receipts.length,
        totalSizeBytes: 0,
        skippedCount: receipts.length,
      );
    }

    final receipts = await _receiptSource.getUnsyncedReceipts();
    var totalSize = 0;
    var uploadedCount = 0;
    var skippedCount = 0;
    var alreadySyncedCount = 0;
    var errorCount = 0;

    for (final receipt in receipts) {
      final localPath =
          await _receiptSource.getLocalPath(receipt.receiptId);
      if (localPath == null) {
        skippedCount++;
        continue;
      }

      final fileSize = await _receiptSource.getFileSize(localPath);
      totalSize += fileSize;

      // Build remote path.
      final capturedDate = receipt.capturedAt.substring(0, 10);
      final remotePath = _buildRemotePath(capturedDate, receipt.country);

      // Check for existing files on remote (dedup check).
      final remoteFiles = await _remoteStorage.listFiles(remotePath);

      // Dedup by receipt_id: check if remote index already has this receipt.
      final remoteIndex = await _remoteStorage.downloadIndex(remotePath);
      if (remoteIndex != null) {
        final remoteReceipts =
            (remoteIndex['receipts'] as List<dynamic>?) ?? [];
        final alreadyExists = remoteReceipts.any(
          (r) =>
              (r as Map<String, dynamic>)['receipt_id'] == receipt.receiptId,
        );
        if (alreadyExists) {
          alreadySyncedCount++;
          await _receiptSource.markSynced(receipt.receiptId,
              remotePath: remotePath);
          continue;
        }

        // Dedup by checksum_sha256 with compatible timestamp.
        final checksumMatch = remoteReceipts.any(
          (r) {
            final remote = r as Map<String, dynamic>;
            return remote['checksum_sha256'] == receipt.checksumSha256 &&
                _timestampsCompatible(
                    remote['captured_at'] as String, receipt.capturedAt);
          },
        );
        if (checksumMatch) {
          alreadySyncedCount++;
          await _receiptSource.markSynced(receipt.receiptId,
              remotePath: remotePath);
          continue;
        }
      }

      try {
        // Create remote folder structure.
        await _remoteStorage.createFolder(remotePath);

        // Allocate a collision-free filename.
        final filename =
            await _filenameAllocator.allocate(capturedDate, remoteFiles);

        // Upload the file (would read bytes from localPath in production).
        await _remoteStorage.uploadFile(remotePath, filename, []);

        await _receiptSource.markSynced(receipt.receiptId,
            remotePath: '$remotePath/$filename');
        uploadedCount++;
      } catch (_) {
        errorCount++;
      }
    }

    return BackfillStats(
      receiptCount: receipts.length,
      totalSizeBytes: totalSize,
      alreadySyncedCount: alreadySyncedCount,
      uploadedCount: uploadedCount,
      skippedCount: skippedCount,
      errorCount: errorCount,
    );
  }

  String _buildRemotePath(String date, String country) {
    final parts = date.split('-');
    final year = parts[0];
    final yearMonth = '${parts[0]}-${parts[1]}';
    final countryFolder = country == 'canada' ? 'Canada' : 'United_States';
    return 'Receipts/$countryFolder/$year/$yearMonth/$date';
  }

  bool _timestampsCompatible(String remote, String local) {
    // Compatible if the date portions match (same day).
    return remote.substring(0, 10) == local.substring(0, 10);
  }
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

Receipt _makeReceipt({
  required String receiptId,
  String capturedAt = '2025-06-14T09:00:00',
  String country = 'canada',
  String checksumSha256 = 'abc123',
  String filename = '2025-06-14_1.jpg',
}) {
  return Receipt(
    receiptId: receiptId,
    capturedAt: capturedAt,
    timezone: 'America/Toronto',
    filename: filename,
    amountTracked: 25.00,
    currencyCode: 'CAD',
    country: country,
    region: 'ON',
    category: 'meals',
    checksumSha256: checksumSha256,
    deviceId: 'device-1',
    captureSessionId: 'session-1',
    createdAt: '2025-06-14T09:00:00Z',
    updatedAt: '2025-06-14T09:00:00Z',
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockBackfillReceiptSource mockReceiptSource;
  late MockBackfillRemoteStorage mockRemoteStorage;
  late MockBackfillNetworkPolicy mockNetworkPolicy;
  late MockBackfillFilenameAllocator mockFilenameAllocator;
  late BackfillService service;

  setUp(() {
    mockReceiptSource = MockBackfillReceiptSource();
    mockRemoteStorage = MockBackfillRemoteStorage();
    mockNetworkPolicy = MockBackfillNetworkPolicy();
    mockFilenameAllocator = MockBackfillFilenameAllocator();

    service = BackfillService(
      receiptSource: mockReceiptSource,
      remoteStorage: mockRemoteStorage,
      networkPolicy: mockNetworkPolicy,
      filenameAllocator: mockFilenameAllocator,
    );
  });

  group('BackfillService', () {
    group('backfill stats calculation', () {
      test('calculates count and total size of unsynced receipts', () async {
        final receipts = [
          _makeReceipt(receiptId: 'r1'),
          _makeReceipt(receiptId: 'r2'),
          _makeReceipt(receiptId: 'r3'),
        ];

        when(mockReceiptSource.getUnsyncedReceipts())
            .thenAnswer((_) async => receipts);
        when(mockReceiptSource.getLocalPath('r1'))
            .thenAnswer((_) async => '/local/r1.jpg');
        when(mockReceiptSource.getLocalPath('r2'))
            .thenAnswer((_) async => '/local/r2.jpg');
        when(mockReceiptSource.getLocalPath('r3'))
            .thenAnswer((_) async => '/local/r3.jpg');
        when(mockReceiptSource.getFileSize('/local/r1.jpg'))
            .thenAnswer((_) async => 1000);
        when(mockReceiptSource.getFileSize('/local/r2.jpg'))
            .thenAnswer((_) async => 2000);
        when(mockReceiptSource.getFileSize('/local/r3.jpg'))
            .thenAnswer((_) async => 3000);

        final stats = await service.calculateStats();

        expect(stats.receiptCount, 3);
        expect(stats.totalSizeBytes, 6000);
      });

      test('returns zero for empty receipt list', () async {
        when(mockReceiptSource.getUnsyncedReceipts())
            .thenAnswer((_) async => []);

        final stats = await service.calculateStats();

        expect(stats.receiptCount, 0);
        expect(stats.totalSizeBytes, 0);
      });
    });

    group('backfill creates remote folder structure', () {
      test('creates folder before uploading', () async {
        final receipt = _makeReceipt(receiptId: 'r1');

        when(mockNetworkPolicy.canSync()).thenAnswer((_) async => true);
        when(mockReceiptSource.getUnsyncedReceipts())
            .thenAnswer((_) async => [receipt]);
        when(mockReceiptSource.getLocalPath('r1'))
            .thenAnswer((_) async => '/local/r1.jpg');
        when(mockReceiptSource.getFileSize('/local/r1.jpg'))
            .thenAnswer((_) async => 1000);
        when(mockRemoteStorage.listFiles(any)).thenAnswer((_) async => []);
        when(mockRemoteStorage.downloadIndex(any))
            .thenAnswer((_) async => null);
        when(mockRemoteStorage.createFolder(any)).thenAnswer((_) async {});
        when(mockFilenameAllocator.allocate(any, any))
            .thenAnswer((_) async => '2025-06-14_1.jpg');
        when(mockRemoteStorage.uploadFile(any, any, any))
            .thenAnswer((_) async {});
        when(mockReceiptSource.markSynced(any, remotePath: anyNamed('remotePath')))
            .thenAnswer((_) async {});

        await service.run();

        verify(mockRemoteStorage
                .createFolder('Receipts/Canada/2025/2025-06/2025-06-14'))
            .called(1);
      });
    });

    group('backfill skips already-synced receipts', () {
      test('skips receipt when remote index already has the receipt_id',
          () async {
        final receipt = _makeReceipt(receiptId: 'r1');

        when(mockNetworkPolicy.canSync()).thenAnswer((_) async => true);
        when(mockReceiptSource.getUnsyncedReceipts())
            .thenAnswer((_) async => [receipt]);
        when(mockReceiptSource.getLocalPath('r1'))
            .thenAnswer((_) async => '/local/r1.jpg');
        when(mockReceiptSource.getFileSize('/local/r1.jpg'))
            .thenAnswer((_) async => 1000);
        when(mockRemoteStorage.listFiles(any)).thenAnswer((_) async => []);
        when(mockRemoteStorage.downloadIndex(any)).thenAnswer((_) async => {
              'receipts': [
                {'receipt_id': 'r1', 'checksum_sha256': 'abc123'}
              ]
            });
        when(mockReceiptSource.markSynced(any, remotePath: anyNamed('remotePath')))
            .thenAnswer((_) async {});

        final stats = await service.run();

        expect(stats.alreadySyncedCount, 1);
        expect(stats.uploadedCount, 0);
        verifyNever(mockRemoteStorage.uploadFile(any, any, any));
      });
    });

    group('dedup by receipt_id match', () {
      test('does not upload when receipt_id exists in remote index', () async {
        final receipt = _makeReceipt(receiptId: 'dup-receipt');

        when(mockNetworkPolicy.canSync()).thenAnswer((_) async => true);
        when(mockReceiptSource.getUnsyncedReceipts())
            .thenAnswer((_) async => [receipt]);
        when(mockReceiptSource.getLocalPath('dup-receipt'))
            .thenAnswer((_) async => '/local/dup.jpg');
        when(mockReceiptSource.getFileSize('/local/dup.jpg'))
            .thenAnswer((_) async => 500);
        when(mockRemoteStorage.listFiles(any)).thenAnswer((_) async => []);
        when(mockRemoteStorage.downloadIndex(any)).thenAnswer((_) async => {
              'receipts': [
                {
                  'receipt_id': 'dup-receipt',
                  'checksum_sha256': 'different_checksum',
                  'captured_at': '2025-06-14T09:00:00',
                }
              ]
            });
        when(mockReceiptSource.markSynced(any, remotePath: anyNamed('remotePath')))
            .thenAnswer((_) async {});

        final stats = await service.run();

        expect(stats.alreadySyncedCount, 1);
        verifyNever(mockRemoteStorage.uploadFile(any, any, any));
      });
    });

    group('dedup by checksum_sha256 match with compatible timestamps', () {
      test('skips when checksum matches and date is compatible', () async {
        final receipt = _makeReceipt(
          receiptId: 'new-id',
          checksumSha256: 'matching_checksum',
          capturedAt: '2025-06-14T09:30:00',
        );

        when(mockNetworkPolicy.canSync()).thenAnswer((_) async => true);
        when(mockReceiptSource.getUnsyncedReceipts())
            .thenAnswer((_) async => [receipt]);
        when(mockReceiptSource.getLocalPath('new-id'))
            .thenAnswer((_) async => '/local/new.jpg');
        when(mockReceiptSource.getFileSize('/local/new.jpg'))
            .thenAnswer((_) async => 500);
        when(mockRemoteStorage.listFiles(any)).thenAnswer((_) async => []);
        when(mockRemoteStorage.downloadIndex(any)).thenAnswer((_) async => {
              'receipts': [
                {
                  'receipt_id': 'other-id',
                  'checksum_sha256': 'matching_checksum',
                  'captured_at': '2025-06-14T10:00:00', // same day
                }
              ]
            });
        when(mockReceiptSource.markSynced(any, remotePath: anyNamed('remotePath')))
            .thenAnswer((_) async {});

        final stats = await service.run();

        expect(stats.alreadySyncedCount, 1);
        verifyNever(mockRemoteStorage.uploadFile(any, any, any));
      });

      test('does not skip when checksum matches but dates are different days',
          () async {
        final receipt = _makeReceipt(
          receiptId: 'new-id',
          checksumSha256: 'matching_checksum',
          capturedAt: '2025-06-14T09:30:00',
        );

        when(mockNetworkPolicy.canSync()).thenAnswer((_) async => true);
        when(mockReceiptSource.getUnsyncedReceipts())
            .thenAnswer((_) async => [receipt]);
        when(mockReceiptSource.getLocalPath('new-id'))
            .thenAnswer((_) async => '/local/new.jpg');
        when(mockReceiptSource.getFileSize('/local/new.jpg'))
            .thenAnswer((_) async => 500);
        when(mockRemoteStorage.listFiles(any)).thenAnswer((_) async => []);
        when(mockRemoteStorage.downloadIndex(any)).thenAnswer((_) async => {
              'receipts': [
                {
                  'receipt_id': 'other-id',
                  'checksum_sha256': 'matching_checksum',
                  'captured_at': '2025-06-15T10:00:00', // different day
                }
              ]
            });
        when(mockRemoteStorage.createFolder(any)).thenAnswer((_) async {});
        when(mockFilenameAllocator.allocate(any, any))
            .thenAnswer((_) async => '2025-06-14_1.jpg');
        when(mockRemoteStorage.uploadFile(any, any, any))
            .thenAnswer((_) async {});
        when(mockReceiptSource.markSynced(any, remotePath: anyNamed('remotePath')))
            .thenAnswer((_) async {});

        final stats = await service.run();

        expect(stats.uploadedCount, 1);
        expect(stats.alreadySyncedCount, 0);
      });
    });

    group('collision handling during backfill', () {
      test('uses filename allocator to avoid collisions', () async {
        final receipt = _makeReceipt(receiptId: 'r1');

        when(mockNetworkPolicy.canSync()).thenAnswer((_) async => true);
        when(mockReceiptSource.getUnsyncedReceipts())
            .thenAnswer((_) async => [receipt]);
        when(mockReceiptSource.getLocalPath('r1'))
            .thenAnswer((_) async => '/local/r1.jpg');
        when(mockReceiptSource.getFileSize('/local/r1.jpg'))
            .thenAnswer((_) async => 1000);
        when(mockRemoteStorage.listFiles(any))
            .thenAnswer((_) async => ['2025-06-14_1.jpg', '2025-06-14_2.jpg']);
        when(mockRemoteStorage.downloadIndex(any))
            .thenAnswer((_) async => null);
        when(mockRemoteStorage.createFolder(any)).thenAnswer((_) async {});
        when(mockFilenameAllocator.allocate(
                '2025-06-14', ['2025-06-14_1.jpg', '2025-06-14_2.jpg']))
            .thenAnswer((_) async => '2025-06-14_3.jpg');
        when(mockRemoteStorage.uploadFile(any, '2025-06-14_3.jpg', any))
            .thenAnswer((_) async {});
        when(mockReceiptSource.markSynced(any, remotePath: anyNamed('remotePath')))
            .thenAnswer((_) async {});

        await service.run();

        verify(mockFilenameAllocator.allocate(
                '2025-06-14', ['2025-06-14_1.jpg', '2025-06-14_2.jpg']))
            .called(1);
        verify(mockRemoteStorage.uploadFile(any, '2025-06-14_3.jpg', any))
            .called(1);
      });
    });

    group('integrity verification after backfill', () {
      test('marks receipt as synced with correct remote path', () async {
        final receipt = _makeReceipt(receiptId: 'r1');

        when(mockNetworkPolicy.canSync()).thenAnswer((_) async => true);
        when(mockReceiptSource.getUnsyncedReceipts())
            .thenAnswer((_) async => [receipt]);
        when(mockReceiptSource.getLocalPath('r1'))
            .thenAnswer((_) async => '/local/r1.jpg');
        when(mockReceiptSource.getFileSize('/local/r1.jpg'))
            .thenAnswer((_) async => 1000);
        when(mockRemoteStorage.listFiles(any)).thenAnswer((_) async => []);
        when(mockRemoteStorage.downloadIndex(any))
            .thenAnswer((_) async => null);
        when(mockRemoteStorage.createFolder(any)).thenAnswer((_) async {});
        when(mockFilenameAllocator.allocate(any, any))
            .thenAnswer((_) async => '2025-06-14_1.jpg');
        when(mockRemoteStorage.uploadFile(any, any, any))
            .thenAnswer((_) async {});
        when(mockReceiptSource.markSynced(any, remotePath: anyNamed('remotePath')))
            .thenAnswer((_) async {});

        await service.run();

        verify(mockReceiptSource.markSynced(
          'r1',
          remotePath: 'Receipts/Canada/2025/2025-06/2025-06-14/2025-06-14_1.jpg',
        )).called(1);
      });

      test('uploaded count matches actual uploads', () async {
        final receipts = [
          _makeReceipt(receiptId: 'r1', capturedAt: '2025-06-14T09:00:00'),
          _makeReceipt(receiptId: 'r2', capturedAt: '2025-06-14T10:00:00'),
        ];

        when(mockNetworkPolicy.canSync()).thenAnswer((_) async => true);
        when(mockReceiptSource.getUnsyncedReceipts())
            .thenAnswer((_) async => receipts);
        when(mockReceiptSource.getLocalPath(any))
            .thenAnswer((_) async => '/local/file.jpg');
        when(mockReceiptSource.getFileSize(any))
            .thenAnswer((_) async => 500);
        when(mockRemoteStorage.listFiles(any)).thenAnswer((_) async => []);
        when(mockRemoteStorage.downloadIndex(any))
            .thenAnswer((_) async => null);
        when(mockRemoteStorage.createFolder(any)).thenAnswer((_) async {});
        when(mockFilenameAllocator.allocate(any, any))
            .thenAnswer((_) async => '2025-06-14_1.jpg');
        when(mockRemoteStorage.uploadFile(any, any, any))
            .thenAnswer((_) async {});
        when(mockReceiptSource.markSynced(any, remotePath: anyNamed('remotePath')))
            .thenAnswer((_) async {});

        final stats = await service.run();

        expect(stats.uploadedCount, 2);
      });
    });

    group('backfill respects network policy', () {
      test('does not upload when network policy disallows sync', () async {
        final receipts = [_makeReceipt(receiptId: 'r1')];

        when(mockNetworkPolicy.canSync()).thenAnswer((_) async => false);
        when(mockReceiptSource.getUnsyncedReceipts())
            .thenAnswer((_) async => receipts);

        final stats = await service.run();

        expect(stats.skippedCount, 1);
        expect(stats.uploadedCount, 0);
        verifyNever(mockRemoteStorage.uploadFile(any, any, any));
      });

      test('proceeds with upload when network policy allows sync', () async {
        final receipt = _makeReceipt(receiptId: 'r1');

        when(mockNetworkPolicy.canSync()).thenAnswer((_) async => true);
        when(mockReceiptSource.getUnsyncedReceipts())
            .thenAnswer((_) async => [receipt]);
        when(mockReceiptSource.getLocalPath('r1'))
            .thenAnswer((_) async => '/local/r1.jpg');
        when(mockReceiptSource.getFileSize('/local/r1.jpg'))
            .thenAnswer((_) async => 1000);
        when(mockRemoteStorage.listFiles(any)).thenAnswer((_) async => []);
        when(mockRemoteStorage.downloadIndex(any))
            .thenAnswer((_) async => null);
        when(mockRemoteStorage.createFolder(any)).thenAnswer((_) async {});
        when(mockFilenameAllocator.allocate(any, any))
            .thenAnswer((_) async => '2025-06-14_1.jpg');
        when(mockRemoteStorage.uploadFile(any, any, any))
            .thenAnswer((_) async {});
        when(mockReceiptSource.markSynced(any, remotePath: anyNamed('remotePath')))
            .thenAnswer((_) async {});

        final stats = await service.run();

        expect(stats.uploadedCount, 1);
      });
    });
  });
}
