/// Day-level index model for the Kira receipt storage system.
///
/// Each day folder (e.g. `2025/06/14/`) contains an `index.json` that is
/// represented by [DayIndex]. The index holds a list of [ReceiptIndexEntry]
/// objects -- lightweight pointers to the full receipt data -- plus metadata
/// about the index itself.
///
/// Merge semantics (spec):
///   - Entries are matched by [ReceiptIndexEntry.receiptId].
///   - New entries (present in remote but not local) are **added** -- never
///     auto-deleted.
///   - When two entries share the same `receiptId` but differ in any metadata
///     field, the entry with the later `updatedAt` wins and `conflict` is set
///     to `true` so the UI can surface it.
library;

import 'package:collection/collection.dart';

// ---------------------------------------------------------------------------
// ReceiptIndexEntry
// ---------------------------------------------------------------------------

/// A lightweight pointer to a receipt inside a day index.
///
/// This is intentionally a subset of [Receipt] -- just enough metadata to
/// render a list row and detect conflicts without loading the full record.
class ReceiptIndexEntry {
  final String receiptId;
  final String filename;
  final double amountTracked;
  final String currencyCode;
  final String category;
  final String checksumSha256;
  final String capturedAt;
  final String updatedAt;
  final bool conflict;
  final String? supersedesFilename;

  // Extended fields for full Receipt reconstruction during sync.
  final String timezone;
  final String region;
  final String? notes;
  final bool? taxApplicable;
  final String deviceId;
  final String captureSessionId;
  final String source;
  final String createdAt;

  ReceiptIndexEntry({
    required this.receiptId,
    required this.filename,
    required this.amountTracked,
    required this.currencyCode,
    required this.category,
    required this.checksumSha256,
    required this.capturedAt,
    required this.updatedAt,
    this.conflict = false,
    this.supersedesFilename,
    this.timezone = '',
    this.region = '',
    this.notes,
    this.taxApplicable,
    this.deviceId = '',
    this.captureSessionId = '',
    this.source = 'camera',
    String? createdAt,
  }) : createdAt = createdAt ?? capturedAt;

  factory ReceiptIndexEntry.fromJson(Map<String, dynamic> json) {
    return ReceiptIndexEntry(
      receiptId: json['receipt_id'] as String,
      filename: json['filename'] as String,
      amountTracked: (json['amount_tracked'] as num).toDouble(),
      currencyCode: json['currency_code'] as String,
      category: json['category'] as String,
      checksumSha256: json['checksum_sha256'] as String,
      capturedAt: json['captured_at'] as String,
      updatedAt: json['updated_at'] as String,
      conflict: json['conflict'] as bool? ?? false,
      supersedesFilename: json['supersedes_filename'] as String?,
      timezone: json['timezone'] as String? ?? '',
      region: json['region'] as String? ?? '',
      notes: json['notes'] as String?,
      taxApplicable: json['tax_applicable'] as bool?,
      deviceId: json['device_id'] as String? ?? '',
      captureSessionId: json['capture_session_id'] as String? ?? '',
      source: json['source'] as String? ?? 'camera',
      createdAt: json['created_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'receipt_id': receiptId,
      'filename': filename,
      'amount_tracked': amountTracked,
      'currency_code': currencyCode,
      'category': category,
      'checksum_sha256': checksumSha256,
      'captured_at': capturedAt,
      'updated_at': updatedAt,
      'conflict': conflict,
      'supersedes_filename': supersedesFilename,
      'timezone': timezone,
      'region': region,
      'notes': notes,
      'tax_applicable': taxApplicable,
      'device_id': deviceId,
      'capture_session_id': captureSessionId,
      'source': source,
      'created_at': createdAt,
    };
  }

  ReceiptIndexEntry copyWith({
    String? receiptId,
    String? filename,
    double? amountTracked,
    String? currencyCode,
    String? category,
    String? checksumSha256,
    String? capturedAt,
    String? updatedAt,
    bool? conflict,
    String? Function()? supersedesFilename,
    String? timezone,
    String? region,
    String? Function()? notes,
    bool? Function()? taxApplicable,
    String? deviceId,
    String? captureSessionId,
    String? source,
    String? createdAt,
  }) {
    return ReceiptIndexEntry(
      receiptId: receiptId ?? this.receiptId,
      filename: filename ?? this.filename,
      amountTracked: amountTracked ?? this.amountTracked,
      currencyCode: currencyCode ?? this.currencyCode,
      category: category ?? this.category,
      checksumSha256: checksumSha256 ?? this.checksumSha256,
      capturedAt: capturedAt ?? this.capturedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      conflict: conflict ?? this.conflict,
      supersedesFilename: supersedesFilename != null
          ? supersedesFilename()
          : this.supersedesFilename,
      timezone: timezone ?? this.timezone,
      region: region ?? this.region,
      notes: notes != null ? notes() : this.notes,
      taxApplicable: taxApplicable != null ? taxApplicable() : this.taxApplicable,
      deviceId: deviceId ?? this.deviceId,
      captureSessionId: captureSessionId ?? this.captureSessionId,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Whether two entries have identical metadata (ignoring the conflict flag).
  bool metadataEquals(ReceiptIndexEntry other) {
    return receiptId == other.receiptId &&
        filename == other.filename &&
        amountTracked == other.amountTracked &&
        currencyCode == other.currencyCode &&
        category == other.category &&
        checksumSha256 == other.checksumSha256 &&
        capturedAt == other.capturedAt &&
        supersedesFilename == other.supersedesFilename;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReceiptIndexEntry &&
        other.receiptId == receiptId &&
        other.filename == filename &&
        other.amountTracked == amountTracked &&
        other.currencyCode == currencyCode &&
        other.category == category &&
        other.checksumSha256 == checksumSha256 &&
        other.capturedAt == capturedAt &&
        other.updatedAt == updatedAt &&
        other.conflict == conflict &&
        other.supersedesFilename == supersedesFilename;
  }

  @override
  int get hashCode => Object.hash(
        receiptId,
        filename,
        amountTracked,
        currencyCode,
        category,
        checksumSha256,
        capturedAt,
        updatedAt,
        conflict,
        supersedesFilename,
      );

  @override
  String toString() =>
      'ReceiptIndexEntry(receiptId: $receiptId, filename: $filename)';
}

// ---------------------------------------------------------------------------
// DayIndex
// ---------------------------------------------------------------------------

/// Represents the `index.json` stored in a single day folder.
class DayIndex {
  /// The date this index covers, in `YYYY-MM-DD` format.
  final String date;

  /// Schema version of this index file, used for forward-compatible migrations.
  final int schemaVersion;

  /// ISO-8601 UTC timestamp of the last modification to this index.
  final String lastUpdated;

  /// Ordered list of receipt entries for this day.
  final List<ReceiptIndexEntry> receipts;

  const DayIndex({
    required this.date,
    this.schemaVersion = 1,
    required this.lastUpdated,
    required this.receipts,
  });

  factory DayIndex.fromJson(Map<String, dynamic> json) {
    final rawReceipts = json['receipts'] as List<dynamic>? ?? <dynamic>[];
    return DayIndex(
      date: json['date'] as String,
      schemaVersion: json['schema_version'] as int? ?? 1,
      lastUpdated: json['last_updated'] as String,
      receipts: rawReceipts
          .map((e) => ReceiptIndexEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'date': date,
      'schema_version': schemaVersion,
      'last_updated': lastUpdated,
      'receipts': receipts.map((e) => e.toJson()).toList(),
    };
  }

  DayIndex copyWith({
    String? date,
    int? schemaVersion,
    String? lastUpdated,
    List<ReceiptIndexEntry>? receipts,
  }) {
    return DayIndex(
      date: date ?? this.date,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      receipts: receipts ?? this.receipts,
    );
  }

  // -------------------------------------------------------------------------
  // Merge logic
  // -------------------------------------------------------------------------

  /// Merges [remote] into **this** (local) index and returns a new [DayIndex].
  ///
  /// Merge rules:
  /// 1. Entries are keyed by `receiptId`.
  /// 2. Entries that exist only in remote are **added** (never auto-deleted).
  /// 3. Entries that exist only in local are **kept** (never auto-deleted).
  /// 4. When both sides contain the same `receiptId`:
  ///    a. If the metadata is identical the local copy is retained as-is.
  ///    b. If the metadata differs the entry with the later `updatedAt` wins,
  ///       and its `conflict` flag is set to `true`.
  ///
  /// The returned index's [lastUpdated] is set to the later of the two
  /// source timestamps.
  DayIndex merge(DayIndex remote) {
    final localMap = <String, ReceiptIndexEntry>{
      for (final entry in receipts) entry.receiptId: entry,
    };
    final remoteMap = <String, ReceiptIndexEntry>{
      for (final entry in remote.receipts) entry.receiptId: entry,
    };

    final allIds = <String>{...localMap.keys, ...remoteMap.keys};
    final merged = <ReceiptIndexEntry>[];

    for (final id in allIds) {
      final local = localMap[id];
      final remoteEntry = remoteMap[id];

      if (local != null && remoteEntry == null) {
        // Only in local -- keep.
        merged.add(local);
      } else if (local == null && remoteEntry != null) {
        // Only in remote -- add.
        merged.add(remoteEntry);
      } else if (local != null && remoteEntry != null) {
        // Present on both sides.
        if (local.metadataEquals(remoteEntry)) {
          // Identical metadata -- keep local, preserve existing conflict flag.
          merged.add(local);
        } else {
          // Metadata conflict -- pick the one with the later updatedAt and
          // flag the conflict.
          final localTime = DateTime.parse(local.updatedAt);
          final remoteTime = DateTime.parse(remoteEntry.updatedAt);
          final winner =
              remoteTime.isAfter(localTime) ? remoteEntry : local;
          merged.add(winner.copyWith(conflict: true));
        }
      }
    }

    // Sort by capturedAt for deterministic ordering.
    merged.sort((a, b) => a.capturedAt.compareTo(b.capturedAt));

    final localTime = DateTime.parse(lastUpdated);
    final remoteTime = DateTime.parse(remote.lastUpdated);
    final latestTimestamp =
        remoteTime.isAfter(localTime) ? remote.lastUpdated : lastUpdated;

    return DayIndex(
      date: date,
      schemaVersion: schemaVersion > remote.schemaVersion
          ? schemaVersion
          : remote.schemaVersion,
      lastUpdated: latestTimestamp,
      receipts: merged,
    );
  }

  // -------------------------------------------------------------------------
  // Equality
  // -------------------------------------------------------------------------

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! DayIndex) return false;
    if (other.date != date ||
        other.schemaVersion != schemaVersion ||
        other.lastUpdated != lastUpdated ||
        other.receipts.length != receipts.length) {
      return false;
    }
    return const ListEquality<ReceiptIndexEntry>()
        .equals(other.receipts, receipts);
  }

  @override
  int get hashCode => Object.hash(
        date,
        schemaVersion,
        lastUpdated,
        const ListEquality<ReceiptIndexEntry>().hash(receipts),
      );

  @override
  String toString() =>
      'DayIndex(date: $date, receipts: ${receipts.length}, '
      'lastUpdated: $lastUpdated)';
}
