/// Data model representing a captured receipt in the Kira system.
///
/// Each receipt corresponds to a single captured image and its associated
/// metadata. Receipts are the atomic unit of data throughout the app --
/// they are stored locally in SQLite, serialised to JSON for cloud sync,
/// and referenced by day/month indexes.
library;

import 'package:collection/collection.dart';

/// The single hard-coded value for [Receipt.source] in the current version.
const String kReceiptSourceCamera = 'camera';

class Receipt {
  /// Primary key -- a v4 UUID generated at capture time.
  final String receiptId;

  /// ISO-8601 local date-time of the capture (no timezone offset).
  /// Example: `2025-06-14T09:32:11`
  final String capturedAt;

  /// IANA timezone identifier at capture time (e.g. `America/Toronto`).
  final String timezone;

  /// Deterministic filename derived from the receipt metadata.
  /// Format: `YYYYMMDD_HHmmss_{receiptId_prefix}.jpg`
  final String filename;

  /// The tracked amount entered by the user, stored as a double
  /// (representing a decimal currency value).
  final double amountTracked;

  /// ISO-4217 currency code. Currently `CAD` or `USD`.
  final String currencyCode;

  /// Country where the receipt was captured (`canada` or `us`).
  final String country;

  /// Province or state code (e.g. `ON`, `CA`).
  final String region;

  /// User-assigned category label.
  final String category;

  /// Free-form notes attached by the user. May be null.
  final String? notes;

  /// Whether tax rules apply to this receipt. Null means "not yet determined".
  final bool? taxApplicable;

  /// SHA-256 hex digest of the original image bytes, used for integrity checks.
  final String checksumSha256;

  /// A stable device identifier persisted across app launches.
  final String deviceId;

  /// A UUID that groups all receipts captured in the same camera session.
  final String captureSessionId;

  /// Origin of the image. Always [kReceiptSourceCamera] in v1.
  final String source;

  /// ISO-8601 UTC timestamp of initial creation.
  final String createdAt;

  /// ISO-8601 UTC timestamp of the last local mutation.
  final String updatedAt;

  /// Set to `true` when a merge detects conflicting metadata for the same
  /// [receiptId]. Defaults to `false`.
  final bool conflict;

  /// If this receipt supersedes (replaces) an earlier capture, this holds
  /// the filename of the previous version. Null otherwise.
  final String? supersedesFilename;

  const Receipt({
    required this.receiptId,
    required this.capturedAt,
    required this.timezone,
    required this.filename,
    required this.amountTracked,
    required this.currencyCode,
    required this.country,
    required this.region,
    required this.category,
    this.notes,
    this.taxApplicable,
    required this.checksumSha256,
    required this.deviceId,
    required this.captureSessionId,
    this.source = kReceiptSourceCamera,
    required this.createdAt,
    required this.updatedAt,
    this.conflict = false,
    this.supersedesFilename,
  });

  // ---------------------------------------------------------------------------
  // JSON serialisation (for cloud index files)
  // ---------------------------------------------------------------------------

  factory Receipt.fromJson(Map<String, dynamic> json) {
    return Receipt(
      receiptId: json['receipt_id'] as String,
      capturedAt: json['captured_at'] as String,
      timezone: json['timezone'] as String,
      filename: json['filename'] as String,
      amountTracked: (json['amount_tracked'] as num).toDouble(),
      currencyCode: json['currency_code'] as String,
      country: json['country'] as String,
      region: json['region'] as String,
      category: json['category'] as String,
      notes: json['notes'] as String?,
      taxApplicable: json['tax_applicable'] as bool?,
      checksumSha256: json['checksum_sha256'] as String,
      deviceId: json['device_id'] as String,
      captureSessionId: json['capture_session_id'] as String,
      source: json['source'] as String? ?? kReceiptSourceCamera,
      createdAt: json['created_at'] as String,
      updatedAt: json['updated_at'] as String,
      conflict: json['conflict'] as bool? ?? false,
      supersedesFilename: json['supersedes_filename'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'receipt_id': receiptId,
      'captured_at': capturedAt,
      'timezone': timezone,
      'filename': filename,
      'amount_tracked': amountTracked,
      'currency_code': currencyCode,
      'country': country,
      'region': region,
      'category': category,
      'notes': notes,
      'tax_applicable': taxApplicable,
      'checksum_sha256': checksumSha256,
      'device_id': deviceId,
      'capture_session_id': captureSessionId,
      'source': source,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'conflict': conflict,
      'supersedes_filename': supersedesFilename,
    };
  }

  // ---------------------------------------------------------------------------
  // Map serialisation (for SQLite via sqflite)
  // ---------------------------------------------------------------------------

  factory Receipt.fromMap(Map<String, dynamic> map) {
    return Receipt(
      receiptId: map['receipt_id'] as String,
      capturedAt: map['captured_at'] as String,
      timezone: map['timezone'] as String,
      filename: map['filename'] as String,
      amountTracked: (map['amount_tracked'] as num).toDouble(),
      currencyCode: map['currency_code'] as String,
      country: map['country'] as String,
      region: map['region'] as String,
      category: map['category'] as String,
      notes: map['notes'] as String?,
      // SQLite stores bools as 0/1 integers.
      taxApplicable: map['tax_applicable'] == null
          ? null
          : (map['tax_applicable'] as int) == 1,
      checksumSha256: map['checksum_sha256'] as String,
      deviceId: map['device_id'] as String,
      captureSessionId: map['capture_session_id'] as String,
      source: map['source'] as String? ?? kReceiptSourceCamera,
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String,
      conflict: (map['conflict'] as int? ?? 0) == 1,
      supersedesFilename: map['supersedes_filename'] as String?,
    );
  }

  /// Returns a [Map] suitable for inserting into / updating an SQLite row.
  ///
  /// Boolean values are stored as `0` / `1` integers, and nullable booleans
  /// are stored as `null` when unset.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'receipt_id': receiptId,
      'captured_at': capturedAt,
      'timezone': timezone,
      'filename': filename,
      'amount_tracked': amountTracked,
      'currency_code': currencyCode,
      'country': country,
      'region': region,
      'category': category,
      'notes': notes,
      'tax_applicable': taxApplicable == null ? null : (taxApplicable! ? 1 : 0),
      'checksum_sha256': checksumSha256,
      'device_id': deviceId,
      'capture_session_id': captureSessionId,
      'source': source,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'conflict': conflict ? 1 : 0,
      'supersedes_filename': supersedesFilename,
    };
  }

  // ---------------------------------------------------------------------------
  // copyWith
  // ---------------------------------------------------------------------------

  Receipt copyWith({
    String? receiptId,
    String? capturedAt,
    String? timezone,
    String? filename,
    double? amountTracked,
    String? currencyCode,
    String? country,
    String? region,
    String? category,
    String? Function()? notes,
    bool? Function()? taxApplicable,
    String? checksumSha256,
    String? deviceId,
    String? captureSessionId,
    String? source,
    String? createdAt,
    String? updatedAt,
    bool? conflict,
    String? Function()? supersedesFilename,
  }) {
    return Receipt(
      receiptId: receiptId ?? this.receiptId,
      capturedAt: capturedAt ?? this.capturedAt,
      timezone: timezone ?? this.timezone,
      filename: filename ?? this.filename,
      amountTracked: amountTracked ?? this.amountTracked,
      currencyCode: currencyCode ?? this.currencyCode,
      country: country ?? this.country,
      region: region ?? this.region,
      category: category ?? this.category,
      notes: notes != null ? notes() : this.notes,
      taxApplicable:
          taxApplicable != null ? taxApplicable() : this.taxApplicable,
      checksumSha256: checksumSha256 ?? this.checksumSha256,
      deviceId: deviceId ?? this.deviceId,
      captureSessionId: captureSessionId ?? this.captureSessionId,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      conflict: conflict ?? this.conflict,
      supersedesFilename: supersedesFilename != null
          ? supersedesFilename()
          : this.supersedesFilename,
    );
  }

  // ---------------------------------------------------------------------------
  // Equality & hash (value-based)
  // ---------------------------------------------------------------------------

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Receipt &&
        other.receiptId == receiptId &&
        other.capturedAt == capturedAt &&
        other.timezone == timezone &&
        other.filename == filename &&
        other.amountTracked == amountTracked &&
        other.currencyCode == currencyCode &&
        other.country == country &&
        other.region == region &&
        other.category == category &&
        other.notes == notes &&
        other.taxApplicable == taxApplicable &&
        other.checksumSha256 == checksumSha256 &&
        other.deviceId == deviceId &&
        other.captureSessionId == captureSessionId &&
        other.source == source &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.conflict == conflict &&
        other.supersedesFilename == supersedesFilename;
  }

  @override
  int get hashCode => Object.hash(
        receiptId,
        capturedAt,
        timezone,
        filename,
        amountTracked,
        currencyCode,
        country,
        region,
        category,
        notes,
        taxApplicable,
        checksumSha256,
        deviceId,
        captureSessionId,
        source,
        createdAt,
        updatedAt,
        conflict,
        supersedesFilename,
      );

  @override
  String toString() => 'Receipt(receiptId: $receiptId, filename: $filename, '
      'amount: $amountTracked $currencyCode, conflict: $conflict)';
}
