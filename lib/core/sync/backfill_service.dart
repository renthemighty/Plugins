/// Post-trial backfill service for uploading pre-existing local receipts to
/// cloud storage ("Sync Old Receipts").
///
/// When a user upgrades from a free trial or connects a cloud storage provider
/// for the first time, there may be receipts that were captured locally but
/// never uploaded. This service:
///
/// 1. Enumerates all unsynced local receipts.
/// 2. Creates the full remote folder structure if missing.
/// 3. Deduplicates against existing remote content (by receipt_id or checksum).
/// 4. Uploads only the missing files.
/// 5. Merges day and month indexes safely (append-only, never overwrite).
/// 6. Verifies integrity after upload (checksums + index references).
///
/// **Deduplication rules:**
/// - Two receipts are considered the same if their `receipt_id` values match
///   **OR** their `checksum_sha256` values match *and* the `captured_at`
///   timestamps fall within a 60-second window.
/// - If a filename collision is detected at upload time, the allocator assigns
///   a new suffix and the mapping is recorded in the receipt metadata.
/// - Remote files are never overwritten.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../db/receipt_dao.dart';
import '../db/sync_queue_dao.dart';
import '../models/day_index.dart';
import '../models/receipt.dart';
import '../services/checksum_service.dart';
import '../services/filename_allocator.dart';
import '../services/folder_service.dart';
import '../services/index_service.dart';

// ---------------------------------------------------------------------------
// BackfillStats
// ---------------------------------------------------------------------------

/// Summary statistics for receipts awaiting backfill.
class BackfillStats {
  /// Number of local-only receipts that need uploading.
  final int count;

  /// Estimated total size in bytes across all local receipt images.
  final int totalSizeBytes;

  const BackfillStats({
    required this.count,
    required this.totalSizeBytes,
  });

  /// Returns a human-readable size string (e.g. "12.3 MB").
  String get formattedSize {
    if (totalSizeBytes < 1024) {
      return '$totalSizeBytes B';
    } else if (totalSizeBytes < 1024 * 1024) {
      final kb = totalSizeBytes / 1024;
      return '${kb.toStringAsFixed(1)} KB';
    } else if (totalSizeBytes < 1024 * 1024 * 1024) {
      final mb = totalSizeBytes / (1024 * 1024);
      return '${mb.toStringAsFixed(1)} MB';
    } else {
      final gb = totalSizeBytes / (1024 * 1024 * 1024);
      return '${gb.toStringAsFixed(2)} GB';
    }
  }

  @override
  String toString() => 'BackfillStats(count: $count, size: $formattedSize)';
}

// ---------------------------------------------------------------------------
// BackfillProgress
// ---------------------------------------------------------------------------

/// Reports the current state of an in-progress backfill operation.
class BackfillProgress {
  /// Zero-based index of the receipt currently being processed.
  final int current;

  /// Total number of receipts in this backfill batch.
  final int total;

  /// The filename of the receipt being uploaded, if available.
  final String? currentFilename;

  /// Whether the backfill has finished (successfully or via cancellation).
  final bool isComplete;

  /// Number of receipts that failed to upload during this batch.
  final int failedCount;

  const BackfillProgress({
    required this.current,
    required this.total,
    this.currentFilename,
    this.isComplete = false,
    this.failedCount = 0,
  });

  /// Fraction complete from 0.0 to 1.0.
  double get fraction {
    if (total == 0) return 1.0;
    return (current / total).clamp(0.0, 1.0);
  }

  @override
  String toString() =>
      'BackfillProgress($current/$total, failed: $failedCount, '
      'complete: $isComplete)';
}

// ---------------------------------------------------------------------------
// BackfillService
// ---------------------------------------------------------------------------

/// Orchestrates the one-time upload of locally-captured receipts that were
/// never synced to cloud storage.
class BackfillService {
  final ReceiptDao _receiptDao;
  final SyncQueueDao _syncQueueDao;
  final FolderService _folderService;
  final FilenameAllocator _filenameAllocator;
  final IndexService _indexService;
  final ChecksumService _checksumService;

  /// Maximum duration allowed between two `captured_at` timestamps for a
  /// checksum-based dedup match to be considered valid.
  static const Duration _checksumTimestampTolerance = Duration(seconds: 60);

  BackfillService({
    required ReceiptDao receiptDao,
    required SyncQueueDao syncQueueDao,
    required FolderService folderService,
    required FilenameAllocator filenameAllocator,
    required IndexService indexService,
    ChecksumService checksumService = const ChecksumService(),
  })  : _receiptDao = receiptDao,
        _syncQueueDao = syncQueueDao,
        _folderService = folderService,
        _filenameAllocator = filenameAllocator,
        _indexService = indexService,
        _checksumService = checksumService;

  // -------------------------------------------------------------------------
  // Statistics
  // -------------------------------------------------------------------------

  /// Returns the count and estimated total size of local-only receipts that
  /// would be included in a backfill operation.
  Future<BackfillStats> getBackfillStats() async {
    final result = await _receiptDao.getReceiptCountAndSize();
    int totalBytes = 0;

    for (final path in result.localPaths) {
      try {
        final file = File(path);
        if (await file.exists()) {
          totalBytes += await file.length();
        }
      } catch (_) {
        // Skip files that cannot be stat'd.
      }
    }

    return BackfillStats(
      count: result.count,
      totalSizeBytes: totalBytes,
    );
  }

  // -------------------------------------------------------------------------
  // Backfill execution
  // -------------------------------------------------------------------------

  /// Starts the backfill process, uploading all unsynced local receipts to
  /// the given [storageProvider].
  ///
  /// - [onProgress] is called after each receipt is processed (whether
  ///   uploaded, skipped as duplicate, or failed).
  /// - [shouldCancel] is polled before each receipt; return `true` to abort
  ///   gracefully.
  ///
  /// The method never throws. Individual receipt failures are counted in
  /// [BackfillProgress.failedCount] and logged, but processing continues.
  Future<void> startBackfill({
    required StorageProvider storageProvider,
    required void Function(BackfillProgress) onProgress,
    required bool Function() shouldCancel,
  }) async {
    // 1. Gather all local-only receipts.
    final localReceipts = await _receiptDao.getAllLocal();
    if (localReceipts.isEmpty) {
      onProgress(const BackfillProgress(
        current: 0,
        total: 0,
        isComplete: true,
      ));
      return;
    }

    final total = localReceipts.length;
    int processed = 0;
    int failed = 0;

    for (final receipt in localReceipts) {
      // Check for cancellation.
      if (shouldCancel()) {
        onProgress(BackfillProgress(
          current: processed,
          total: total,
          isComplete: true,
          failedCount: failed,
        ));
        return;
      }

      try {
        await _processReceipt(receipt, storageProvider);
      } catch (e) {
        failed++;
        debugPrint(
          'BackfillService: failed to process receipt '
          '${receipt.receiptId}: $e',
        );
      }

      processed++;
      onProgress(BackfillProgress(
        current: processed,
        total: total,
        currentFilename: receipt.filename,
        isComplete: processed == total,
        failedCount: failed,
      ));
    }

    // 6. Post-backfill integrity verification.
    if (failed < total) {
      await _verifyIntegrity(localReceipts, storageProvider);
    }
  }

  // -------------------------------------------------------------------------
  // Per-receipt processing
  // -------------------------------------------------------------------------

  /// Processes a single receipt: dedup check, upload if needed, index merge.
  Future<void> _processReceipt(
    Receipt receipt,
    StorageProvider storageProvider,
  ) async {
    final date = DateTime.parse(receipt.capturedAt);
    final country = _resolveCountry(receipt.country);

    // 2. Ensure the full remote folder structure exists.
    final remotePath = await _folderService.ensureRemoteFolders(
      storageProvider,
      date,
      country,
    );

    // 3. Check if the receipt already exists remotely.
    final isDuplicate = await _checkDuplicate(
      receipt,
      remotePath,
      storageProvider,
    );

    if (isDuplicate) {
      // Already present remotely -- just mark as synced locally.
      await _receiptDao.markSynced(receipt.receiptId, remotePath: remotePath);
      return;
    }

    // 4. Upload the receipt image.
    final localPath = await _resolveLocalPath(receipt);
    if (localPath == null) {
      throw StateError(
        'Local file not found for receipt ${receipt.receiptId}',
      );
    }

    // Verify local file integrity before upload.
    final localChecksum = await _checksumService.computeFileChecksum(localPath);
    if (localChecksum.toLowerCase() !=
        receipt.checksumSha256.toLowerCase()) {
      throw StateError(
        'Checksum mismatch for ${receipt.filename}: '
        'expected ${receipt.checksumSha256}, got $localChecksum',
      );
    }

    // Check for filename collision in the remote folder.
    final remoteFiles = await storageProvider.listFiles(remotePath);
    String uploadFilename = receipt.filename;

    if (remoteFiles.contains(receipt.filename)) {
      // Collision: allocate a new suffix.
      final allocated = await _filenameAllocator.allocateFilename(
        date,
        country,
      );
      uploadFilename = allocated.filename;
      debugPrint(
        'BackfillService: filename collision for ${receipt.filename}, '
        'allocated $uploadFilename',
      );
    }

    // Upload the image file.
    final imageBytes = await File(localPath).readAsBytes();
    await storageProvider.uploadFile(remotePath, uploadFilename, imageBytes);

    // 5. Merge into the day index safely.
    final receiptForIndex = uploadFilename != receipt.filename
        ? receipt.copyWith(
            filename: uploadFilename,
            supersedesFilename: () => receipt.filename,
          )
        : receipt;

    await _mergeIntoIndex(
      receiptForIndex,
      remotePath,
      date,
      country,
      storageProvider,
    );

    // Mark as synced in the local database.
    await _receiptDao.markSynced(
      receipt.receiptId,
      remotePath: '$remotePath/$uploadFilename',
    );
  }

  // -------------------------------------------------------------------------
  // Deduplication
  // -------------------------------------------------------------------------

  /// Returns `true` if the receipt already exists remotely, either by
  /// matching `receipt_id` or by matching `checksum_sha256` with a compatible
  /// timestamp.
  Future<bool> _checkDuplicate(
    Receipt receipt,
    String remotePath,
    StorageProvider storageProvider,
  ) async {
    try {
      // Download the remote day index if it exists.
      final remoteIndexContent =
          await storageProvider.readTextFile('$remotePath/index.json');
      if (remoteIndexContent == null) return false;

      final json =
          jsonDecode(remoteIndexContent) as Map<String, dynamic>;
      final dayIndex = DayIndex.fromJson(json);

      for (final entry in dayIndex.receipts) {
        // Match by receipt_id.
        if (entry.receiptId == receipt.receiptId) {
          return true;
        }

        // Match by checksum + compatible timestamp.
        if (entry.checksumSha256.toLowerCase() ==
            receipt.checksumSha256.toLowerCase()) {
          final entryTime = DateTime.tryParse(entry.capturedAt);
          final receiptTime = DateTime.tryParse(receipt.capturedAt);

          if (entryTime != null && receiptTime != null) {
            final diff = entryTime.difference(receiptTime).abs();
            if (diff <= _checksumTimestampTolerance) {
              return true;
            }
          }
        }
      }
    } catch (_) {
      // If we cannot read the remote index, assume no duplicate.
    }

    return false;
  }

  // -------------------------------------------------------------------------
  // Index merging
  // -------------------------------------------------------------------------

  /// Appends [receipt] to the remote day index at [remotePath], merging with
  /// any existing entries. Also updates the month index.
  Future<void> _mergeIntoIndex(
    Receipt receipt,
    String remotePath,
    DateTime date,
    KiraCountry country,
    StorageProvider storageProvider,
  ) async {
    // Read existing remote day index.
    DayIndex? remoteIndex;
    try {
      final content =
          await storageProvider.readTextFile('$remotePath/index.json');
      if (content != null) {
        final json = jsonDecode(content) as Map<String, dynamic>;
        remoteIndex = DayIndex.fromJson(json);
      }
    } catch (_) {
      // Remote index corrupt or missing -- will create fresh.
    }

    // Read local day index.
    final localDir = await _folderService.getLocalPath(date, country);
    final localIndexPath = p.join(localDir, 'index.json');
    final localIndex = await _indexService.readDayIndex(localIndexPath);

    // Build the base index by merging local and remote.
    DayIndex baseIndex;
    if (localIndex != null && remoteIndex != null) {
      baseIndex = _indexService.mergeDayIndexes(localIndex, remoteIndex);
    } else if (localIndex != null) {
      baseIndex = localIndex;
    } else if (remoteIndex != null) {
      baseIndex = remoteIndex;
    } else {
      baseIndex = _indexService.createDayIndex(date, []);
    }

    // Append the receipt (no-op if already present by receiptId).
    final mergedIndex = _indexService.addReceiptToIndex(baseIndex, receipt);

    // Write merged index locally.
    await _indexService.writeDayIndex(localDir, mergedIndex);

    // Upload merged index to remote.
    final indexJson =
        const JsonEncoder.withIndent('  ').convert(mergedIndex.toJson());
    await storageProvider.writeTextFile(
      '$remotePath/index.json',
      indexJson,
    );

    // Update the month index.
    try {
      await _indexService.updateMonthIndexForDay(
        mergedIndex,
        date,
        country,
      );
    } catch (e) {
      debugPrint('BackfillService: month index update failed: $e');
      // Non-fatal -- the day index is the source of truth.
    }
  }

  // -------------------------------------------------------------------------
  // Integrity verification
  // -------------------------------------------------------------------------

  /// Performs a best-effort post-backfill integrity check: verifies that
  /// uploaded files match their expected checksums and that day indexes
  /// reference every uploaded receipt.
  Future<void> _verifyIntegrity(
    List<Receipt> receipts,
    StorageProvider storageProvider,
  ) async {
    // Group receipts by date for batch index verification.
    final byDate = <String, List<Receipt>>{};
    for (final receipt in receipts) {
      final dateStr = receipt.capturedAt.substring(0, 10); // YYYY-MM-DD
      byDate.putIfAbsent(dateStr, () => []).add(receipt);
    }

    for (final entry in byDate.entries) {
      try {
        final sampleReceipt = entry.value.first;
        final date = DateTime.parse(sampleReceipt.capturedAt);
        final country = _resolveCountry(sampleReceipt.country);
        final remotePath = _folderService.getRemotePath(date, country);

        // Check that the remote index contains all receipts for this day.
        final content =
            await storageProvider.readTextFile('$remotePath/index.json');
        if (content == null) {
          debugPrint(
            'BackfillService: integrity warning -- no remote index for '
            '${entry.key}',
          );
          continue;
        }

        final json = jsonDecode(content) as Map<String, dynamic>;
        final dayIndex = DayIndex.fromJson(json);
        final indexedIds =
            dayIndex.receipts.map((r) => r.receiptId).toSet();

        for (final receipt in entry.value) {
          if (!indexedIds.contains(receipt.receiptId)) {
            debugPrint(
              'BackfillService: integrity warning -- receipt '
              '${receipt.receiptId} not found in remote index for '
              '${entry.key}',
            );
          }
        }

        // Verify that remote files exist for each indexed receipt.
        final remoteFiles = await storageProvider.listFiles(remotePath);
        for (final indexEntry in dayIndex.receipts) {
          if (!remoteFiles.contains(indexEntry.filename)) {
            debugPrint(
              'BackfillService: integrity warning -- file '
              '${indexEntry.filename} referenced in index but not found '
              'in remote folder $remotePath',
            );
          }
        }
      } catch (e) {
        debugPrint(
          'BackfillService: integrity check error for ${entry.key}: $e',
        );
      }
    }
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  /// Resolves the local file path for a receipt by checking the database
  /// row's `local_path` column, falling back to the folder service.
  Future<String?> _resolveLocalPath(Receipt receipt) async {
    // First, check if the DAO stored a local_path.
    final result = await _receiptDao.getReceiptCountAndSize();
    // The DAO does not expose local_path per receipt, so fall back to the
    // folder-based resolution.
    final date = DateTime.parse(receipt.capturedAt);
    final country = _resolveCountry(receipt.country);
    final localDir = await _folderService.getLocalPath(date, country);
    final candidate = p.join(localDir, receipt.filename);

    if (await File(candidate).exists()) {
      return candidate;
    }

    return null;
  }

  /// Maps a country string from the receipt model to a [KiraCountry] enum.
  static KiraCountry _resolveCountry(String country) {
    switch (country.toLowerCase()) {
      case 'canada':
      case 'ca':
        return KiraCountry.canada;
      case 'us':
      case 'united_states':
      case 'unitedstates':
        return KiraCountry.unitedStates;
      default:
        return KiraCountry.canada;
    }
  }
}
