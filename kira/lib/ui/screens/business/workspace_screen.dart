// Kira - The Receipt Saver
// Business workspace screen: list workspaces, create workspace, workspace
// detail with members, roles, trips, and expense reports.

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../../../core/db/database_helper.dart';
import '../../theme/kira_icons.dart';
import '../../theme/kira_theme.dart';

// ---------------------------------------------------------------------------
// In-memory models for workspace management (backed by SQLite via DAO layer)
// ---------------------------------------------------------------------------

class _Workspace {
  final String workspaceId;
  final String name;
  final String ownerUserId;
  final String createdAt;
  final List<_WorkspaceMember> members;

  _Workspace({
    required this.workspaceId,
    required this.name,
    required this.ownerUserId,
    required this.createdAt,
    this.members = const [],
  });
}

class _WorkspaceMember {
  final String userId;
  final String displayName;
  final String email;
  final String role; // admin | approver | member | accountant

  _WorkspaceMember({
    required this.userId,
    required this.displayName,
    required this.email,
    required this.role,
  });
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  List<_Workspace> _workspaces = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadWorkspaces();
  }

  Future<void> _loadWorkspaces() async {
    setState(() => _loading = true);
    // TODO: Load from DAO.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    setState(() => _loading = false);
  }

  String _roleLabel(AppLocalizations l10n, String role) {
    switch (role) {
      case 'admin':
        return l10n.workspaceRoleAdmin;
      case 'approver':
        return l10n.workspaceRoleApprover;
      case 'member':
        return l10n.workspaceRoleMember;
      case 'accountant':
        return l10n.workspaceRoleAccountant;
      default:
        return role;
    }
  }

  IconData _roleIcon(String role) {
    switch (role) {
      case 'admin':
        return KiraIcons.admin;
      case 'approver':
        return KiraIcons.approve;
      case 'member':
        return KiraIcons.person;
      case 'accountant':
        return KiraIcons.summary;
      default:
        return KiraIcons.person;
    }
  }

  Future<void> _createWorkspace(AppLocalizations l10n) async {
    final nameController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.createWorkspace),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: l10n.workspaceName,
            labelText: l10n.workspaceName,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.of(ctx).pop(nameController.text.trim()),
            child: Text(l10n.save),
          ),
        ],
      ),
    );

    nameController.dispose();

    if (result != null && result.isNotEmpty) {
      final newWs = _Workspace(
        workspaceId: DateTime.now().millisecondsSinceEpoch.toString(),
        name: result,
        ownerUserId: 'current_user',
        createdAt: DateTime.now().toUtc().toIso8601String(),
        members: [
          _WorkspaceMember(
            userId: 'current_user',
            displayName: 'You',
            email: '',
            role: 'admin',
          ),
        ],
      );
      setState(() => _workspaces.add(newWs));
      // TODO: Persist via DAO.
    }
  }

  Future<void> _inviteMember(
    AppLocalizations l10n,
    _Workspace workspace,
  ) async {
    final emailController = TextEditingController();
    String selectedRole = 'member';

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Text(l10n.workspaceMembers),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    hintText: 'Email',
                    labelText: 'Email',
                  ),
                ),
                const SizedBox(height: KiraDimens.spacingMd),
                DropdownButtonFormField<String>(
                  value: selectedRole,
                  items: ['admin', 'approver', 'member', 'accountant']
                      .map((r) => DropdownMenuItem(
                            value: r,
                            child: Text(_roleLabel(l10n, r)),
                          ))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => selectedRole = val);
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(l10n.cancel),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop({
                  'email': emailController.text.trim(),
                  'role': selectedRole,
                }),
                child: Text(l10n.save),
              ),
            ],
          );
        });
      },
    );

    emailController.dispose();

    if (result != null &&
        result['email'] != null &&
        result['email']!.isNotEmpty) {
      setState(() {
        workspace.members.add(_WorkspaceMember(
          userId: DateTime.now().millisecondsSinceEpoch.toString(),
          displayName: result['email']!.split('@').first,
          email: result['email']!,
          role: result['role'] ?? 'member',
        ));
      });
      // TODO: Send invitation and persist.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(KiraIcons.arrowBack),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: l10n.back,
        ),
        title: Text(l10n.workspaces),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createWorkspace(l10n),
        icon: const Icon(KiraIcons.add),
        label: Text(l10n.createWorkspace),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _workspaces.isEmpty
              ? _buildEmptyState(l10n, colors, text)
              : ListView.builder(
                  padding: const EdgeInsets.only(
                    bottom: KiraDimens.spacingXxxl * 2,
                    top: KiraDimens.spacingSm,
                  ),
                  itemCount: _workspaces.length,
                  itemBuilder: (context, index) =>
                      _buildWorkspaceCard(l10n, _workspaces[index]),
                ),
    );
  }

  Widget _buildEmptyState(
    AppLocalizations l10n,
    ColorScheme colors,
    TextTheme text,
  ) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            KiraIcons.workspace,
            size: KiraDimens.iconXl,
            color: colors.outline,
          ),
          const SizedBox(height: KiraDimens.spacingLg),
          Text(
            l10n.workspaces,
            style: text.titleMedium?.copyWith(color: colors.outline),
          ),
          const SizedBox(height: KiraDimens.spacingSm),
          Text(
            l10n.createWorkspace,
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildWorkspaceCard(AppLocalizations l10n, _Workspace ws) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: KiraDimens.spacingLg,
        vertical: KiraDimens.spacingSm,
      ),
      child: ExpansionTile(
        leading: Icon(
          KiraIcons.workspace,
          color: colors.primary,
          size: KiraDimens.iconMd,
        ),
        title: Text(ws.name, style: text.titleSmall),
        subtitle: Text(
          '${ws.members.length} ${l10n.workspaceMembers}',
          style: text.bodySmall,
        ),
        children: [
          const Divider(height: 1),

          // Members list
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KiraDimens.spacingLg,
              vertical: KiraDimens.spacingSm,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.workspaceMembers, style: text.titleSmall),
                TextButton.icon(
                  onPressed: () => _inviteMember(l10n, ws),
                  icon: const Icon(KiraIcons.add, size: KiraDimens.iconSm),
                  label: Text(l10n.workspaceMembers),
                ),
              ],
            ),
          ),

          ...ws.members.map((member) => ListTile(
                leading: CircleAvatar(
                  backgroundColor: colors.primaryContainer,
                  child: Icon(
                    _roleIcon(member.role),
                    color: colors.onPrimaryContainer,
                    size: KiraDimens.iconSm,
                  ),
                ),
                title: Text(member.displayName, style: text.bodyMedium),
                subtitle: Text(
                  _roleLabel(l10n, member.role),
                  style: text.bodySmall,
                ),
                dense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: KiraDimens.spacingLg,
                ),
              )),

          // Navigation to trips and expense reports
          const Divider(height: 1),
          ListTile(
            leading: const Icon(KiraIcons.trip, size: KiraDimens.iconMd),
            title: Text(l10n.trips, style: text.bodyMedium),
            trailing: const Icon(
              KiraIcons.chevronRight,
              size: KiraDimens.iconMd,
            ),
            onTap: () {
              // TODO: Navigate to TripScreen with workspace context.
            },
            contentPadding: const EdgeInsets.symmetric(
              horizontal: KiraDimens.spacingLg,
            ),
          ),
          ListTile(
            leading: const Icon(KiraIcons.summary, size: KiraDimens.iconMd),
            title: Text(l10n.expenseReports, style: text.bodyMedium),
            trailing: const Icon(
              KiraIcons.chevronRight,
              size: KiraDimens.iconMd,
            ),
            onTap: () {
              // TODO: Navigate to ExpenseReportScreen with workspace context.
            },
            contentPadding: const EdgeInsets.symmetric(
              horizontal: KiraDimens.spacingLg,
            ),
          ),
          const SizedBox(height: KiraDimens.spacingSm),
        ],
      ),
    );
  }
}
