/// Offline sync queue item model for the Kira sync engine.
///
/// Each pending upload/download is represented as a [SyncQueueItem] and
/// persisted in a local SQLite table. The sync service polls the queue,
/// processes items in FIFO order, and updates their [status] as they
/// progress through the pipeline.
library;

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// The kind of sync operation to perform.
enum SyncAction {
  /// Upload the receipt image (JPEG) to cloud storage.
  uploadImage,

  /// Upload or update the day/month index JSON file.
  uploadIndex,

  /// Download a file from cloud storage to the local device.
  download,
}

/// Lifecycle status of a queued sync operation.
enum SyncStatus {
  /// Waiting to be picked up by the sync worker.
  pending,

  /// Currently being executed.
  inProgress,

  /// The last attempt failed; eligible for retry.
  failed,

  /// Successfully completed; ready for cleanup.
  completed,
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _syncActionToString(SyncAction action) {
  switch (action) {
    case SyncAction.uploadImage:
      return 'upload_image';
    case SyncAction.uploadIndex:
      return 'upload_index';
    case SyncAction.download:
      return 'download';
  }
}

SyncAction _syncActionFromString(String value) {
  switch (value) {
    case 'upload_image':
      return SyncAction.uploadImage;
    case 'upload_index':
      return SyncAction.uploadIndex;
    case 'download':
      return SyncAction.download;
    default:
      throw ArgumentError('Unknown SyncAction value: $value');
  }
}

String _syncStatusToString(SyncStatus status) {
  switch (status) {
    case SyncStatus.pending:
      return 'pending';
    case SyncStatus.inProgress:
      return 'in_progress';
    case SyncStatus.failed:
      return 'failed';
    case SyncStatus.completed:
      return 'completed';
  }
}

SyncStatus _syncStatusFromString(String value) {
  switch (value) {
    case 'pending':
      return SyncStatus.pending;
    case 'in_progress':
      return SyncStatus.inProgress;
    case 'failed':
      return SyncStatus.failed;
    case 'completed':
      return SyncStatus.completed;
    default:
      throw ArgumentError('Unknown SyncStatus value: $value');
  }
}

// ---------------------------------------------------------------------------
// SyncQueueItem
// ---------------------------------------------------------------------------

/// A single entry in the offline sync queue.
class SyncQueueItem {
  /// Auto-incrementing primary key in the local database.
  final int? id;

  /// The receipt this operation relates to.
  final String receiptId;

  /// What kind of sync work to perform.
  final SyncAction action;

  /// Current lifecycle status.
  final SyncStatus status;

  /// Number of times this item has been retried after failure.
  final int retryCount;

  /// ISO-8601 UTC timestamp of the most recent attempt, or `null` if the
  /// item has never been attempted.
  final String? lastAttempt;

  /// Human-readable error message from the most recent failure, or `null`.
  final String? errorMessage;

  /// ISO-8601 UTC timestamp of when this item was first enqueued.
  final String createdAt;

  const SyncQueueItem({
    this.id,
    required this.receiptId,
    required this.action,
    this.status = SyncStatus.pending,
    this.retryCount = 0,
    this.lastAttempt,
    this.errorMessage,
    required this.createdAt,
  });

  // -------------------------------------------------------------------------
  // JSON serialisation
  // -------------------------------------------------------------------------

  factory SyncQueueItem.fromJson(Map<String, dynamic> json) {
    return SyncQueueItem(
      id: json['id'] as int?,
      receiptId: json['receipt_id'] as String,
      action: _syncActionFromString(json['action'] as String),
      status: _syncStatusFromString(json['status'] as String? ?? 'pending'),
      retryCount: json['retry_count'] as int? ?? 0,
      lastAttempt: json['last_attempt'] as String?,
      errorMessage: json['error_message'] as String?,
      createdAt: json['created_at'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'receipt_id': receiptId,
      'action': _syncActionToString(action),
      'status': _syncStatusToString(status),
      'retry_count': retryCount,
      'last_attempt': lastAttempt,
      'error_message': errorMessage,
      'created_at': createdAt,
    };
  }

  // -------------------------------------------------------------------------
  // SQLite map serialisation
  // -------------------------------------------------------------------------

  factory SyncQueueItem.fromMap(Map<String, dynamic> map) {
    return SyncQueueItem(
      id: map['id'] as int?,
      receiptId: map['receipt_id'] as String,
      action: _syncActionFromString(map['action'] as String),
      status: _syncStatusFromString(map['status'] as String? ?? 'pending'),
      retryCount: map['retry_count'] as int? ?? 0,
      lastAttempt: map['last_attempt'] as String?,
      errorMessage: map['error_message'] as String?,
      createdAt: map['created_at'] as String,
    );
  }

  /// Returns a map suitable for SQLite insertion.
  ///
  /// The [id] field is omitted when `null` so that SQLite can auto-generate
  /// the primary key.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      if (id != null) 'id': id,
      'receipt_id': receiptId,
      'action': _syncActionToString(action),
      'status': _syncStatusToString(status),
      'retry_count': retryCount,
      'last_attempt': lastAttempt,
      'error_message': errorMessage,
      'created_at': createdAt,
    };
  }

  // -------------------------------------------------------------------------
  // copyWith
  // -------------------------------------------------------------------------

  SyncQueueItem copyWith({
    int? Function()? id,
    String? receiptId,
    SyncAction? action,
    SyncStatus? status,
    int? retryCount,
    String? Function()? lastAttempt,
    String? Function()? errorMessage,
    String? createdAt,
  }) {
    return SyncQueueItem(
      id: id != null ? id() : this.id,
      receiptId: receiptId ?? this.receiptId,
      action: action ?? this.action,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      lastAttempt: lastAttempt != null ? lastAttempt() : this.lastAttempt,
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // -------------------------------------------------------------------------
  // Equality
  // -------------------------------------------------------------------------

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SyncQueueItem &&
        other.id == id &&
        other.receiptId == receiptId &&
        other.action == action &&
        other.status == status &&
        other.retryCount == retryCount &&
        other.lastAttempt == lastAttempt &&
        other.errorMessage == errorMessage &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode => Object.hash(
        id,
        receiptId,
        action,
        status,
        retryCount,
        lastAttempt,
        errorMessage,
        createdAt,
      );

  @override
  String toString() =>
      'SyncQueueItem(id: $id, receiptId: $receiptId, '
      'action: ${_syncActionToString(action)}, '
      'status: ${_syncStatusToString(status)}, retries: $retryCount)';
}
