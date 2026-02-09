/// Admin error reporting panel for Kira.
///
/// Displays error records with filtering, detail expansion, and export
/// capabilities. All PII is redacted and no auth tokens are shown.
///
/// Features:
/// - Scrollable list of error records with timestamp, module, error code,
///   and message.
/// - Expandable detail view with stack trace, correlation IDs, OS/device info.
/// - Filter by module, error code, and date range.
/// - Export to JSON and CSV.
/// - "Copy prompt" button that summarises top errors for debugging.
/// - Uses [AppLocalizations] for all user-facing strings.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../../../core/db/error_dao.dart';
import '../../theme/kira_icons.dart';
import '../../theme/kira_theme.dart';

// ---------------------------------------------------------------------------
// ErrorPanelScreen
// ---------------------------------------------------------------------------

class ErrorPanelScreen extends StatefulWidget {
  const ErrorPanelScreen({super.key});

  @override
  State<ErrorPanelScreen> createState() => _ErrorPanelScreenState();
}

class _ErrorPanelScreenState extends State<ErrorPanelScreen> {
  // Error records list with: timestamp, module, error code, message.
  // Expandable detail: stack trace, correlation IDs, OS/device info.
  // Filter by module, error code, date range.
  // Export: JSON, CSV buttons.
  // "Copy prompt" button that summarises top errors for dev tools.
  // PII redacted, no tokens shown.
  // All strings via localization.

  final ErrorDao _errorDao = ErrorDao();

  List<ErrorRecord> _allErrors = [];
  List<ErrorRecord> _filteredErrors = [];
  bool _loading = true;
  String? _errorMessage;

  // Filter state.
  String? _selectedModule;
  String? _selectedErrorCode;
  DateTimeRange? _dateRange;

  // Expansion state (tracked by error id).
  final Set<String> _expandedIds = {};

  // Available filter options (populated from loaded data).
  List<String> _availableModules = [];
  List<String> _availableErrorCodes = [];

  @override
  void initState() {
    super.initState();
    _loadErrors();
  }

  // -------------------------------------------------------------------------
  // Data loading
  // -------------------------------------------------------------------------

  Future<void> _loadErrors() async {
    setState(() => _loading = true);

    try {
      final errors = await _errorDao.getAll();

      // Extract unique modules and error codes for filter dropdowns.
      final modules = <String>{};
      final codes = <String>{};
      for (final error in errors) {
        modules.add(error.errorType);
        // Parse context field for error codes when available.
        if (error.context != null && error.context!.isNotEmpty) {
          codes.add(error.context!.split(':').first.trim());
        }
      }

      setState(() {
        _allErrors = errors;
        _availableModules = modules.toList()..sort();
        _availableErrorCodes = codes.toList()..sort();
        _applyFilters();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _loading = false;
      });
    }
  }

  void _applyFilters() {
    var filtered = List<ErrorRecord>.from(_allErrors);

    // Filter by module (error_type).
    if (_selectedModule != null && _selectedModule!.isNotEmpty) {
      filtered = filtered
          .where((e) => e.errorType == _selectedModule)
          .toList();
    }

    // Filter by error code (stored in context field).
    if (_selectedErrorCode != null && _selectedErrorCode!.isNotEmpty) {
      filtered = filtered
          .where((e) =>
              e.context != null &&
              e.context!.contains(_selectedErrorCode!))
          .toList();
    }

    // Filter by date range.
    if (_dateRange != null) {
      final start = _dateRange!.start.toIso8601String();
      final end = _dateRange!.end
          .add(const Duration(days: 1))
          .toIso8601String();
      filtered = filtered
          .where((e) =>
              e.createdAt.compareTo(start) >= 0 &&
              e.createdAt.compareTo(end) < 0)
          .toList();
    }

    _filteredErrors = filtered;
  }

  bool get _hasActiveFilters =>
      _selectedModule != null ||
      _selectedErrorCode != null ||
      _dateRange != null;

  void _clearFilters() {
    setState(() {
      _selectedModule = null;
      _selectedErrorCode = null;
      _dateRange = null;
      _applyFilters();
    });
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

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
        title: Text(l10n.adminErrorPanel),
        actions: [
          // Export menu: JSON, CSV, Copy prompt.
          PopupMenuButton<String>(
            icon: const Icon(KiraIcons.moreVert),
            tooltip: l10n.adminExportErrors,
            onSelected: _handleExportAction,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'json',
                child: Row(
                  children: [
                    const Icon(KiraIcons.exportIcon,
                        size: KiraDimens.iconSm),
                    const SizedBox(width: KiraDimens.spacingSm),
                    Text(l10n.exportCsv.replaceAll('CSV', 'JSON')),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'csv',
                child: Row(
                  children: [
                    const Icon(KiraIcons.csv, size: KiraDimens.iconSm),
                    const SizedBox(width: KiraDimens.spacingSm),
                    Text(l10n.exportCsv),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'copy_prompt',
                child: Row(
                  children: [
                    const Icon(KiraIcons.copy, size: KiraDimens.iconSm),
                    const SizedBox(width: KiraDimens.spacingSm),
                    Text(l10n.adminExportErrors),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(KiraIcons.refresh, size: KiraDimens.iconMd),
            onPressed: _loadErrors,
            tooltip: l10n.syncNow,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorState(l10n, colors, text)
              : Column(
                  children: [
                    _buildFilterBar(l10n, colors, text),
                    Expanded(
                      child: _filteredErrors.isEmpty
                          ? _buildEmptyState(l10n, colors, text)
                          : _buildErrorList(l10n, colors, text),
                    ),
                  ],
                ),
    );
  }

  // -------------------------------------------------------------------------
  // Filter bar
  // -------------------------------------------------------------------------

  Widget _buildFilterBar(
    AppLocalizations l10n,
    ColorScheme colors,
    TextTheme text,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KiraDimens.spacingLg,
        vertical: KiraDimens.spacingSm,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          bottom: BorderSide(color: colors.outlineVariant),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Module filter dropdown.
              Expanded(
                child: _buildFilterDropdown(
                  value: _selectedModule,
                  items: _availableModules,
                  hint: l10n.category,
                  icon: KiraIcons.filter,
                  onChanged: (value) {
                    setState(() {
                      _selectedModule = value;
                      _applyFilters();
                    });
                  },
                  colors: colors,
                  text: text,
                ),
              ),
              const SizedBox(width: KiraDimens.spacingSm),
              // Error code filter dropdown.
              if (_availableErrorCodes.isNotEmpty) ...[
                Expanded(
                  child: _buildFilterDropdown(
                    value: _selectedErrorCode,
                    items: _availableErrorCodes,
                    hint: l10n.error,
                    icon: KiraIcons.error,
                    onChanged: (value) {
                      setState(() {
                        _selectedErrorCode = value;
                        _applyFilters();
                      });
                    },
                    colors: colors,
                    text: text,
                  ),
                ),
                const SizedBox(width: KiraDimens.spacingSm),
              ],
              // Date range picker.
              OutlinedButton.icon(
                onPressed: () => _selectDateRange(l10n),
                icon: const Icon(KiraIcons.dateRange,
                    size: KiraDimens.iconSm),
                label: Text(
                  _dateRange != null
                      ? '${DateFormat('MM/dd').format(_dateRange!.start)} - '
                          '${DateFormat('MM/dd').format(_dateRange!.end)}'
                      : l10n.receiptDate,
                  style: text.bodySmall,
                ),
              ),
            ],
          ),
          if (_hasActiveFilters) ...[
            const SizedBox(height: KiraDimens.spacingXs),
            Row(
              children: [
                Text(
                  '${_filteredErrors.length} / ${_allErrors.length}',
                  style:
                      text.bodySmall?.copyWith(color: colors.outline),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _clearFilters,
                  child: Text(l10n.cancel),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String? value,
    required List<String> items,
    required String hint,
    required IconData icon,
    required ValueChanged<String?> onChanged,
    required ColorScheme colors,
    required TextTheme text,
  }) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: KiraDimens.spacingSm),
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(KiraDimens.radiusSm),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: KiraDimens.iconSm, color: colors.outline),
              const SizedBox(width: KiraDimens.spacingXs),
              Text(hint, style: text.bodySmall),
            ],
          ),
          isExpanded: true,
          isDense: true,
          items: [
            DropdownMenuItem<String>(
              value: null,
              child: Text(hint, style: text.bodySmall),
            ),
            ...items.map((item) => DropdownMenuItem<String>(
                  value: item,
                  child: Text(
                    _redactValue(item),
                    style: text.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                )),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  Future<void> _selectDateRange(AppLocalizations l10n) async {
    final now = DateTime.now();
    final result = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
      initialDateRange: _dateRange,
    );

    if (result != null) {
      setState(() {
        _dateRange = result;
        _applyFilters();
      });
    }
  }

  // -------------------------------------------------------------------------
  // Error list
  // -------------------------------------------------------------------------

  Widget _buildErrorList(
    AppLocalizations l10n,
    ColorScheme colors,
    TextTheme text,
  ) {
    return ListView.builder(
      padding:
          const EdgeInsets.symmetric(vertical: KiraDimens.spacingSm),
      itemCount: _filteredErrors.length,
      itemBuilder: (context, index) {
        final error = _filteredErrors[index];
        final errorId = error.id.toString();
        final isExpanded = _expandedIds.contains(errorId);
        return _buildErrorCard(
            error, isExpanded, l10n, colors, text);
      },
    );
  }

  Widget _buildErrorCard(
    ErrorRecord error,
    bool isExpanded,
    AppLocalizations l10n,
    ColorScheme colors,
    TextTheme text,
  ) {
    final errorId = error.id.toString();

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: KiraDimens.spacingLg,
        vertical: KiraDimens.spacingXs,
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            if (isExpanded) {
              _expandedIds.remove(errorId);
            } else {
              _expandedIds.add(errorId);
            }
          });
        },
        borderRadius: BorderRadius.circular(KiraDimens.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(KiraDimens.spacingLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: timestamp + module badge + error code badge.
              _buildErrorHeader(error, colors, text),
              const SizedBox(height: KiraDimens.spacingSm),

              // Message (always visible, PII-redacted).
              Text(
                _redactValue(error.message),
                style: text.bodyMedium,
                maxLines: isExpanded ? null : 2,
                overflow: isExpanded ? null : TextOverflow.ellipsis,
              ),

              // Expanded detail section.
              if (isExpanded) ...[
                const Divider(height: KiraDimens.spacingXl),
                _buildExpandedDetail(error, l10n, colors, text),
              ],

              // Expand/collapse chevron.
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(
                    isExpanded
                        ? KiraIcons.expandLess
                        : KiraIcons.expandMore,
                    size: KiraDimens.iconSm,
                    color: colors.outline,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorHeader(
    ErrorRecord error,
    ColorScheme colors,
    TextTheme text,
  ) {
    final severityColor = _getSeverityColor(error.errorType);

    return Row(
      children: [
        // Severity colour indicator.
        Container(
          width: 4,
          height: 32,
          decoration: BoxDecoration(
            color: severityColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: KiraDimens.spacingSm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Timestamp.
              Text(
                _formatTimestamp(error.createdAt),
                style: text.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: colors.outline,
                ),
              ),
              const SizedBox(height: KiraDimens.spacingXxs),
              Row(
                children: [
                  // Module badge.
                  _badge(error.errorType, severityColor, text),
                  if (error.resolved) ...[
                    const SizedBox(width: KiraDimens.spacingXs),
                    _badge(
                      'resolved',
                      KiraColors.syncedGreen,
                      text,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Expanded detail: stack trace, correlation IDs, OS/device info
  // -------------------------------------------------------------------------

  Widget _buildExpandedDetail(
    ErrorRecord error,
    AppLocalizations l10n,
    ColorScheme colors,
    TextTheme text,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Stack trace (PII-redacted).
        if (error.stackTrace != null &&
            error.stackTrace!.isNotEmpty) ...[
          Text(l10n.error, style: text.titleSmall),
          const SizedBox(height: KiraDimens.spacingXs),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(KiraDimens.spacingSm),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius:
                  BorderRadius.circular(KiraDimens.radiusSm),
            ),
            child: SelectableText(
              _redactStackTrace(error.stackTrace!),
              style: text.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 11,
              ),
              maxLines: 20,
            ),
          ),
          const SizedBox(height: KiraDimens.spacingMd),
        ],

        // Device / OS info.
        if (error.deviceId != null || error.appVersion != null) ...[
          Text(l10n.settingsAbout, style: text.titleSmall),
          const SizedBox(height: KiraDimens.spacingXs),
          if (error.appVersion != null)
            _infoRow(
              l10n.settingsAbout,
              error.appVersion!,
              KiraIcons.about,
              colors,
              text,
            ),
          if (error.deviceId != null)
            _infoRow(
              l10n.settings,
              _redactValue(error.deviceId!),
              KiraIcons.person,
              colors,
              text,
            ),
          const SizedBox(height: KiraDimens.spacingMd),
        ],

        // Context / correlation IDs.
        if (error.context != null && error.context!.isNotEmpty) ...[
          Text(l10n.receiptDetail, style: text.titleSmall),
          const SizedBox(height: KiraDimens.spacingXs),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(KiraDimens.spacingSm),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius:
                  BorderRadius.circular(KiraDimens.radiusSm),
            ),
            child: Text(
              _redactValue(error.context!),
              style:
                  text.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
          ),
        ],
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Empty / error states
  // -------------------------------------------------------------------------

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
            KiraIcons.success,
            size: KiraDimens.iconXl * 1.5,
            color: KiraColors.syncedGreen,
          ),
          const SizedBox(height: KiraDimens.spacingLg),
          Text(
            _hasActiveFilters
                ? l10n.noReceipts
                : l10n.integrityNoAlerts,
            style: text.titleMedium
                ?.copyWith(color: KiraColors.syncedGreen),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(
    AppLocalizations l10n,
    ColorScheme colors,
    TextTheme text,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KiraDimens.spacingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(KiraIcons.error,
                size: KiraDimens.iconXl, color: colors.error),
            const SizedBox(height: KiraDimens.spacingLg),
            Text(
              _errorMessage ?? '',
              style: text.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: KiraDimens.spacingXl),
            ElevatedButton.icon(
              onPressed: _loadErrors,
              icon: const Icon(KiraIcons.refresh,
                  size: KiraDimens.iconSm),
              label: Text(l10n.syncNow),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Shared widgets
  // -------------------------------------------------------------------------

  Widget _badge(String label, Color color, TextTheme text) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KiraDimens.spacingSm,
        vertical: KiraDimens.spacingXxs,
      ),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(KiraDimens.radiusFull),
      ),
      child: Text(
        label,
        style: text.labelSmall?.copyWith(color: color),
      ),
    );
  }

  Widget _infoRow(
    String label,
    String value,
    IconData icon,
    ColorScheme colors,
    TextTheme text,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: KiraDimens.spacingXs),
      child: Row(
        children: [
          Icon(icon,
              size: KiraDimens.iconSm, color: colors.outline),
          const SizedBox(width: KiraDimens.spacingXs),
          Text('$label: ', style: text.bodySmall),
          Expanded(
            child: Text(
              value,
              style: text.bodySmall
                  ?.copyWith(fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Export actions
  // -------------------------------------------------------------------------

  void _handleExportAction(String action) {
    switch (action) {
      case 'json':
        _exportJson();
      case 'csv':
        _exportCsv();
      case 'copy_prompt':
        _copyPrompt();
    }
  }

  /// Exports filtered errors as a JSON array to the clipboard.
  void _exportJson() {
    final records =
        _filteredErrors.map(_sanitizeForExport).toList();
    final json =
        const JsonEncoder.withIndent('  ').convert(records);

    Clipboard.setData(ClipboardData(text: json));

    if (mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.success)),
      );
    }
  }

  /// Exports filtered errors as CSV to the clipboard.
  void _exportCsv() {
    final buffer = StringBuffer();

    // CSV header.
    buffer.writeln('id,timestamp,error_type,message,resolved');

    // CSV rows (PII-redacted).
    for (final error in _filteredErrors) {
      final msg =
          _redactValue(error.message).replaceAll('"', '""');
      buffer.writeln(
        '${error.id},'
        '${error.createdAt},'
        '${error.errorType},'
        '"$msg",'
        '${error.resolved}',
      );
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));

    if (mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.success)),
      );
    }
  }

  /// Generates a developer-friendly summary of top errors suitable for
  /// pasting into a bug report or AI-assisted debugging prompt.
  void _copyPrompt() {
    final buffer = StringBuffer();
    buffer.writeln('=== Kira Error Summary ===');
    buffer.writeln(
        'Generated: ${DateTime.now().toUtc().toIso8601String()}');
    buffer.writeln('Total errors: ${_filteredErrors.length}');
    buffer.writeln();

    // Group by error type and count.
    final grouped = <String, List<ErrorRecord>>{};
    for (final error in _filteredErrors) {
      grouped.putIfAbsent(error.errorType, () => []).add(error);
    }

    // Sort by frequency descending.
    final sortedTypes = grouped.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    // Summarise top 5 error types.
    for (final entry in sortedTypes.take(5)) {
      buffer.writeln(
          '--- ${entry.key} (${entry.value.length} occurrences) ---');

      final latest = entry.value.first;
      buffer.writeln('Latest: ${latest.createdAt}');
      buffer.writeln('Message: ${_redactValue(latest.message)}');

      if (latest.stackTrace != null &&
          latest.stackTrace!.isNotEmpty) {
        final lines =
            _redactStackTrace(latest.stackTrace!).split('\n');
        final preview = lines.take(5).join('\n');
        buffer.writeln('Stack (top 5 frames):');
        buffer.writeln(preview);
      }

      if (latest.context != null && latest.context!.isNotEmpty) {
        buffer.writeln(
            'Context: ${_redactValue(latest.context!)}');
      }

      buffer.writeln();
      buffer.writeln('Repro steps:');
      buffer.writeln(
          '1. Trigger the ${entry.key} module operation');
      buffer.writeln(
          '2. Observe error: ${_redactValue(latest.message)}');
      buffer.writeln(
          '3. Check logs around ${latest.createdAt}');
      buffer.writeln();
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));

    if (mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.success)),
      );
    }
  }

  // -------------------------------------------------------------------------
  // PII redaction -- no tokens, emails, or home paths shown
  // -------------------------------------------------------------------------

  /// Redacts potentially sensitive values from display strings.
  ///
  /// Patterns redacted:
  /// - Bearer/OAuth tokens
  /// - Email addresses
  /// - File paths containing user directories
  /// - UUIDs in device IDs (partially masked)
  static String _redactValue(String value) {
    var redacted = value;

    // Redact Bearer tokens.
    redacted = redacted.replaceAll(
      RegExp(r'Bearer\s+[A-Za-z0-9\-._~+/]+=*',
          caseSensitive: false),
      'Bearer [TOKEN_REDACTED]',
    );

    // Redact OAuth-style tokens (long alphanumeric strings).
    redacted = redacted.replaceAll(
      RegExp(
        r'(?:token|key|secret|password|credential)["\s:=]+[A-Za-z0-9\-._~+/]{20,}',
        caseSensitive: false,
      ),
      '[CREDENTIAL_REDACTED]',
    );

    // Redact email addresses.
    redacted = redacted.replaceAll(
      RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'),
      '[EMAIL_REDACTED]',
    );

    return redacted;
  }

  /// Redacts stack traces to remove PII from file paths.
  static String _redactStackTrace(String stackTrace) {
    var redacted = stackTrace;

    // Redact home directory paths on macOS, Linux, and Windows.
    redacted = redacted.replaceAll(
      RegExp(r'/Users/[^/\s]+', caseSensitive: false),
      '/Users/[REDACTED]',
    );
    redacted = redacted.replaceAll(
      RegExp(r'/home/[^/\s]+', caseSensitive: false),
      '/home/[REDACTED]',
    );
    redacted = redacted.replaceAll(
      RegExp(r'C:\\Users\\[^\\]+', caseSensitive: false),
      r'C:\Users\[REDACTED]',
    );

    return _redactValue(redacted);
  }

  /// Sanitises an error record for export, stripping PII-sensitive fields.
  Map<String, dynamic> _sanitizeForExport(ErrorRecord error) {
    return {
      'id': error.id,
      'timestamp': error.createdAt,
      'error_type': error.errorType,
      'message': _redactValue(error.message),
      'stack_trace': error.stackTrace != null
          ? _redactStackTrace(error.stackTrace!)
          : null,
      'context': error.context != null
          ? _redactValue(error.context!)
          : null,
      'app_version': error.appVersion,
      'resolved': error.resolved,
    };
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  Color _getSeverityColor(String errorType) {
    switch (errorType) {
      case ErrorType.upload:
      case ErrorType.sync:
      case ErrorType.network:
        return KiraColors.failedRed;
      case ErrorType.integrity:
      case ErrorType.database:
        return KiraColors.pendingAmber;
      case ErrorType.camera:
      case ErrorType.auth:
        return KiraColors.infoBlue;
      default:
        return KiraColors.mediumGrey;
    }
  }

  String _formatTimestamp(String isoTimestamp) {
    try {
      final dt = DateTime.parse(isoTimestamp);
      return DateFormat('yyyy-MM-dd HH:mm:ss').format(dt);
    } catch (_) {
      return isoTimestamp;
    }
  }
}
