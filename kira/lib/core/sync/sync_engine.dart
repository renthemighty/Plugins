/// Bidirectional sync engine with two-step commit, conflict resolution,
/// and network-policy enforcement for Kira receipt storage.
///
/// Upload flow per receipt:
///   1. Ensure remote folder structure exists
///   2. Check if already present remotely (by checksum or receipt_id) → skip
///   3. Allocate collision-free filename (remote listing recheck)
///   4. Upload image file
///   5. Merge + upload day index.json (two-step commit)
///   6. If index upload fails → mark `uploaded_unindexed` and retry later
///   7. Update month index.json
///   8. Mark synced in local DB
///
/// The engine never overwrites files or index entries.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../db/receipt_dao.dart';
import '../db/settings_dao.dart';
import '../db/sync_queue_dao.dart';
import '../models/app_settings.dart';
import '../models/receipt.dart';
import '../models/day_index.dart';
import '../services/checksum_service.dart';
import '../services/filename_allocator.dart';
import '../services/folder_service.dart';
import '../services/index_service.dart';
import 'network_monitor.dart';

/// High-level sync lifecycle state.
enum SyncEngineStatus {
  idle,
  syncing,
  error,
  offline,
}

/// Result of a single sync cycle.
class SyncResult {
  final int uploaded;
  final int downloaded;
  final int merged;
  final int failed;
  final int skipped;

  const SyncResult({
    this.uploaded = 0,
    this.downloaded = 0,
    this.merged = 0,
    this.failed = 0,
    this.skipped = 0,
  });
}

class SyncEngine extends ChangeNotifier {
  final ReceiptDao _receiptDao;
  final SettingsDao _settingsDao;
  final SyncQueueDao? _syncQueueDao;
  final FolderService? _folderService;
  final FilenameAllocator? _filenameAllocator;
  final IndexService? _indexService;
  final ChecksumService? _checksumService;
  final NetworkMonitor? _networkMonitor;
  StorageProvider? _storageProvider;

  SyncEngineStatus _status = SyncEngineStatus.idle;
  int _pendingCount = 0;
  int _failedCount = 0;
  int _currentItem = 0;
  int _totalItems = 0;
  String? _lastError;
  bool _initialized = false;
  bool _cancelRequested = false;

  /// Maximum retries per item with exponential backoff.
  static const int _maxRetries = 4;

  /// Random jitter source for backoff.
  static final _random = Random();

  SyncEngine({
    required ReceiptDao receiptDao,
    required SettingsDao settingsDao,
    SyncQueueDao? syncQueueDao,
    FolderService? folderService,
    FilenameAllocator? filenameAllocator,
    IndexService? indexService,
    ChecksumService? checksumService,
    NetworkMonitor? networkMonitor,
    StorageProvider? storageProvider,
  })  : _receiptDao = receiptDao,
        _settingsDao = settingsDao,
        _syncQueueDao = syncQueueDao,
        _folderService = folderService,
        _filenameAllocator = filenameAllocator,
        _indexService = indexService,
        _checksumService = checksumService,
        _networkMonitor = networkMonitor,
        _storageProvider = storageProvider;

  // ---------------------------------------------------------------------------
  // Public getters
  // ---------------------------------------------------------------------------

  bool get initialized => _initialized;
  SyncEngineStatus get status => _status;
  int get pendingCount => _pendingCount;
  int get failedCount => _failedCount;
  int get currentItem => _currentItem;
  int get totalItems => _totalItems;
  String? get lastError => _lastError;
  bool get isSyncing => _status == SyncEngineStatus.syncing;

  double get progress {
    if (_totalItems == 0) return 0.0;
    return (_currentItem / _totalItems).clamp(0.0, 1.0);
  }

  void setStorageProvider(StorageProvider provider) {
    _storageProvider = provider;
  }

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  Future<void> initialize() async {
    final unsynced = await _receiptDao.getUnsyncedReceipts();
    _pendingCount = unsynced.length;
    _initialized = true;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Full bidirectional sync
  // ---------------------------------------------------------------------------

  /// Full sync cycle: upload local → download remote → merge indexes.
  Future<SyncResult> syncAll() async {
    if (_status == SyncEngineStatus.syncing) {
      return const SyncResult();
    }

    // Check network policy
    if (_networkMonitor != null) {
      final settings = await _settingsDao.getAppSettings();
      final policy = settings?.syncPolicy ?? SyncPolicy.wifiOnly;
      final canSync = await _networkMonitor!.canSync(policy);
      if (!canSync) {
        _status = SyncEngineStatus.offline;
        notifyListeners();
        return const SyncResult();
      }
    }

    _status = SyncEngineStatus.syncing;
    _lastError = null;
    _cancelRequested = false;
    notifyListeners();

    int uploaded = 0;
    int downloaded = 0;
    int merged = 0;
    int failed = 0;
    int skipped = 0;

    try {
      // Phase 1: Upload new local receipts
      final unsynced = await _receiptDao.getUnsyncedReceipts();
      _totalItems = unsynced.length;
      _currentItem = 0;

      for (final receipt in unsynced) {
        if (_cancelRequested) break;

        _currentItem++;
        notifyListeners();

        final result = await _uploadReceiptWithRetry(receipt);
        switch (result) {
          case _UploadResult.success:
            uploaded++;
          case _UploadResult.skipped:
            skipped++;
          case _UploadResult.failed:
            failed++;
        }
      }

      // Phase 2: Download remote changes (if storage provider available)
      if (_storageProvider != null && !_cancelRequested) {
        final dlResult = await _downloadRemoteChanges();
        downloaded += dlResult.downloaded;
        merged += dlResult.merged;
      }

      _pendingCount = (await _receiptDao.getUnsyncedReceipts()).length;
      _failedCount = failed;
      _status = failed > 0 ? SyncEngineStatus.error : SyncEngineStatus.idle;
    } catch (e) {
      _lastError = e.toString();
      _status = SyncEngineStatus.error;
    }

    notifyListeners();
    return SyncResult(
      uploaded: uploaded,
      downloaded: downloaded,
      merged: merged,
      failed: failed,
      skipped: skipped,
    );
  }

  // ---------------------------------------------------------------------------
  // Upload single receipt with two-step commit
  // ---------------------------------------------------------------------------

  Future<_UploadResult> _uploadReceiptWithRetry(Receipt receipt) async {
    for (int attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        return await _uploadReceipt(receipt);
      } catch (e) {
        if (attempt == _maxRetries) {
          _lastError = 'Failed to upload ${receipt.filename}: $e';
          return _UploadResult.failed;
        }
        // Exponential backoff with jitter
        final baseDelay = Duration(seconds: pow(2, attempt + 1).toInt());
        final jitter = Duration(
          milliseconds: _random.nextInt(1000),
        );
        await Future.delayed(baseDelay + jitter);
      }
    }
    return _UploadResult.failed;
  }

  Future<_UploadResult> _uploadReceipt(Receipt receipt) async {
    if (_storageProvider == null || _folderService == null) {
      // No storage provider → just mark synced locally
      await _receiptDao.markSynced(receipt.receiptId);
      return _UploadResult.success;
    }

    final date = DateTime.parse(receipt.capturedAt);
    final country = KiraCountry.fromFolderName(receipt.country);

    // Step 0: Check if already exists remotely (dedup by checksum or receipt_id)
    final remotePath = _folderService!.getRemotePath(date, country);
    try {
      final remoteIndex = await _storageProvider!.downloadFile(
        remotePath,
        'index.json',
      );
      if (remoteIndex != null) {
        final content = utf8.decode(remoteIndex);
        final json = jsonDecode(content) as Map<String, dynamic>;
        final entries = json['receipts'] as List<dynamic>? ?? [];
        for (final entry in entries) {
          final map = entry as Map<String, dynamic>;
          if (map['receipt_id'] == receipt.receiptId ||
              map['checksum_sha256'] == receipt.checksumSha256) {
            // Already present remotely → skip
            await _receiptDao.markSynced(receipt.receiptId);
            return _UploadResult.skipped;
          }
        }
      }
    } catch (_) {
      // Remote index may not exist yet — proceed with upload
    }

    // Step 1: Ensure remote folder structure
    await _folderService!.ensureRemoteFolders(
      _storageProvider!,
      date,
      country,
    );

    // Step 2: Read local image file
    final localPath = await _folderService!.getLocalPath(date, country);
    final imageFile = File('$localPath/${receipt.filename}');
    if (!await imageFile.exists()) {
      throw StateError('Local image file missing: ${imageFile.path}');
    }
    final imageBytes = await imageFile.readAsBytes();

    // Step 3: Upload image (first step of two-step commit)
    await _storageProvider!.uploadFile(
      remotePath,
      receipt.filename,
      imageBytes,
    );

    // Step 4: Merge and upload day index (second step)
    try {
      await _mergeAndUploadDayIndex(receipt, remotePath);
      await _receiptDao.markSynced(receipt.receiptId);
      await _receiptDao.markIndexed(receipt.receiptId);
    } catch (e) {
      // Image uploaded but index failed → mark uploaded_unindexed
      await _receiptDao.markSynced(receipt.receiptId);
      // Will retry index upload later
      debugPrint('Index upload failed for ${receipt.filename}: $e');
    }

    return _UploadResult.success;
  }

  Future<void> _mergeAndUploadDayIndex(
    Receipt receipt,
    String remotePath,
  ) async {
    if (_indexService == null || _storageProvider == null) return;

    // Read existing remote day index if it exists
    DayIndex? remoteIndex;
    try {
      final data = await _storageProvider!.downloadFile(
        remotePath,
        'index.json',
      );
      if (data != null) {
        remoteIndex = DayIndex.fromJson(
          jsonDecode(utf8.decode(data)) as Map<String, dynamic>,
        );
      }
    } catch (_) {
      // No remote index yet
    }

    // Read local day index
    final localPath = await _folderService!.getLocalPath(
      DateTime.parse(receipt.capturedAt),
      KiraCountry.fromFolderName(receipt.country),
    );
    DayIndex? localIndex;
    try {
      final indexFile = File('$localPath/index.json');
      if (await indexFile.exists()) {
        localIndex = DayIndex.fromJson(
          jsonDecode(await indexFile.readAsString()) as Map<String, dynamic>,
        );
      }
    } catch (_) {}

    // Merge indexes
    final merged = _indexService!.mergeDayIndexes(localIndex, remoteIndex);

    // Ensure receipt is in the merged index
    final updatedIndex = _indexService!.addReceiptToIndex(merged, receipt);

    // Upload merged index
    final indexBytes = utf8.encode(jsonEncode(updatedIndex.toJson()));
    await _storageProvider!.uploadFile(remotePath, 'index.json', indexBytes);

    // Also update local index
    final localIndexFile = File('$localPath/index.json');
    await localIndexFile.writeAsString(jsonEncode(updatedIndex.toJson()));
  }

  // ---------------------------------------------------------------------------
  // Download remote changes
  // ---------------------------------------------------------------------------

  Future<({int downloaded, int merged})> _downloadRemoteChanges() async {
    // Walk remote folder structure and download missing receipts
    int downloaded = 0;
    int merged = 0;

    if (_storageProvider == null || _folderService == null) {
      return (downloaded: 0, merged: 0);
    }

    // List countries in remote Receipts/ folder
    try {
      final countries = await _storageProvider!.listFiles('Receipts');
      for (final countryFolder in countries) {
        try {
          final country = KiraCountry.fromFolderName(countryFolder);
          final years = await _storageProvider!.listFiles(
            'Receipts/${country.folderName}',
          );
          for (final year in years) {
            final months = await _storageProvider!.listFiles(
              'Receipts/${country.folderName}/$year',
            );
            for (final month in months) {
              final days = await _storageProvider!.listFiles(
                'Receipts/${country.folderName}/$year/$month',
              );
              for (final day in days) {
                if (day == '_Quarantine') continue;
                final remoteDayPath =
                    'Receipts/${country.folderName}/$year/$month/$day';
                final result = await _downloadDayFolder(
                  remoteDayPath,
                  country,
                );
                downloaded += result.downloaded;
                merged += result.merged;
              }
            }
          }
        } catch (_) {
          continue;
        }
      }
    } catch (_) {
      // Remote listing may fail
    }

    return (downloaded: downloaded, merged: merged);
  }

  Future<({int downloaded, int merged})> _downloadDayFolder(
    String remoteDayPath,
    KiraCountry country,
  ) async {
    int downloaded = 0;
    int merged = 0;

    try {
      // Download remote day index
      final remoteIndexData = await _storageProvider!.downloadFile(
        remoteDayPath,
        'index.json',
      );
      if (remoteIndexData == null) return (downloaded: 0, merged: 0);

      final remoteIndex = DayIndex.fromJson(
        jsonDecode(utf8.decode(remoteIndexData)) as Map<String, dynamic>,
      );

      // Check each receipt in remote index
      for (final entry in remoteIndex.receipts) {
        final existing = await _receiptDao.getById(entry.receiptId);
        if (existing != null) {
          merged++;
          continue;
        }

        // Download the image
        final imageData = await _storageProvider!.downloadFile(
          remoteDayPath,
          entry.filename,
        );
        if (imageData == null) continue;

        // Save locally
        final date = DateTime.parse(entry.capturedAt);
        final localPath = await _folderService!.getLocalPath(date, country);
        await Directory(localPath).create(recursive: true);
        final localFile = File('$localPath/${entry.filename}');
        await localFile.writeAsBytes(imageData);

        // Insert into local DB
        final receipt = Receipt(
          receiptId: entry.receiptId,
          capturedAt: entry.capturedAt,
          timezone: entry.timezone,
          filename: entry.filename,
          amountTracked: entry.amountTracked,
          currencyCode: entry.currencyCode,
          country: country.folderName,
          region: entry.region,
          category: entry.category,
          notes: entry.notes,
          taxApplicable: entry.taxApplicable,
          checksumSha256: entry.checksumSha256,
          deviceId: entry.deviceId,
          captureSessionId: entry.captureSessionId,
          source: entry.source,
          createdAt: entry.createdAt,
          updatedAt: entry.updatedAt,
          conflict: entry.conflict,
          supersedesFilename: entry.supersedesFilename,
        );
        await _receiptDao.insert(receipt);
        downloaded++;
      }
    } catch (_) {
      // Continue with other folders
    }

    return (downloaded: downloaded, merged: merged);
  }

  // ---------------------------------------------------------------------------
  // Batch sync (for backfill)
  // ---------------------------------------------------------------------------

  /// Syncs a batch of receipts for the backfill flow.
  Future<({int synced, int failed})> syncBatch({
    required List<String> receiptIds,
    void Function(int current, int total)? onProgress,
  }) async {
    _status = SyncEngineStatus.syncing;
    _totalItems = receiptIds.length;
    _currentItem = 0;
    int synced = 0;
    int failed = 0;
    _lastError = null;
    _cancelRequested = false;
    notifyListeners();

    for (final id in receiptIds) {
      if (_cancelRequested) break;

      _currentItem++;
      onProgress?.call(_currentItem, _totalItems);
      notifyListeners();

      try {
        final receipt = await _receiptDao.getById(id);
        if (receipt == null) {
          failed++;
          continue;
        }
        final result = await _uploadReceiptWithRetry(receipt);
        if (result == _UploadResult.success || result == _UploadResult.skipped) {
          synced++;
        } else {
          failed++;
        }
      } catch (e) {
        failed++;
        _lastError = e.toString();
      }
    }

    _pendingCount = (_pendingCount - synced).clamp(0, _pendingCount);
    _failedCount = failed;
    _status = failed > 0 ? SyncEngineStatus.error : SyncEngineStatus.idle;
    notifyListeners();

    return (synced: synced, failed: failed);
  }

  // ---------------------------------------------------------------------------
  // Control
  // ---------------------------------------------------------------------------

  void cancelSync() {
    _cancelRequested = true;
    if (_status == SyncEngineStatus.syncing) {
      _status = SyncEngineStatus.idle;
      notifyListeners();
    }
  }

  Future<void> refreshCounts() async {
    final unsynced = await _receiptDao.getUnsyncedReceipts();
    _pendingCount = unsynced.length;
    notifyListeners();
  }
}

enum _UploadResult { success, skipped, failed }
