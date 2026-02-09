/// Index file management for the Kira receipt storage system.
///
/// Each day folder contains an `index.json` ([DayIndex]) and each month
/// folder contains an `index.json` ([MonthIndex]). This service handles
/// creation, reading, merging, and the two-step commit protocol:
///
/// 1. Upload the receipt image to cloud storage.
/// 2. Merge the local index with the remote index and upload the merged
///    version.
///
/// If step 2 fails the receipt is marked `uploaded_unindexed` in the local
/// database so that the index can be retried later without re-uploading the
/// image.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/day_index.dart';
import '../models/receipt.dart';
import 'folder_service.dart';

// ---------------------------------------------------------------------------
// MonthIndex model (co-located here -- tightly coupled to index operations)
// ---------------------------------------------------------------------------

/// A single day pointer inside a [MonthIndex].
///
/// Also exported as [DaySummary] for use in month-level merge tests.
class MonthDayEntry {
  /// The date in `YYYY-MM-DD` format.
  final String date;

  /// Number of receipts captured on this day.
  final int receiptCount;

  /// Sum of `amountTracked` for every receipt on this day, keyed by
  /// currency code (e.g. `{'CAD': 142.30, 'USD': 55.00}`).
  final Map<String, double> totalByCurrency;

  /// ISO-8601 UTC timestamp of the last modification to this day's data.
  final String lastUpdated;

  /// Whether this entry was produced by a conflict resolution.
  final bool conflict;

  const MonthDayEntry({
    required this.date,
    required this.receiptCount,
    required this.totalByCurrency,
    this.lastUpdated = '',
    this.conflict = false,
  });

  /// Alias for [totalByCurrency] (plural form used in some contexts).
  Map<String, double> get totalsByCurrency => totalByCurrency;

  factory MonthDayEntry.fromJson(Map<String, dynamic> json) {
    final rawTotals = json['total_by_currency'] as Map<String, dynamic>? ?? {};
    return MonthDayEntry(
      date: json['date'] as String,
      receiptCount: json['receipt_count'] as int,
      totalByCurrency: rawTotals
          .map((k, v) => MapEntry(k, (v as num).toDouble())),
      lastUpdated: json['last_updated'] as String? ?? '',
      conflict: json['conflict'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'date': date,
        'receipt_count': receiptCount,
        'total_by_currency': totalByCurrency,
        'last_updated': lastUpdated,
        'conflict': conflict,
      };

  MonthDayEntry copyWith({
    String? date,
    int? receiptCount,
    Map<String, double>? totalByCurrency,
    String? lastUpdated,
    bool? conflict,
  }) {
    return MonthDayEntry(
      date: date ?? this.date,
      receiptCount: receiptCount ?? this.receiptCount,
      totalByCurrency: totalByCurrency ?? this.totalByCurrency,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      conflict: conflict ?? this.conflict,
    );
  }

  /// Whether two entries have identical data (for merge comparison).
  bool metadataEquals(MonthDayEntry other) {
    if (date != other.date || receiptCount != other.receiptCount) return false;
    if (totalByCurrency.length != other.totalByCurrency.length) return false;
    for (final key in totalByCurrency.keys) {
      if (totalByCurrency[key] != other.totalByCurrency[key]) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MonthDayEntry && metadataEquals(other);

  @override
  int get hashCode => Object.hash(date, receiptCount, totalByCurrency.length);
}

/// Type alias for [MonthDayEntry], used in month-level merge contexts.
typedef DaySummary = MonthDayEntry;

/// Represents the `index.json` stored in a month folder (e.g. `2025/2025-06/`).
class MonthIndex {
  /// The year-month this index covers, in `YYYY-MM` format.
  final String yearMonth;

  final int schemaVersion;
  final String lastUpdated;

  /// One entry per day that has at least one receipt.
  final List<MonthDayEntry> days;

  MonthIndex({
    String? yearMonth,
    String? month,
    this.schemaVersion = 1,
    required this.lastUpdated,
    required this.days,
  }) : yearMonth = yearMonth ?? month ?? '';

  /// Alias for [yearMonth].
  String get month => yearMonth;

  /// Aggregated totals across all days, keyed by currency code.
  /// Returns `null` if there are no days.
  Map<String, double>? get totals {
    if (days.isEmpty) return null;
    final result = <String, double>{};
    for (final day in days) {
      for (final entry in day.totalByCurrency.entries) {
        result[entry.key] = (result[entry.key] ?? 0) + entry.value;
      }
    }
    return result;
  }

  factory MonthIndex.fromJson(Map<String, dynamic> json) {
    final rawDays = json['days'] as List<dynamic>? ?? <dynamic>[];
    return MonthIndex(
      yearMonth: json['year_month'] as String,
      schemaVersion: json['schema_version'] as int? ?? 1,
      lastUpdated: json['last_updated'] as String,
      days: rawDays
          .map((e) => MonthDayEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'year_month': yearMonth,
        'schema_version': schemaVersion,
        'last_updated': lastUpdated,
        'days': days.map((d) => d.toJson()).toList(),
      };

  MonthIndex copyWith({
    String? yearMonth,
    int? schemaVersion,
    String? lastUpdated,
    List<MonthDayEntry>? days,
  }) {
    return MonthIndex(
      yearMonth: yearMonth ?? this.yearMonth,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      days: days ?? this.days,
    );
  }

  /// Merges [remote] into this (local) month index.
  ///
  /// Merge rules mirror [DayIndex.merge]:
  /// - Day entries are keyed by [MonthDayEntry.date].
  /// - Entries only in remote are added; entries only in local are kept.
  /// - When both sides have the same date with identical metadata, the local
  ///   copy is retained.
  /// - When metadata differs, the entry from the index with the later
  ///   [lastUpdated] wins.
  MonthIndex merge(MonthIndex remote) {
    final localMap = <String, MonthDayEntry>{
      for (final d in days) d.date: d,
    };
    final remoteMap = <String, MonthDayEntry>{
      for (final d in remote.days) d.date: d,
    };

    final allDates = <String>{...localMap.keys, ...remoteMap.keys};
    final merged = <MonthDayEntry>[];

    for (final date in allDates) {
      final localEntry = localMap[date];
      final remoteEntry = remoteMap[date];

      if (localEntry != null && remoteEntry == null) {
        merged.add(localEntry);
      } else if (localEntry == null && remoteEntry != null) {
        merged.add(remoteEntry);
      } else if (localEntry != null && remoteEntry != null) {
        if (localEntry.metadataEquals(remoteEntry)) {
          merged.add(localEntry);
        } else {
          // Pick the entry from the index with the later overall lastUpdated.
          final localTime = DateTime.parse(lastUpdated);
          final remoteTime = DateTime.parse(remote.lastUpdated);
          final winner = remoteTime.isAfter(localTime) ? remoteEntry : localEntry;
          merged.add(winner.copyWith(conflict: true));
        }
      }
    }

    merged.sort((a, b) => a.date.compareTo(b.date));

    final localTime = DateTime.parse(lastUpdated);
    final remoteTime = DateTime.parse(remote.lastUpdated);
    final latestTimestamp =
        remoteTime.isAfter(localTime) ? remote.lastUpdated : lastUpdated;

    return MonthIndex(
      yearMonth: yearMonth,
      schemaVersion: schemaVersion > remote.schemaVersion
          ? schemaVersion
          : remote.schemaVersion,
      lastUpdated: latestTimestamp,
      days: merged,
    );
  }
}

// ---------------------------------------------------------------------------
// IndexService
// ---------------------------------------------------------------------------

/// Manages creation, persistence, and merging of day and month index files.
class IndexService {
  final FolderService _folderService;

  /// Callback to mark a receipt as `uploaded_unindexed` in the local database
  /// when the index upload fails after a successful image upload.
  final Future<void> Function(String receiptId)? _markUploadedUnindexed;

  IndexService({
    required FolderService folderService,
    Future<void> Function(String receiptId)? markUploadedUnindexed,
  })  : _folderService = folderService,
        _markUploadedUnindexed = markUploadedUnindexed;

  // ---------------------------------------------------------------------------
  // Day index operations
  // ---------------------------------------------------------------------------

  /// Creates a [DayIndex] from the given [date] and list of [Receipt]s and
  /// returns it without writing to disk.
  DayIndex createDayIndex(DateTime date, List<Receipt> receipts) {
    final now = DateTime.now().toUtc().toIso8601String();
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    return DayIndex(
      date: dateStr,
      schemaVersion: 1,
      lastUpdated: now,
      receipts: receipts.map(_receiptToEntry).toList(),
    );
  }

  /// Reads and parses a [DayIndex] from the JSON file at [path].
  ///
  /// Returns `null` if the file does not exist or cannot be parsed.
  Future<DayIndex?> readDayIndex(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return DayIndex.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// Writes [index] to `index.json` inside [directoryPath].
  Future<void> writeDayIndex(String directoryPath, DayIndex index) async {
    await Directory(directoryPath).create(recursive: true);
    final file = File(p.join(directoryPath, 'index.json'));
    final json = const JsonEncoder.withIndent('  ').convert(index.toJson());
    await file.writeAsString(json);
  }

  /// Merges a [local] and [remote] day index using the canonical merge rules
  /// defined in [DayIndex.merge].
  ///
  /// This is a thin delegation -- the merge logic lives on the model -- but
  /// having it here keeps the service as the single entry point for index
  /// operations.
  DayIndex mergeDayIndexes(DayIndex local, DayIndex remote) {
    return local.merge(remote);
  }

  /// Appends a single receipt to an existing [DayIndex], returning the new
  /// index.
  ///
  /// If a receipt with the same `receiptId` already exists, the existing
  /// entry is **preserved** and the new one is ignored (append-only, never
  /// overwrite).
  DayIndex addReceiptToIndex(DayIndex index, Receipt receipt) {
    final existing = index.receipts.any(
      (e) => e.receiptId == receipt.receiptId,
    );
    if (existing) return index;

    final entry = _receiptToEntry(receipt);
    final updatedReceipts = [...index.receipts, entry];
    updatedReceipts.sort((a, b) => a.capturedAt.compareTo(b.capturedAt));

    return index.copyWith(
      receipts: updatedReceipts,
      lastUpdated: DateTime.now().toUtc().toIso8601String(),
    );
  }

  // ---------------------------------------------------------------------------
  // Month index operations
  // ---------------------------------------------------------------------------

  /// Creates a [MonthIndex] from the given [yearMonth] string and a list of
  /// per-day summaries.
  MonthIndex createMonthIndex(
    String yearMonth,
    List<MonthDayEntry> daySummaries,
  ) {
    final now = DateTime.now().toUtc().toIso8601String();
    final sorted = [...daySummaries]..sort((a, b) => a.date.compareTo(b.date));

    return MonthIndex(
      yearMonth: yearMonth,
      schemaVersion: 1,
      lastUpdated: now,
      days: sorted,
    );
  }

  /// Reads and parses a [MonthIndex] from the JSON file at [path].
  ///
  /// Returns `null` if the file does not exist or cannot be parsed.
  Future<MonthIndex?> readMonthIndex(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return MonthIndex.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// Writes [index] to `index.json` inside [directoryPath].
  Future<void> writeMonthIndex(String directoryPath, MonthIndex index) async {
    await Directory(directoryPath).create(recursive: true);
    final file = File(p.join(directoryPath, 'index.json'));
    final json = const JsonEncoder.withIndent('  ').convert(index.toJson());
    await file.writeAsString(json);
  }

  /// Merges a [local] and [remote] month index using canonical merge rules.
  MonthIndex mergeMonthIndexes(MonthIndex local, MonthIndex remote) {
    return local.merge(remote);
  }

  // ---------------------------------------------------------------------------
  // Two-step commit
  // ---------------------------------------------------------------------------

  /// Executes the two-step commit protocol for a single receipt:
  ///
  /// 1. Upload the image to cloud storage.
  /// 2. Download the remote day index, merge with local, upload merged index.
  ///
  /// If step 1 succeeds but step 2 fails, the receipt is marked
  /// `uploaded_unindexed` so that the index merge can be retried later.
  ///
  /// Returns `true` if both steps succeed, `false` if the index step failed
  /// (image was still uploaded successfully).
  Future<bool> commitReceipt({
    required StorageProvider storageProvider,
    required Receipt receipt,
    required List<int> imageBytes,
    required DateTime date,
    required KiraCountry country,
    String? workspaceId,
  }) async {
    final remotePath = _folderService.getRemotePath(
      date,
      country,
      workspaceId: workspaceId,
    );

    // Step 1: Upload image.
    await storageProvider.uploadFile(remotePath, receipt.filename, imageBytes);

    // Step 2: Merge and upload index.
    try {
      // Read local day index.
      final localDir = await _folderService.getLocalPath(
        date,
        country,
        workspaceId: workspaceId,
      );
      final localIndex =
          await readDayIndex(p.join(localDir, 'index.json'));

      // Download remote day index.
      DayIndex? remoteIndex;
      final remoteData =
          await storageProvider.downloadFile(remotePath, 'index.json');
      if (remoteData != null) {
        try {
          final json =
              jsonDecode(utf8.decode(remoteData)) as Map<String, dynamic>;
          remoteIndex = DayIndex.fromJson(json);
        } catch (_) {
          // Remote index is corrupt -- we will create a fresh one.
        }
      }

      // Build the merged index.
      DayIndex mergedIndex;
      if (localIndex != null && remoteIndex != null) {
        mergedIndex = mergeDayIndexes(localIndex, remoteIndex);
      } else if (localIndex != null) {
        mergedIndex = localIndex;
      } else if (remoteIndex != null) {
        mergedIndex = remoteIndex;
      } else {
        mergedIndex = createDayIndex(date, []);
      }

      // Add the new receipt (no-op if already present).
      mergedIndex = addReceiptToIndex(mergedIndex, receipt);

      // Persist locally.
      await writeDayIndex(localDir, mergedIndex);

      // Upload merged index to remote.
      final indexJson =
          const JsonEncoder.withIndent('  ').convert(mergedIndex.toJson());
      await storageProvider.uploadFile(
        remotePath,
        'index.json',
        utf8.encode(indexJson),
      );

      return true;
    } catch (_) {
      // Image uploaded successfully but index failed -- mark for retry.
      if (_markUploadedUnindexed != null) {
        await _markUploadedUnindexed!(receipt.receiptId);
      }
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Month index maintenance
  // ---------------------------------------------------------------------------

  /// Builds a [MonthDayEntry] summary from a [DayIndex].
  MonthDayEntry summarizeDay(DayIndex dayIndex) {
    final totals = <String, double>{};
    for (final receipt in dayIndex.receipts) {
      totals[receipt.currencyCode] =
          (totals[receipt.currencyCode] ?? 0.0) + receipt.amountTracked;
    }

    return MonthDayEntry(
      date: dayIndex.date,
      receiptCount: dayIndex.receipts.length,
      totalByCurrency: totals,
    );
  }

  /// Updates the month index that contains [dayIndex] on the local file
  /// system.
  ///
  /// If a month index already exists, the day entry is replaced or added.
  /// If no month index exists, a new one is created.
  Future<void> updateMonthIndexForDay(
    DayIndex dayIndex,
    DateTime date,
    KiraCountry country, {
    String? workspaceId,
  }) async {
    final localDir = await _folderService.getLocalPath(
      date,
      country,
      workspaceId: workspaceId,
    );
    // Month folder is one level up from the day folder.
    final monthDir = p.dirname(localDir);
    final monthIndexPath = p.join(monthDir, 'index.json');

    final yearMonth =
        '${date.year}-${date.month.toString().padLeft(2, '0')}';
    final daySummary = summarizeDay(dayIndex);

    var monthIndex = await readMonthIndex(monthIndexPath);

    if (monthIndex != null) {
      // Replace or add the day entry.
      final updatedDays = <MonthDayEntry>[
        ...monthIndex.days.where((d) => d.date != daySummary.date),
        daySummary,
      ]..sort((a, b) => a.date.compareTo(b.date));

      monthIndex = monthIndex.copyWith(
        days: updatedDays,
        lastUpdated: DateTime.now().toUtc().toIso8601String(),
      );
    } else {
      monthIndex = createMonthIndex(yearMonth, [daySummary]);
    }

    await writeMonthIndex(monthDir, monthIndex);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Converts a full [Receipt] to the lightweight [ReceiptIndexEntry] stored
  /// in day indexes.
  ReceiptIndexEntry _receiptToEntry(Receipt receipt) {
    return ReceiptIndexEntry(
      receiptId: receipt.receiptId,
      filename: receipt.filename,
      amountTracked: receipt.amountTracked,
      currencyCode: receipt.currencyCode,
      category: receipt.category,
      checksumSha256: receipt.checksumSha256,
      capturedAt: receipt.capturedAt,
      updatedAt: receipt.updatedAt,
      conflict: receipt.conflict,
      supersedesFilename: receipt.supersedesFilename,
      timezone: receipt.timezone,
      region: receipt.region,
      notes: receipt.notes,
      taxApplicable: receipt.taxApplicable,
      deviceId: receipt.deviceId,
      captureSessionId: receipt.captureSessionId,
      source: receipt.source,
      createdAt: receipt.createdAt,
    );
  }
}
