/// Error record model for the Kira diagnostics / error reporting panel.
///
/// Each unhandled exception or significant error in the app is captured as an
/// [ErrorRecord] and persisted locally. Records can later be synced to a
/// remote error-reporting endpoint when the user opts in.
library;

import 'package:collection/collection.dart';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// The application module where the error originated.
enum ErrorModule {
  /// Camera capture pipeline.
  capture,

  /// Cloud sync engine.
  sync,

  /// Index (day/month) management and merge logic.
  indexMgmt,

  /// On-device OCR processing.
  ocr,

  /// Third-party integrations (accounting exports, etc.).
  integration,
}

// ---------------------------------------------------------------------------
// Enum helpers
// ---------------------------------------------------------------------------

String _moduleToString(ErrorModule module) {
  switch (module) {
    case ErrorModule.capture:
      return 'capture';
    case ErrorModule.sync:
      return 'sync';
    case ErrorModule.indexMgmt:
      return 'index_mgmt';
    case ErrorModule.ocr:
      return 'ocr';
    case ErrorModule.integration:
      return 'integration';
  }
}

ErrorModule _moduleFromString(String value) {
  switch (value) {
    case 'capture':
      return ErrorModule.capture;
    case 'sync':
      return ErrorModule.sync;
    case 'index_mgmt':
      return ErrorModule.indexMgmt;
    case 'ocr':
      return ErrorModule.ocr;
    case 'integration':
      return ErrorModule.integration;
    default:
      throw ArgumentError('Unknown ErrorModule value: $value');
  }
}

// ---------------------------------------------------------------------------
// ErrorRecord
// ---------------------------------------------------------------------------

/// A structured error report suitable for local persistence and remote
/// submission.
class ErrorRecord {
  /// Unique identifier (UUID v4).
  final String id;

  /// ISO-8601 UTC timestamp of when the error occurred.
  final String timestamp;

  /// Semantic version of the app at the time of the error (e.g. `1.2.3+45`).
  final String appVersion;

  /// Operating system description (e.g. `iOS 17.4`, `Android 14`).
  final String osInfo;

  /// Device model string (e.g. `iPhone 15 Pro`, `Pixel 8`).
  final String deviceModel;

  /// The active locale when the error occurred (e.g. `en_CA`, `fr_CA`).
  final String locale;

  /// The application module that raised the error.
  final ErrorModule module;

  /// A machine-readable error code (e.g. `SYNC_UPLOAD_FAILED`,
  /// `CAPTURE_PERMISSION_DENIED`).
  final String errorCode;

  /// A human-readable error message.
  final String message;

  /// The full Dart stack trace captured at the error site.
  final String stackTrace;

  /// A map of correlation identifiers that help tie this error to other
  /// operations. Common keys include `receipt_id`, `sync_queue_id`, and
  /// `capture_session_id`.
  final Map<String, String> correlationIds;

  /// Whether this error record has been uploaded to the remote reporting
  /// service.
  final bool synced;

  const ErrorRecord({
    required this.id,
    required this.timestamp,
    required this.appVersion,
    required this.osInfo,
    required this.deviceModel,
    required this.locale,
    required this.module,
    required this.errorCode,
    required this.message,
    required this.stackTrace,
    this.correlationIds = const <String, String>{},
    this.synced = false,
  });

  // -------------------------------------------------------------------------
  // JSON serialisation
  // -------------------------------------------------------------------------

  factory ErrorRecord.fromJson(Map<String, dynamic> json) {
    final rawCorrelation =
        json['correlation_ids'] as Map<String, dynamic>? ??
            <String, dynamic>{};
    return ErrorRecord(
      id: json['id'] as String,
      timestamp: json['timestamp'] as String,
      appVersion: json['app_version'] as String,
      osInfo: json['os_info'] as String,
      deviceModel: json['device_model'] as String,
      locale: json['locale'] as String,
      module: _moduleFromString(json['module'] as String),
      errorCode: json['error_code'] as String,
      message: json['message'] as String,
      stackTrace: json['stack_trace'] as String,
      correlationIds:
          rawCorrelation.map((k, v) => MapEntry(k, v as String)),
      synced: json['synced'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'timestamp': timestamp,
      'app_version': appVersion,
      'os_info': osInfo,
      'device_model': deviceModel,
      'locale': locale,
      'module': _moduleToString(module),
      'error_code': errorCode,
      'message': message,
      'stack_trace': stackTrace,
      'correlation_ids': correlationIds,
      'synced': synced,
    };
  }

  // -------------------------------------------------------------------------
  // SQLite map serialisation
  // -------------------------------------------------------------------------

  factory ErrorRecord.fromMap(Map<String, dynamic> map) {
    // correlation_ids are stored as a comma-separated `key:value` string in
    // SQLite for simplicity. An empty string yields an empty map.
    final rawCorrelation = map['correlation_ids'] as String? ?? '';
    final correlationIds = <String, String>{};
    if (rawCorrelation.isNotEmpty) {
      for (final pair in rawCorrelation.split(',')) {
        final parts = pair.split(':');
        if (parts.length == 2) {
          correlationIds[parts[0].trim()] = parts[1].trim();
        }
      }
    }

    return ErrorRecord(
      id: map['id'] as String,
      timestamp: map['timestamp'] as String,
      appVersion: map['app_version'] as String,
      osInfo: map['os_info'] as String,
      deviceModel: map['device_model'] as String,
      locale: map['locale'] as String,
      module: _moduleFromString(map['module'] as String),
      errorCode: map['error_code'] as String,
      message: map['message'] as String,
      stackTrace: map['stack_trace'] as String,
      correlationIds: correlationIds,
      synced: (map['synced'] as int? ?? 0) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    // Serialise the correlation map as `key:value` pairs joined by commas.
    final correlationString = correlationIds.entries
        .map((e) => '${e.key}:${e.value}')
        .join(',');

    return <String, dynamic>{
      'id': id,
      'timestamp': timestamp,
      'app_version': appVersion,
      'os_info': osInfo,
      'device_model': deviceModel,
      'locale': locale,
      'module': _moduleToString(module),
      'error_code': errorCode,
      'message': message,
      'stack_trace': stackTrace,
      'correlation_ids': correlationString,
      'synced': synced ? 1 : 0,
    };
  }

  // -------------------------------------------------------------------------
  // copyWith
  // -------------------------------------------------------------------------

  ErrorRecord copyWith({
    String? id,
    String? timestamp,
    String? appVersion,
    String? osInfo,
    String? deviceModel,
    String? locale,
    ErrorModule? module,
    String? errorCode,
    String? message,
    String? stackTrace,
    Map<String, String>? correlationIds,
    bool? synced,
  }) {
    return ErrorRecord(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      appVersion: appVersion ?? this.appVersion,
      osInfo: osInfo ?? this.osInfo,
      deviceModel: deviceModel ?? this.deviceModel,
      locale: locale ?? this.locale,
      module: module ?? this.module,
      errorCode: errorCode ?? this.errorCode,
      message: message ?? this.message,
      stackTrace: stackTrace ?? this.stackTrace,
      correlationIds: correlationIds ?? this.correlationIds,
      synced: synced ?? this.synced,
    );
  }

  // -------------------------------------------------------------------------
  // Equality
  // -------------------------------------------------------------------------

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ErrorRecord) return false;
    return other.id == id &&
        other.timestamp == timestamp &&
        other.appVersion == appVersion &&
        other.osInfo == osInfo &&
        other.deviceModel == deviceModel &&
        other.locale == locale &&
        other.module == module &&
        other.errorCode == errorCode &&
        other.message == message &&
        other.stackTrace == stackTrace &&
        const MapEquality<String, String>()
            .equals(other.correlationIds, correlationIds) &&
        other.synced == synced;
  }

  @override
  int get hashCode => Object.hash(
        id,
        timestamp,
        appVersion,
        osInfo,
        deviceModel,
        locale,
        module,
        errorCode,
        message,
        stackTrace,
        const MapEquality<String, String>().hash(correlationIds),
        synced,
      );

  @override
  String toString() =>
      'ErrorRecord(id: $id, module: ${_moduleToString(module)}, '
      'code: $errorCode, synced: $synced)';
}
