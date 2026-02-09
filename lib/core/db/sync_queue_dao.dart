/// Data-access object for the `sync_queue` table.
///
/// The sync queue tracks pending upload / index operations.  Items are
/// enqueued when a receipt is captured and dequeued by the sync engine.
/// Failed items are retried with exponential back-off managed externally;
/// this DAO simply tracks the retry count and last-attempt timestamp.
library;

import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';

/// The type of sync operation.
enum SyncAction { uploadImage, uploadIndex, download }

/// The current status of a sync queue item.
enum SyncStatus { pending, inProgress, failed, completed }

/// Lightweight value object representing a single sync-queue row.
class SyncQueueItem {
  final int? id;
  final String receiptId;
  final String action;
  final String status;
  final int retryCount;
  final String? lastAttempt;
  final String? errorMessage;
  final String createdAt;

  const SyncQueueItem({
    this.id,
    required this.receiptId,
    required this.action,
    this.status = 'pending',
    this.retryCount = 0,
    this.lastAttempt,
    this.errorMessage,
    required this.createdAt,
  });

  factory SyncQueueItem.fromMap(Map<String, dynamic> map) {
    return SyncQueueItem(
      id: map['id'] as int?,
      receiptId: map['receipt_id'] as String,
      action: map['action'] as String,
      status: map['status'] as String? ?? 'pending',
      retryCount: map['retry_count'] as int? ?? 0,
      lastAttempt: map['last_attempt'] as String?,
      errorMessage: map['error_message'] as String?,
      createdAt: map['created_at'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      if (id != null) 'id': id,
      'receipt_id': receiptId,
      'action': action,
      'status': status,
      'retry_count': retryCount,
      'last_attempt': lastAttempt,
      'error_message': errorMessage,
      'created_at': createdAt,
    };
  }

  @override
  String toString() =>
      'SyncQueueItem(id: $id, receiptId: $receiptId, action: $action, '
      'status: $status, retries: $retryCount)';
}

class SyncQueueDao {
  final DatabaseHelper _dbHelper;

  SyncQueueDao([DatabaseHelper? helper])
      : _dbHelper = helper ?? DatabaseHelper();

  Future<Database> get _db => _dbHelper.database;

  // ---------------------------------------------------------------------------
  // Enqueue / dequeue
  // ---------------------------------------------------------------------------

  /// Adds a new item to the queue.  Returns the auto-generated row id.
  Future<int> enqueue({
    required String receiptId,
    required String action,
  }) async {
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();
    return db.insert('sync_queue', {
      'receipt_id': receiptId,
      'action': action,
      'status': 'pending',
      'retry_count': 0,
      'created_at': now,
    });
  }

  /// Removes the given item from the queue entirely.
  Future<void> dequeue(int id) async {
    final db = await _db;
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------------------
  // Status transitions
  // ---------------------------------------------------------------------------

  /// Marks an item as successfully completed and removes it from the queue.
  Future<void> markCompleted(int id) async {
    final db = await _db;
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
  }

  /// Marks an item as failed, recording the error message and incrementing
  /// the retry counter.
  Future<void> markFailed(int id, String errorMessage) async {
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.rawUpdate(
      'UPDATE sync_queue SET status = ?, error_message = ?, '
      'retry_count = retry_count + 1, last_attempt = ? WHERE id = ?',
      ['failed', errorMessage, now, id],
    );
  }

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  /// Returns the next pending item (oldest first), or `null` if the queue is
  /// empty.
  Future<SyncQueueItem?> getNextPending() async {
    final db = await _db;
    final rows = await db.query(
      'sync_queue',
      where: "status = 'pending'",
      orderBy: 'created_at ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return SyncQueueItem.fromMap(rows.first);
  }

  /// Returns the number of pending items.
  Future<int> getPendingCount() async {
    final db = await _db;
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS cnt FROM sync_queue WHERE status = 'pending'",
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Returns all items with status `'failed'`.
  Future<List<SyncQueueItem>> getFailedItems() async {
    final db = await _db;
    final rows = await db.query(
      'sync_queue',
      where: "status = 'failed'",
      orderBy: 'created_at ASC',
    );
    return rows.map(SyncQueueItem.fromMap).toList();
  }

  /// Resets all failed items back to `'pending'` so the sync engine will
  /// retry them.  Returns the number of rows affected.
  Future<int> retryFailed() async {
    final db = await _db;
    return db.update(
      'sync_queue',
      {'status': 'pending'},
      where: "status = 'failed'",
    );
  }

  /// Deletes all completed items from the queue.  (Completed items are
  /// normally removed immediately by [markCompleted], but this method serves
  /// as a safety-net sweep.)
  Future<int> clearCompleted() async {
    final db = await _db;
    return db.delete(
      'sync_queue',
      where: "status = 'completed'",
    );
  }

  /// Returns every item in the queue regardless of status.
  Future<List<SyncQueueItem>> getAll() async {
    final db = await _db;
    final rows = await db.query(
      'sync_queue',
      orderBy: 'created_at ASC',
    );
    return rows.map(SyncQueueItem.fromMap).toList();
  }
}
