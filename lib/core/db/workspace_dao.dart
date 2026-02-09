/// Data-access object for the business / workspace tables:
/// `workspaces`, `workspace_members`, `trips`, `expense_reports`, and
/// `audit_events`.
///
/// All five tables are grouped into one DAO because they share a tight
/// foreign-key graph and most business operations touch several of them
/// within the same transaction.
library;

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Value objects
// ═══════════════════════════════════════════════════════════════════════════

// ---------------------------------------------------------------------------
// Workspace
// ---------------------------------------------------------------------------

class Workspace {
  final String workspaceId;
  final String name;
  final String ownerUserId;
  final String createdAt;
  final String updatedAt;

  const Workspace({
    required this.workspaceId,
    required this.name,
    required this.ownerUserId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Workspace.fromMap(Map<String, dynamic> map) {
    return Workspace(
      workspaceId: map['workspace_id'] as String,
      name: map['name'] as String,
      ownerUserId: map['owner_user_id'] as String,
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'workspace_id': workspaceId,
      'name': name,
      'owner_user_id': ownerUserId,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  @override
  String toString() =>
      'Workspace(id: $workspaceId, name: $name, owner: $ownerUserId)';
}

// ---------------------------------------------------------------------------
// WorkspaceMember
// ---------------------------------------------------------------------------

/// Roles mirroring the localisation keys in `app_en.arb`.
abstract final class WorkspaceRole {
  static const String admin = 'admin';
  static const String approver = 'approver';
  static const String member = 'member';
  static const String accountant = 'accountant';
}

class WorkspaceMember {
  final int? id;
  final String workspaceId;
  final String userId;
  final String role;
  final String? displayName;
  final String? email;
  final String invitedAt;
  final String? joinedAt;

  const WorkspaceMember({
    this.id,
    required this.workspaceId,
    required this.userId,
    required this.role,
    this.displayName,
    this.email,
    required this.invitedAt,
    this.joinedAt,
  });

  factory WorkspaceMember.fromMap(Map<String, dynamic> map) {
    return WorkspaceMember(
      id: map['id'] as int?,
      workspaceId: map['workspace_id'] as String,
      userId: map['user_id'] as String,
      role: map['role'] as String,
      displayName: map['display_name'] as String?,
      email: map['email'] as String?,
      invitedAt: map['invited_at'] as String,
      joinedAt: map['joined_at'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      if (id != null) 'id': id,
      'workspace_id': workspaceId,
      'user_id': userId,
      'role': role,
      'display_name': displayName,
      'email': email,
      'invited_at': invitedAt,
      'joined_at': joinedAt,
    };
  }

  @override
  String toString() =>
      'WorkspaceMember(userId: $userId, role: $role, ws: $workspaceId)';
}

// ---------------------------------------------------------------------------
// Trip
// ---------------------------------------------------------------------------

class Trip {
  final String tripId;
  final String workspaceId;
  final String name;
  final String? description;
  final String? startDate;
  final String? endDate;
  final String createdBy;
  final String createdAt;
  final String updatedAt;

  const Trip({
    required this.tripId,
    required this.workspaceId,
    required this.name,
    this.description,
    this.startDate,
    this.endDate,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Trip.fromMap(Map<String, dynamic> map) {
    return Trip(
      tripId: map['trip_id'] as String,
      workspaceId: map['workspace_id'] as String,
      name: map['name'] as String,
      description: map['description'] as String?,
      startDate: map['start_date'] as String?,
      endDate: map['end_date'] as String?,
      createdBy: map['created_by'] as String,
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'trip_id': tripId,
      'workspace_id': workspaceId,
      'name': name,
      'description': description,
      'start_date': startDate,
      'end_date': endDate,
      'created_by': createdBy,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  @override
  String toString() =>
      'Trip(id: $tripId, name: $name, ws: $workspaceId)';
}

// ---------------------------------------------------------------------------
// ExpenseReport
// ---------------------------------------------------------------------------

/// Status values for expense reports.
abstract final class ReportStatus {
  static const String draft = 'draft';
  static const String submitted = 'submitted';
  static const String approved = 'approved';
  static const String exported = 'exported';
}

class ExpenseReport {
  final String reportId;
  final String workspaceId;
  final String? tripId;
  final String title;
  final String status;
  final double totalAmount;
  final String currencyCode;
  final String? submittedBy;
  final String? submittedAt;
  final String? approvedBy;
  final String? approvedAt;
  final String? notes;
  final String createdAt;
  final String updatedAt;

  const ExpenseReport({
    required this.reportId,
    required this.workspaceId,
    this.tripId,
    required this.title,
    this.status = ReportStatus.draft,
    this.totalAmount = 0.0,
    this.currencyCode = 'CAD',
    this.submittedBy,
    this.submittedAt,
    this.approvedBy,
    this.approvedAt,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ExpenseReport.fromMap(Map<String, dynamic> map) {
    return ExpenseReport(
      reportId: map['report_id'] as String,
      workspaceId: map['workspace_id'] as String,
      tripId: map['trip_id'] as String?,
      title: map['title'] as String,
      status: map['status'] as String? ?? ReportStatus.draft,
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0.0,
      currencyCode: map['currency_code'] as String? ?? 'CAD',
      submittedBy: map['submitted_by'] as String?,
      submittedAt: map['submitted_at'] as String?,
      approvedBy: map['approved_by'] as String?,
      approvedAt: map['approved_at'] as String?,
      notes: map['notes'] as String?,
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'report_id': reportId,
      'workspace_id': workspaceId,
      'trip_id': tripId,
      'title': title,
      'status': status,
      'total_amount': totalAmount,
      'currency_code': currencyCode,
      'submitted_by': submittedBy,
      'submitted_at': submittedAt,
      'approved_by': approvedBy,
      'approved_at': approvedAt,
      'notes': notes,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  @override
  String toString() =>
      'ExpenseReport(id: $reportId, title: $title, status: $status)';
}

// ---------------------------------------------------------------------------
// AuditEvent
// ---------------------------------------------------------------------------

class AuditEvent {
  final String eventId;
  final String workspaceId;
  final String userId;
  final String action;
  final String? targetType;
  final String? targetId;
  final Map<String, dynamic>? metadata;
  final String createdAt;

  const AuditEvent({
    required this.eventId,
    required this.workspaceId,
    required this.userId,
    required this.action,
    this.targetType,
    this.targetId,
    this.metadata,
    required this.createdAt,
  });

  factory AuditEvent.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic>? meta;
    final raw = map['metadata'] as String?;
    if (raw != null && raw.isNotEmpty) {
      try {
        meta = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        // Corrupt JSON is silently ignored.
      }
    }
    return AuditEvent(
      eventId: map['event_id'] as String,
      workspaceId: map['workspace_id'] as String,
      userId: map['user_id'] as String,
      action: map['action'] as String,
      targetType: map['target_type'] as String?,
      targetId: map['target_id'] as String?,
      metadata: meta,
      createdAt: map['created_at'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'event_id': eventId,
      'workspace_id': workspaceId,
      'user_id': userId,
      'action': action,
      'target_type': targetType,
      'target_id': targetId,
      'metadata': metadata != null ? jsonEncode(metadata) : null,
      'created_at': createdAt,
    };
  }

  @override
  String toString() =>
      'AuditEvent(id: $eventId, action: $action, user: $userId)';
}

// ═══════════════════════════════════════════════════════════════════════════
// DAO
// ═══════════════════════════════════════════════════════════════════════════

class WorkspaceDao {
  final DatabaseHelper _dbHelper;

  WorkspaceDao([DatabaseHelper? helper])
      : _dbHelper = helper ?? DatabaseHelper();

  Future<Database> get _db => _dbHelper.database;

  // ========================================================================
  // Workspaces
  // ========================================================================

  Future<void> insertWorkspace(Workspace workspace) async {
    final db = await _db;
    await db.insert(
      'workspaces',
      workspace.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<Workspace?> getWorkspaceById(String workspaceId) async {
    final db = await _db;
    final rows = await db.query(
      'workspaces',
      where: 'workspace_id = ?',
      whereArgs: [workspaceId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Workspace.fromMap(rows.first);
  }

  Future<List<Workspace>> getAllWorkspaces() async {
    final db = await _db;
    final rows = await db.query('workspaces', orderBy: 'name ASC');
    return rows.map(Workspace.fromMap).toList();
  }

  Future<void> updateWorkspace(Workspace workspace) async {
    final db = await _db;
    await db.update(
      'workspaces',
      workspace.toMap(),
      where: 'workspace_id = ?',
      whereArgs: [workspace.workspaceId],
    );
  }

  Future<void> deleteWorkspace(String workspaceId) async {
    final db = await _db;
    // CASCADE deletes members, trips, reports, and audit events.
    await db.delete(
      'workspaces',
      where: 'workspace_id = ?',
      whereArgs: [workspaceId],
    );
  }

  // ========================================================================
  // Workspace members
  // ========================================================================

  Future<int> insertMember(WorkspaceMember member) async {
    final db = await _db;
    return db.insert(
      'workspace_members',
      member.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<WorkspaceMember>> getMembersByWorkspace(
    String workspaceId,
  ) async {
    final db = await _db;
    final rows = await db.query(
      'workspace_members',
      where: 'workspace_id = ?',
      whereArgs: [workspaceId],
      orderBy: 'invited_at ASC',
    );
    return rows.map(WorkspaceMember.fromMap).toList();
  }

  Future<WorkspaceMember?> getMember(
    String workspaceId,
    String userId,
  ) async {
    final db = await _db;
    final rows = await db.query(
      'workspace_members',
      where: 'workspace_id = ? AND user_id = ?',
      whereArgs: [workspaceId, userId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return WorkspaceMember.fromMap(rows.first);
  }

  Future<void> updateMemberRole(
    String workspaceId,
    String userId,
    String newRole,
  ) async {
    final db = await _db;
    await db.update(
      'workspace_members',
      {'role': newRole},
      where: 'workspace_id = ? AND user_id = ?',
      whereArgs: [workspaceId, userId],
    );
  }

  Future<void> markMemberJoined(
    String workspaceId,
    String userId,
  ) async {
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'workspace_members',
      {'joined_at': now},
      where: 'workspace_id = ? AND user_id = ?',
      whereArgs: [workspaceId, userId],
    );
  }

  Future<void> removeMember(String workspaceId, String userId) async {
    final db = await _db;
    await db.delete(
      'workspace_members',
      where: 'workspace_id = ? AND user_id = ?',
      whereArgs: [workspaceId, userId],
    );
  }

  // ========================================================================
  // Trips
  // ========================================================================

  Future<void> insertTrip(Trip trip) async {
    final db = await _db;
    await db.insert(
      'trips',
      trip.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<Trip?> getTripById(String tripId) async {
    final db = await _db;
    final rows = await db.query(
      'trips',
      where: 'trip_id = ?',
      whereArgs: [tripId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Trip.fromMap(rows.first);
  }

  Future<List<Trip>> getTripsByWorkspace(String workspaceId) async {
    final db = await _db;
    final rows = await db.query(
      'trips',
      where: 'workspace_id = ?',
      whereArgs: [workspaceId],
      orderBy: 'created_at DESC',
    );
    return rows.map(Trip.fromMap).toList();
  }

  Future<void> updateTrip(Trip trip) async {
    final db = await _db;
    await db.update(
      'trips',
      trip.toMap(),
      where: 'trip_id = ?',
      whereArgs: [trip.tripId],
    );
  }

  Future<void> deleteTrip(String tripId) async {
    final db = await _db;
    await db.delete('trips', where: 'trip_id = ?', whereArgs: [tripId]);
  }

  // ========================================================================
  // Expense reports
  // ========================================================================

  Future<void> insertExpenseReport(ExpenseReport report) async {
    final db = await _db;
    await db.insert(
      'expense_reports',
      report.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<ExpenseReport?> getExpenseReportById(String reportId) async {
    final db = await _db;
    final rows = await db.query(
      'expense_reports',
      where: 'report_id = ?',
      whereArgs: [reportId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ExpenseReport.fromMap(rows.first);
  }

  Future<List<ExpenseReport>> getExpenseReportsByWorkspace(
    String workspaceId,
  ) async {
    final db = await _db;
    final rows = await db.query(
      'expense_reports',
      where: 'workspace_id = ?',
      whereArgs: [workspaceId],
      orderBy: 'created_at DESC',
    );
    return rows.map(ExpenseReport.fromMap).toList();
  }

  Future<List<ExpenseReport>> getExpenseReportsByTrip(
    String tripId,
  ) async {
    final db = await _db;
    final rows = await db.query(
      'expense_reports',
      where: 'trip_id = ?',
      whereArgs: [tripId],
      orderBy: 'created_at DESC',
    );
    return rows.map(ExpenseReport.fromMap).toList();
  }

  Future<List<ExpenseReport>> getExpenseReportsByStatus(
    String workspaceId,
    String status,
  ) async {
    final db = await _db;
    final rows = await db.query(
      'expense_reports',
      where: 'workspace_id = ? AND status = ?',
      whereArgs: [workspaceId, status],
      orderBy: 'created_at DESC',
    );
    return rows.map(ExpenseReport.fromMap).toList();
  }

  Future<void> updateExpenseReport(ExpenseReport report) async {
    final db = await _db;
    await db.update(
      'expense_reports',
      report.toMap(),
      where: 'report_id = ?',
      whereArgs: [report.reportId],
    );
  }

  /// Transitions an expense report to the given [status], recording the
  /// actor and timestamp for submit / approve transitions.
  Future<void> updateExpenseReportStatus(
    String reportId, {
    required String status,
    String? actorUserId,
  }) async {
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();
    final updates = <String, dynamic>{
      'status': status,
      'updated_at': now,
    };
    if (status == ReportStatus.submitted && actorUserId != null) {
      updates['submitted_by'] = actorUserId;
      updates['submitted_at'] = now;
    } else if (status == ReportStatus.approved && actorUserId != null) {
      updates['approved_by'] = actorUserId;
      updates['approved_at'] = now;
    }
    await db.update(
      'expense_reports',
      updates,
      where: 'report_id = ?',
      whereArgs: [reportId],
    );
  }

  Future<void> deleteExpenseReport(String reportId) async {
    final db = await _db;
    await db.delete(
      'expense_reports',
      where: 'report_id = ?',
      whereArgs: [reportId],
    );
  }

  // ========================================================================
  // Audit events
  // ========================================================================

  Future<void> insertAuditEvent(AuditEvent event) async {
    final db = await _db;
    await db.insert('audit_events', event.toMap());
  }

  /// Convenience method for logging an audit event with minimal boilerplate.
  Future<void> logAuditEvent({
    required String eventId,
    required String workspaceId,
    required String userId,
    required String action,
    String? targetType,
    String? targetId,
    Map<String, dynamic>? metadata,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await insertAuditEvent(AuditEvent(
      eventId: eventId,
      workspaceId: workspaceId,
      userId: userId,
      action: action,
      targetType: targetType,
      targetId: targetId,
      metadata: metadata,
      createdAt: now,
    ));
  }

  Future<List<AuditEvent>> getAuditEventsByWorkspace(
    String workspaceId, {
    int? limit,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'audit_events',
      where: 'workspace_id = ?',
      whereArgs: [workspaceId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(AuditEvent.fromMap).toList();
  }

  Future<List<AuditEvent>> getAuditEventsByUser(
    String workspaceId,
    String userId, {
    int? limit,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'audit_events',
      where: 'workspace_id = ? AND user_id = ?',
      whereArgs: [workspaceId, userId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(AuditEvent.fromMap).toList();
  }

  Future<List<AuditEvent>> getAuditEventsForTarget(
    String workspaceId, {
    required String targetType,
    required String targetId,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'audit_events',
      where: 'workspace_id = ? AND target_type = ? AND target_id = ?',
      whereArgs: [workspaceId, targetType, targetId],
      orderBy: 'created_at DESC',
    );
    return rows.map(AuditEvent.fromMap).toList();
  }

  /// Deletes audit events older than [before] (ISO-8601 string).
  Future<int> deleteAuditEventsBefore(
    String workspaceId,
    String before,
  ) async {
    final db = await _db;
    return db.delete(
      'audit_events',
      where: 'workspace_id = ? AND created_at < ?',
      whereArgs: [workspaceId, before],
    );
  }
}
