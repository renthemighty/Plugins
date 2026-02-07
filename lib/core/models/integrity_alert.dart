/// Integrity alert model for the Kira self-healing / audit system.
///
/// The integrity checker scans the local and cloud file structures looking
/// for anomalies (orphan files, checksum mismatches, etc.) and records each
/// finding as an [IntegrityAlert]. Alerts are surfaced in the diagnostics
/// panel and can be dismissed or quarantined by the user.
library;

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// Classification of the integrity issue detected.
enum IntegrityAlertType {
  /// A file exists on disk but has no corresponding entry in any index.
  orphanFile,

  /// An index entry references a file that does not exist on disk.
  orphanEntry,

  /// A filename does not conform to the expected naming convention.
  invalidFilename,

  /// A receipt image is stored in the wrong date folder.
  folderMismatch,

  /// The SHA-256 checksum of a file does not match its index entry.
  checksumMismatch,

  /// An unexpected (non-receipt) file was found in the storage tree.
  unexpectedFile,
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _alertTypeToString(IntegrityAlertType type) {
  switch (type) {
    case IntegrityAlertType.orphanFile:
      return 'orphan_file';
    case IntegrityAlertType.orphanEntry:
      return 'orphan_entry';
    case IntegrityAlertType.invalidFilename:
      return 'invalid_filename';
    case IntegrityAlertType.folderMismatch:
      return 'folder_mismatch';
    case IntegrityAlertType.checksumMismatch:
      return 'checksum_mismatch';
    case IntegrityAlertType.unexpectedFile:
      return 'unexpected_file';
  }
}

IntegrityAlertType _alertTypeFromString(String value) {
  switch (value) {
    case 'orphan_file':
      return IntegrityAlertType.orphanFile;
    case 'orphan_entry':
      return IntegrityAlertType.orphanEntry;
    case 'invalid_filename':
      return IntegrityAlertType.invalidFilename;
    case 'folder_mismatch':
      return IntegrityAlertType.folderMismatch;
    case 'checksum_mismatch':
      return IntegrityAlertType.checksumMismatch;
    case 'unexpected_file':
      return IntegrityAlertType.unexpectedFile;
    default:
      throw ArgumentError('Unknown IntegrityAlertType value: $value');
  }
}

// ---------------------------------------------------------------------------
// IntegrityAlert
// ---------------------------------------------------------------------------

/// A single finding from the integrity checker.
class IntegrityAlert {
  /// Unique identifier for this alert (UUID v4).
  final String id;

  /// The category of integrity issue.
  final IntegrityAlertType type;

  /// The storage path (local or cloud-relative) where the issue was found.
  final String path;

  /// A human-readable description of what went wrong.
  final String description;

  /// A suggested corrective action for the user or the auto-repair system.
  final String recommendedAction;

  /// ISO-8601 UTC timestamp of when the issue was first detected.
  final String detectedAt;

  /// Whether the user has dismissed this alert from the UI.
  final bool dismissed;

  /// Whether the offending file has been moved to the quarantine folder.
  final bool quarantined;

  const IntegrityAlert({
    required this.id,
    required this.type,
    required this.path,
    required this.description,
    required this.recommendedAction,
    required this.detectedAt,
    this.dismissed = false,
    this.quarantined = false,
  });

  // -------------------------------------------------------------------------
  // JSON serialisation
  // -------------------------------------------------------------------------

  factory IntegrityAlert.fromJson(Map<String, dynamic> json) {
    return IntegrityAlert(
      id: json['id'] as String,
      type: _alertTypeFromString(json['type'] as String),
      path: json['path'] as String,
      description: json['description'] as String,
      recommendedAction: json['recommended_action'] as String,
      detectedAt: json['detected_at'] as String,
      dismissed: json['dismissed'] as bool? ?? false,
      quarantined: json['quarantined'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'type': _alertTypeToString(type),
      'path': path,
      'description': description,
      'recommended_action': recommendedAction,
      'detected_at': detectedAt,
      'dismissed': dismissed,
      'quarantined': quarantined,
    };
  }

  // -------------------------------------------------------------------------
  // SQLite map serialisation
  // -------------------------------------------------------------------------

  factory IntegrityAlert.fromMap(Map<String, dynamic> map) {
    return IntegrityAlert(
      id: map['id'] as String,
      type: _alertTypeFromString(map['type'] as String),
      path: map['path'] as String,
      description: map['description'] as String,
      recommendedAction: map['recommended_action'] as String,
      detectedAt: map['detected_at'] as String,
      dismissed: (map['dismissed'] as int? ?? 0) == 1,
      quarantined: (map['quarantined'] as int? ?? 0) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'type': _alertTypeToString(type),
      'path': path,
      'description': description,
      'recommended_action': recommendedAction,
      'detected_at': detectedAt,
      'dismissed': dismissed ? 1 : 0,
      'quarantined': quarantined ? 1 : 0,
    };
  }

  // -------------------------------------------------------------------------
  // copyWith
  // -------------------------------------------------------------------------

  IntegrityAlert copyWith({
    String? id,
    IntegrityAlertType? type,
    String? path,
    String? description,
    String? recommendedAction,
    String? detectedAt,
    bool? dismissed,
    bool? quarantined,
  }) {
    return IntegrityAlert(
      id: id ?? this.id,
      type: type ?? this.type,
      path: path ?? this.path,
      description: description ?? this.description,
      recommendedAction: recommendedAction ?? this.recommendedAction,
      detectedAt: detectedAt ?? this.detectedAt,
      dismissed: dismissed ?? this.dismissed,
      quarantined: quarantined ?? this.quarantined,
    );
  }

  // -------------------------------------------------------------------------
  // Equality
  // -------------------------------------------------------------------------

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is IntegrityAlert &&
        other.id == id &&
        other.type == type &&
        other.path == path &&
        other.description == description &&
        other.recommendedAction == recommendedAction &&
        other.detectedAt == detectedAt &&
        other.dismissed == dismissed &&
        other.quarantined == quarantined;
  }

  @override
  int get hashCode => Object.hash(
        id,
        type,
        path,
        description,
        recommendedAction,
        detectedAt,
        dismissed,
        quarantined,
      );

  @override
  String toString() =>
      'IntegrityAlert(id: $id, type: ${_alertTypeToString(type)}, '
      'path: $path, dismissed: $dismissed, quarantined: $quarantined)';
}
