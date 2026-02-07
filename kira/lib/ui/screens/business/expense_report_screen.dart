// Kira - The Receipt Saver
// Expense reports screen: create from trip or manual selection, status flow
// (draft -> submitted -> approved -> exported), submit/approve buttons,
// CSV + indexes + optional zipped images export, status badges.

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../../theme/kira_icons.dart';
import '../../theme/kira_theme.dart';

// ---------------------------------------------------------------------------
// In-memory expense report model (backed by SQLite expense_reports table)
// ---------------------------------------------------------------------------

enum _ReportStatus { draft, submitted, approved, exported }

class _ExpenseReport {
  final String reportId;
  final String workspaceId;
  final String? tripId;
  final String title;
  _ReportStatus status;
  final double totalAmount;
  final String currencyCode;
  final String? submittedBy;
  final String? approvedBy;
  final String? notes;
  final String createdAt;

  _ExpenseReport({
    required this.reportId,
    required this.workspaceId,
    this.tripId,
    required this.title,
    this.status = _ReportStatus.draft,
    this.totalAmount = 0,
    this.currencyCode = 'CAD',
    this.submittedBy,
    this.approvedBy,
    this.notes,
    required this.createdAt,
  });
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class ExpenseReportScreen extends StatefulWidget {
  final String? workspaceId;
  final String? tripId;
  /// Whether the current user is an approver/admin.
  final bool isApprover;

  const ExpenseReportScreen({
    super.key,
    this.workspaceId,
    this.tripId,
    this.isApprover = false,
  });

  @override
  State<ExpenseReportScreen> createState() => _ExpenseReportScreenState();
}

class _ExpenseReportScreenState extends State<ExpenseReportScreen> {
  List<_ExpenseReport> _reports = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() => _loading = true);
    // TODO: Load from DAO for the given workspace/trip.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    setState(() => _loading = false);
  }

  String _formatCurrency(double amount, String currencyCode) {
    return NumberFormat.currency(
      symbol: currencyCode == 'CAD' ? r'CA$' : r'US$',
      decimalDigits: 2,
    ).format(amount);
  }

  String _statusLabel(AppLocalizations l10n, _ReportStatus status) {
    switch (status) {
      case _ReportStatus.draft:
        return l10n.reportStatusDraft;
      case _ReportStatus.submitted:
        return l10n.reportStatusSubmitted;
      case _ReportStatus.approved:
        return l10n.reportStatusApproved;
      case _ReportStatus.exported:
        return l10n.reportStatusExported;
    }
  }

  Color _statusColor(_ReportStatus status) {
    switch (status) {
      case _ReportStatus.draft:
        return KiraColors.mediumGrey;
      case _ReportStatus.submitted:
        return KiraColors.pendingAmber;
      case _ReportStatus.approved:
        return KiraColors.syncedGreen;
      case _ReportStatus.exported:
        return KiraColors.infoBlue;
    }
  }

  IconData _statusIcon(_ReportStatus status) {
    switch (status) {
      case _ReportStatus.draft:
        return KiraIcons.edit;
      case _ReportStatus.submitted:
        return KiraIcons.syncPending;
      case _ReportStatus.approved:
        return KiraIcons.approve;
      case _ReportStatus.exported:
        return KiraIcons.exportIcon;
    }
  }

  Future<void> _createReport(AppLocalizations l10n) async {
    final titleController = TextEditingController();
    final notesController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.createExpenseReport),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.expenseReports,
                hintText: l10n.expenseReports,
              ),
            ),
            const SizedBox(height: KiraDimens.spacingMd),
            TextField(
              controller: notesController,
              decoration: InputDecoration(
                labelText: l10n.notes,
                hintText: l10n.notes,
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.save),
          ),
        ],
      ),
    );

    if (result == true && titleController.text.trim().isNotEmpty) {
      final report = _ExpenseReport(
        reportId: DateTime.now().millisecondsSinceEpoch.toString(),
        workspaceId: widget.workspaceId ?? '',
        tripId: widget.tripId,
        title: titleController.text.trim(),
        notes: notesController.text.trim().isEmpty
            ? null
            : notesController.text.trim(),
        createdAt: DateTime.now().toUtc().toIso8601String(),
      );
      setState(() => _reports.add(report));
      // TODO: Persist via DAO.
    }

    titleController.dispose();
    notesController.dispose();
  }

  void _submitReport(_ExpenseReport report, AppLocalizations l10n) {
    if (report.status != _ReportStatus.draft) return;
    setState(() => report.status = _ReportStatus.submitted);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.submitReport)),
    );
    // TODO: Persist status change.
  }

  void _approveReport(_ExpenseReport report, AppLocalizations l10n) {
    if (report.status != _ReportStatus.submitted) return;
    setState(() => report.status = _ReportStatus.approved);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.approveReport)),
    );
    // TODO: Persist status change.
  }

  void _exportReport(_ExpenseReport report, AppLocalizations l10n) {
    setState(() => report.status = _ReportStatus.exported);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.exportReport)),
    );
    // TODO: Generate CSV + indexes + optional zipped images.
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
        title: Text(l10n.expenseReports),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createReport(l10n),
        icon: const Icon(KiraIcons.add),
        label: Text(l10n.createExpenseReport),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _reports.isEmpty
              ? _buildEmptyState(l10n, colors, text)
              : ListView.builder(
                  padding: const EdgeInsets.only(
                    bottom: KiraDimens.spacingXxxl * 2,
                    top: KiraDimens.spacingSm,
                  ),
                  itemCount: _reports.length,
                  itemBuilder: (context, index) =>
                      _buildReportCard(_reports[index], l10n),
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
            KiraIcons.summary,
            size: KiraDimens.iconXl,
            color: colors.outline,
          ),
          const SizedBox(height: KiraDimens.spacingLg),
          Text(
            l10n.expenseReports,
            style: text.titleMedium?.copyWith(color: colors.outline),
          ),
          const SizedBox(height: KiraDimens.spacingSm),
          Text(
            l10n.createExpenseReport,
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildReportCard(_ExpenseReport report, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;
    final statusColor = _statusColor(report.status);

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: KiraDimens.spacingLg,
        vertical: KiraDimens.spacingSm,
      ),
      child: Padding(
        padding: const EdgeInsets.all(KiraDimens.spacingLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title and status badge
            Row(
              children: [
                Expanded(
                  child: Text(
                    report.title,
                    style: text.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _buildStatusBadge(report.status, l10n, statusColor, text),
              ],
            ),
            const SizedBox(height: KiraDimens.spacingSm),

            // Amount
            Text(
              _formatCurrency(report.totalAmount, report.currencyCode),
              style: text.titleMedium?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: KiraDimens.spacingXs),

            // Notes
            if (report.notes != null)
              Text(
                report.notes!,
                style: text.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: KiraDimens.spacingMd),

            // Status flow indicator
            _buildStatusFlow(report.status, text),
            const SizedBox(height: KiraDimens.spacingMd),

            // Action buttons
            _buildActionButtons(report, l10n, colors),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(
    _ReportStatus status,
    AppLocalizations l10n,
    Color color,
    TextTheme text,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KiraDimens.spacingSm,
        vertical: KiraDimens.spacingXxs,
      ),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(KiraDimens.radiusFull),
        border: Border.all(color: color.withAlpha(100)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_statusIcon(status), size: 14, color: color),
          const SizedBox(width: KiraDimens.spacingXxs),
          Text(
            _statusLabel(l10n, status),
            style: text.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusFlow(_ReportStatus currentStatus, TextTheme text) {
    final statuses = _ReportStatus.values;
    final currentIdx = statuses.indexOf(currentStatus);

    return Row(
      children: List.generate(statuses.length * 2 - 1, (index) {
        if (index.isOdd) {
          // Connector line
          final prevIdx = index ~/ 2;
          return Expanded(
            child: Container(
              height: 2,
              color: prevIdx < currentIdx
                  ? KiraColors.syncedGreen
                  : KiraColors.lightGrey,
            ),
          );
        }

        final statusIdx = index ~/ 2;
        final isCompleted = statusIdx <= currentIdx;
        final isCurrent = statusIdx == currentIdx;

        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCompleted
                ? KiraColors.syncedGreen
                : KiraColors.lightGrey,
            border: isCurrent
                ? Border.all(color: KiraColors.syncedGreen, width: 2)
                : null,
          ),
        );
      }),
    );
  }

  Widget _buildActionButtons(
    _ExpenseReport report,
    AppLocalizations l10n,
    ColorScheme colors,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Submit button (draft -> submitted)
        if (report.status == _ReportStatus.draft)
          ElevatedButton.icon(
            onPressed: () => _submitReport(report, l10n),
            icon: const Icon(KiraIcons.syncPending, size: KiraDimens.iconSm),
            label: Text(l10n.submitReport),
          ),

        // Approve button (submitted -> approved, for approvers)
        if (report.status == _ReportStatus.submitted && widget.isApprover)
          ElevatedButton.icon(
            onPressed: () => _approveReport(report, l10n),
            icon: const Icon(KiraIcons.approve, size: KiraDimens.iconSm),
            label: Text(l10n.approveReport),
            style: ElevatedButton.styleFrom(
              backgroundColor: KiraColors.syncedGreen,
              foregroundColor: Colors.white,
            ),
          ),

        // Export button (approved or exported)
        if (report.status == _ReportStatus.approved ||
            report.status == _ReportStatus.exported) ...[
          const SizedBox(width: KiraDimens.spacingSm),
          OutlinedButton.icon(
            onPressed: () => _exportReport(report, l10n),
            icon: const Icon(KiraIcons.exportIcon, size: KiraDimens.iconSm),
            label: Text(l10n.exportReport),
          ),
          const SizedBox(width: KiraDimens.spacingSm),
          OutlinedButton.icon(
            onPressed: () {
              // TODO: Export with zipped images.
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.exportIncludeImages)),
              );
            },
            icon: const Icon(KiraIcons.image, size: KiraDimens.iconSm),
            label: Text(l10n.exportIncludeImages),
          ),
        ],
      ],
    );
  }
}
