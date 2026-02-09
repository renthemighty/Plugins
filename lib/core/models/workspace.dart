/// Business workspace models for multi-user receipt management.
///
/// This file contains the five interconnected models that power the
/// collaborative / business tier of Kira:
///
///   - [Workspace]        -- a business entity that owns receipt data.
///   - [WorkspaceMember]  -- a user's membership & role within a workspace.
///   - [Trip]             -- a named date-range grouping of expenses.
///   - [ExpenseReport]    -- a collection of receipts for review / export.
///   - [AuditEvent]       -- an immutable log entry for compliance.
library;

import 'package:collection/collection.dart';

// ============================================================================
// Enums
// ============================================================================

/// The role a user holds within a [Workspace].
enum WorkspaceRole {
  /// Full control: invite/remove members, change roles, delete workspace.
  admin,

  /// Can approve or reject expense reports.
  approver,

  /// Standard member: can capture receipts and create reports.
  member,

  /// Read-only access to approved reports and exported data.
  accountant,
}

/// Lifecycle status of an [ExpenseReport].
enum ExpenseReportStatus {
  /// The report is still being assembled by the creator.
  draft,

  /// The report has been submitted for approval.
  submitted,

  /// An approver has approved the report.
  approved,

  /// The report has been exported (CSV/PDF) for accounting.
  exported,
}

// ============================================================================
// Enum helpers
// ============================================================================

String _roleToString(WorkspaceRole role) {
  switch (role) {
    case WorkspaceRole.admin:
      return 'admin';
    case WorkspaceRole.approver:
      return 'approver';
    case WorkspaceRole.member:
      return 'member';
    case WorkspaceRole.accountant:
      return 'accountant';
  }
}

WorkspaceRole _roleFromString(String value) {
  switch (value) {
    case 'admin':
      return WorkspaceRole.admin;
    case 'approver':
      return WorkspaceRole.approver;
    case 'member':
      return WorkspaceRole.member;
    case 'accountant':
      return WorkspaceRole.accountant;
    default:
      throw ArgumentError('Unknown WorkspaceRole value: $value');
  }
}

String _reportStatusToString(ExpenseReportStatus status) {
  switch (status) {
    case ExpenseReportStatus.draft:
      return 'draft';
    case ExpenseReportStatus.submitted:
      return 'submitted';
    case ExpenseReportStatus.approved:
      return 'approved';
    case ExpenseReportStatus.exported:
      return 'exported';
  }
}

ExpenseReportStatus _reportStatusFromString(String value) {
  switch (value) {
    case 'draft':
      return ExpenseReportStatus.draft;
    case 'submitted':
      return ExpenseReportStatus.submitted;
    case 'approved':
      return ExpenseReportStatus.approved;
    case 'exported':
      return ExpenseReportStatus.exported;
    default:
      throw ArgumentError('Unknown ExpenseReportStatus value: $value');
  }
}

// ============================================================================
// Workspace
// ============================================================================

/// A business workspace that groups users, trips, and expense reports.
class Workspace {
  /// Unique identifier (UUID v4).
  final String id;

  /// Display name chosen by the workspace admin.
  final String name;

  /// User ID of the workspace creator / owner.
  final String ownerId;

  /// ISO-8601 UTC timestamp of creation.
  final String createdAt;

  /// Root path or prefix for cloud storage associated with this workspace.
  final String storageRoot;

  const Workspace({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.createdAt,
    required this.storageRoot,
  });

  factory Workspace.fromJson(Map<String, dynamic> json) {
    return Workspace(
      id: json['id'] as String,
      name: json['name'] as String,
      ownerId: json['owner_id'] as String,
      createdAt: json['created_at'] as String,
      storageRoot: json['storage_root'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'owner_id': ownerId,
      'created_at': createdAt,
      'storage_root': storageRoot,
    };
  }

  Workspace copyWith({
    String? id,
    String? name,
    String? ownerId,
    String? createdAt,
    String? storageRoot,
  }) {
    return Workspace(
      id: id ?? this.id,
      name: name ?? this.name,
      ownerId: ownerId ?? this.ownerId,
      createdAt: createdAt ?? this.createdAt,
      storageRoot: storageRoot ?? this.storageRoot,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Workspace &&
        other.id == id &&
        other.name == name &&
        other.ownerId == ownerId &&
        other.createdAt == createdAt &&
        other.storageRoot == storageRoot;
  }

  @override
  int get hashCode => Object.hash(id, name, ownerId, createdAt, storageRoot);

  @override
  String toString() => 'Workspace(id: $id, name: $name, owner: $ownerId)';
}

// ============================================================================
// WorkspaceMember
// ============================================================================

/// A user's membership record within a [Workspace].
class WorkspaceMember {
  /// Unique membership ID (UUID v4).
  final String id;

  /// The workspace this membership belongs to.
  final String workspaceId;

  /// The authenticated user's ID.
  final String userId;

  /// The role granted to this user in the workspace.
  final WorkspaceRole role;

  /// ISO-8601 UTC timestamp of when the user joined.
  final String joinedAt;

  const WorkspaceMember({
    required this.id,
    required this.workspaceId,
    required this.userId,
    required this.role,
    required this.joinedAt,
  });

  factory WorkspaceMember.fromJson(Map<String, dynamic> json) {
    return WorkspaceMember(
      id: json['id'] as String,
      workspaceId: json['workspace_id'] as String,
      userId: json['user_id'] as String,
      role: _roleFromString(json['role'] as String),
      joinedAt: json['joined_at'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'workspace_id': workspaceId,
      'user_id': userId,
      'role': _roleToString(role),
      'joined_at': joinedAt,
    };
  }

  WorkspaceMember copyWith({
    String? id,
    String? workspaceId,
    String? userId,
    WorkspaceRole? role,
    String? joinedAt,
  }) {
    return WorkspaceMember(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      userId: userId ?? this.userId,
      role: role ?? this.role,
      joinedAt: joinedAt ?? this.joinedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WorkspaceMember &&
        other.id == id &&
        other.workspaceId == workspaceId &&
        other.userId == userId &&
        other.role == role &&
        other.joinedAt == joinedAt;
  }

  @override
  int get hashCode =>
      Object.hash(id, workspaceId, userId, role, joinedAt);

  @override
  String toString() =>
      'WorkspaceMember(id: $id, userId: $userId, '
      'role: ${_roleToString(role)})';
}

// ============================================================================
// Trip
// ============================================================================

/// A named date-range grouping of expenses within a workspace.
class Trip {
  /// Unique identifier (UUID v4).
  final String id;

  /// The workspace this trip belongs to.
  final String workspaceId;

  /// Display name (e.g. "Montreal Client Visit Q2 2025").
  final String name;

  /// Start date in `YYYY-MM-DD` format.
  final String startDate;

  /// End date in `YYYY-MM-DD` format.
  final String endDate;

  /// User ID of the person who created this trip.
  final String createdBy;

  const Trip({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.createdBy,
  });

  factory Trip.fromJson(Map<String, dynamic> json) {
    return Trip(
      id: json['id'] as String,
      workspaceId: json['workspace_id'] as String,
      name: json['name'] as String,
      startDate: json['start_date'] as String,
      endDate: json['end_date'] as String,
      createdBy: json['created_by'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'workspace_id': workspaceId,
      'name': name,
      'start_date': startDate,
      'end_date': endDate,
      'created_by': createdBy,
    };
  }

  Trip copyWith({
    String? id,
    String? workspaceId,
    String? name,
    String? startDate,
    String? endDate,
    String? createdBy,
  }) {
    return Trip(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      name: name ?? this.name,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      createdBy: createdBy ?? this.createdBy,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Trip &&
        other.id == id &&
        other.workspaceId == workspaceId &&
        other.name == name &&
        other.startDate == startDate &&
        other.endDate == endDate &&
        other.createdBy == createdBy;
  }

  @override
  int get hashCode =>
      Object.hash(id, workspaceId, name, startDate, endDate, createdBy);

  @override
  String toString() =>
      'Trip(id: $id, name: $name, $startDate -> $endDate)';
}

// ============================================================================
// ExpenseReport
// ============================================================================

/// A collection of receipts packaged for review, approval, and export.
class ExpenseReport {
  /// Unique identifier (UUID v4).
  final String id;

  /// The workspace this report belongs to.
  final String workspaceId;

  /// Optional trip this report is associated with. Null for ad-hoc reports.
  final String? tripId;

  /// Human-readable title.
  final String title;

  /// Current lifecycle status.
  final ExpenseReportStatus status;

  /// Ordered list of receipt IDs included in this report.
  final List<String> receiptIds;

  /// User ID of the report creator.
  final String createdBy;

  /// ISO-8601 UTC timestamp of creation.
  final String createdAt;

  /// ISO-8601 UTC timestamp of the last modification.
  final String updatedAt;

  const ExpenseReport({
    required this.id,
    required this.workspaceId,
    this.tripId,
    required this.title,
    this.status = ExpenseReportStatus.draft,
    required this.receiptIds,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ExpenseReport.fromJson(Map<String, dynamic> json) {
    final rawIds = json['receipt_ids'] as List<dynamic>? ?? <dynamic>[];
    return ExpenseReport(
      id: json['id'] as String,
      workspaceId: json['workspace_id'] as String,
      tripId: json['trip_id'] as String?,
      title: json['title'] as String,
      status: _reportStatusFromString(json['status'] as String? ?? 'draft'),
      receiptIds: rawIds.cast<String>(),
      createdBy: json['created_by'] as String,
      createdAt: json['created_at'] as String,
      updatedAt: json['updated_at'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'workspace_id': workspaceId,
      'trip_id': tripId,
      'title': title,
      'status': _reportStatusToString(status),
      'receipt_ids': receiptIds,
      'created_by': createdBy,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  ExpenseReport copyWith({
    String? id,
    String? workspaceId,
    String? Function()? tripId,
    String? title,
    ExpenseReportStatus? status,
    List<String>? receiptIds,
    String? createdBy,
    String? createdAt,
    String? updatedAt,
  }) {
    return ExpenseReport(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      tripId: tripId != null ? tripId() : this.tripId,
      title: title ?? this.title,
      status: status ?? this.status,
      receiptIds: receiptIds ?? this.receiptIds,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ExpenseReport) return false;
    return other.id == id &&
        other.workspaceId == workspaceId &&
        other.tripId == tripId &&
        other.title == title &&
        other.status == status &&
        const ListEquality<String>().equals(other.receiptIds, receiptIds) &&
        other.createdBy == createdBy &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(
        id,
        workspaceId,
        tripId,
        title,
        status,
        const ListEquality<String>().hash(receiptIds),
        createdBy,
        createdAt,
        updatedAt,
      );

  @override
  String toString() =>
      'ExpenseReport(id: $id, title: $title, '
      'status: ${_reportStatusToString(status)}, '
      'receipts: ${receiptIds.length})';
}

// ============================================================================
// AuditEvent
// ============================================================================

/// An immutable log entry recording a user action for compliance / auditing.
class AuditEvent {
  /// Unique identifier (UUID v4).
  final String id;

  /// The workspace in which this event occurred.
  final String workspaceId;

  /// The user who performed the action.
  final String actorId;

  /// A machine-readable action verb (e.g. `receipt.created`,
  /// `report.approved`).
  final String action;

  /// The type of entity the action targeted (e.g. `receipt`, `report`,
  /// `member`).
  final String targetType;

  /// The ID of the targeted entity.
  final String targetId;

  /// Arbitrary structured metadata associated with the event.
  final Map<String, dynamic> metadata;

  /// ISO-8601 UTC timestamp of the event.
  final String timestamp;

  const AuditEvent({
    required this.id,
    required this.workspaceId,
    required this.actorId,
    required this.action,
    required this.targetType,
    required this.targetId,
    this.metadata = const <String, dynamic>{},
    required this.timestamp,
  });

  factory AuditEvent.fromJson(Map<String, dynamic> json) {
    return AuditEvent(
      id: json['id'] as String,
      workspaceId: json['workspace_id'] as String,
      actorId: json['actor_id'] as String,
      action: json['action'] as String,
      targetType: json['target_type'] as String,
      targetId: json['target_id'] as String,
      metadata: (json['metadata'] as Map<String, dynamic>?) ??
          const <String, dynamic>{},
      timestamp: json['timestamp'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'workspace_id': workspaceId,
      'actor_id': actorId,
      'action': action,
      'target_type': targetType,
      'target_id': targetId,
      'metadata': metadata,
      'timestamp': timestamp,
    };
  }

  AuditEvent copyWith({
    String? id,
    String? workspaceId,
    String? actorId,
    String? action,
    String? targetType,
    String? targetId,
    Map<String, dynamic>? metadata,
    String? timestamp,
  }) {
    return AuditEvent(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      actorId: actorId ?? this.actorId,
      action: action ?? this.action,
      targetType: targetType ?? this.targetType,
      targetId: targetId ?? this.targetId,
      metadata: metadata ?? this.metadata,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AuditEvent) return false;
    return other.id == id &&
        other.workspaceId == workspaceId &&
        other.actorId == actorId &&
        other.action == action &&
        other.targetType == targetType &&
        other.targetId == targetId &&
        const MapEquality<String, dynamic>()
            .equals(other.metadata, metadata) &&
        other.timestamp == timestamp;
  }

  @override
  int get hashCode => Object.hash(
        id,
        workspaceId,
        actorId,
        action,
        targetType,
        targetId,
        const MapEquality<String, dynamic>().hash(metadata),
        timestamp,
      );

  @override
  String toString() =>
      'AuditEvent(id: $id, action: $action, '
      'target: $targetType/$targetId, actor: $actorId)';
}
