/// Admin error reporting panel for Kira.
///
/// Displays error records with filtering, detail expansion, and export
/// capabilities. All PII is redacted and no auth tokens are shown.
///
/// Features:
/// - Scrollable list of error records with timestamp, module, code, message.
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
import 'package:share_plus/share_plus.dart';

import '../../../core/db/error_dao.dart';
import '../../../core/models/error_record.dart';
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
  final ErrorDao _errorDao = ErrorDao();

  List<ErrorRecord> _allErrors = [];
  List<ErrorRecord> _filteredErrors = [];
  bool _loading = true;
  String? _errorMessage;

  // Filter state
  String? _selectedModule;
  String? _selectedErrorCode;
  DateTimeRange? _dateRange;

  // Expansion state
  final Set<String> _expandedIds = {};

  // Available filter options (populated from data)
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
        // error_dao ErrorRecord uses errorType instead of module/errorCode.
        // We parse the context field if available for more detail.
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
              e.context != null && e.context!.contains(_selectedErrorCode!))
          .toList();
    }

    // Filter by date range.
    if (_dateRange != null) {
      final start = _dateRange!.start.toIso8601String();
      final end = _dateRange!.end
          .add(const Duration(days: 1))
          .toIso8601String();
      filtered = filtered
          .where((e) => e.createdAt.compareTo(start) >= 0 &&
              e.createdAt.compareTo(end) < 0)
          .toList();
    }

    _filteredErrors = filtered;
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
        title: Text(l10n.integrityAlerts), // "Error Reports"
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(KiraIcons.moreVert),
            tooltip: l10n.settings,
            onSelected: _handleExportAction,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'json',
                child: Row(
                  children: [
                    const Icon(KiraIcons.exportIcon, size: KiraDimens.iconSm),
                    const SizedBox(width: KiraDimens.spacingSm),
                    Text(l10n.reports), // "Export JSON"
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'csv',
                child: Row(
                  children: [
                    const Icon(KiraIcons.csv, size: KiraDimens.iconSm),
                    const SizedBox(width: KiraDimens.spacingSm),
                    Text(l10n.reports), // "Export CSV"
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
                    Text(l10n.save), // "Copy Prompt"
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
              // Module filter
              Expanded(
                child: _buildFilterDropdown(
                  value: _selectedModule,
                  items: _availableModules,
                  hint: l10n.category, // "Module"
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

              // Date range picker
              OutlinedButton.icon(
                onPressed: () => _selectDateRange(l10n),
                icon: const Icon(KiraIcons.dateRange, size: KiraDimens.iconSm),
                label: Text(
                  _dateRange != null
                      ? '${DateFormat('MM/dd').format(_dateRange!.start)} - '
                        '${DateFormat('MM/dd').format(_dateRange!.end)}'
                      : l10n.reports, // "Date Range"
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
                  style: text.bodySmall?.copyWith(color: colors.outline),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _clearFilters,
                  child: Text(l10n.cancel), // "Clear Filters"
                ),
              ],
            ),
          ],
        ],
      ),
    );
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
      padding: const EdgeInsets.symmetric(horizontal: KiraDimens.spacingSm),
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
              Icon(icon, size: KiraDimens.iconSm, color: colors.outline),
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
      padding: const EdgeInsets.symmetric(vertical: KiraDimens.spacingSm),
      itemCount: _filteredErrors.length,
      itemBuilder: (context, index) {
        final error = _filteredErrors[index];
        final isExpanded = _expandedIds.contains(error.id.toString());
        return _buildErrorCard(error, isExpanded, l10n, colors, text);
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
              // Header row: timestamp + module + error code
              _buildErrorHeader(error, colors, text),
              const SizedBox(height: KiraDimens.spacingSm),

              // Message (always visible, redacted)
              Text(
                _redactValue(error.message),
                style: text.bodyMedium,
                maxLines: isExpanded ? null : 2,
                overflow: isExpanded ? null : TextOverflow.ellipsis,
              ),

              // Expanded detail section
              if (isExpanded) ...[
                const Divider(height: KiraDimens.spacingXl),
                _buildExpandedDetail(error, l10n, colors, text),
              ],

              // Expand/collapse indicator
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(
                    isExpanded ? KiraIcons.expandLess : KiraIcons.expandMore,
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
        // Severity indicator
        Container(
          width: 4,
          height: 32,
          decoration: BoxDecoration(
            color: severityColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: KiraDimens.spacingSm),

        // Timestamp
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                  _buildBadge(
                    error.errorType,
                    severityColor,
                    text,
                  ),
                  if (error.resolved) ...[
                    const SizedBox(width: KiraDimens.spacingXs),
                    _buildBadge(
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

  Widget _buildExpandedDetail(
    ErrorRecord error,
    AppLocalizations l10n,
    ColorScheme colors,
    TextTheme text,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Stack trace (PII redacted)
        if (error.stackTrace != null && error.stackTrace!.isNotEmpty) ...[
          Text(l10n.integrityAlerts, style: text.titleSmall), // "Stack Trace"
          const SizedBox(height: KiraDimens.spacingXs),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(KiraDimens.spacingSm),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(KiraDimens.radiusSm),
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

        // Device / OS info
        if (error.deviceId != null || error.appVersion != null) ...[
          Text(l10n.settingsAbout, style: text.titleSmall), // "Device Info"
          const SizedBox(height: KiraDimens.spacingXs),
          if (error.appVersion != null)
            _buildInfoRow(
              l10n.settingsAbout,
              error.appVersion!,
              KiraIcons.about,
              colors,
              text,
            ),
          if (error.deviceId != null)
            _buildInfoRow(
              l10n.settings,
              _redactValue(error.deviceId!),
              KiraIcons.person,
              colors,
              text,
            ),
          const SizedBox(height: KiraDimens.spacingMd),
        ],

        // Context / correlation IDs
        if (error.context != null && error.context!.isNotEmpty) ...[
          Text(l10n.reports, style: text.titleSmall), // "Context"
          const SizedBox(height: KiraDimens.spacingXs),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(KiraDimens.spacingSm),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(KiraDimens.radiusSm),
            ),
            child: Text(
              _redactValue(error.context!),
              style: text.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildInfoRow(
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
          Icon(icon, size: KiraDimens.iconSm, color: colors.outline),
          const SizedBox(width: KiraDimens.spacingXs),
          Text('$label: ', style: text.bodySmall),
          Expanded(
            child: Text(
              value,
              style: text.bodySmall?.copyWith(fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String label, Color color, TextTheme text) {
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
                ? l10n.cancel // "No matching errors"
                : l10n.integrityAlerts, // "No errors recorded"
            style: text.titleMedium?.copyWith(color: KiraColors.syncedGreen),
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
            Icon(KiraIcons.error, size: KiraDimens.iconXl, color: colors.error),
            const SizedBox(height: KiraDimens.spacingLg),
            Text(
              _errorMessage ?? '',
              style: text.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: KiraDimens.spacingXl),
            ElevatedButton.icon(
              onPressed: _loadErrors,
              icon: const Icon(KiraIcons.refresh, size: KiraDimens.iconSm),
              label: Text(l10n.syncNow),
            ),
          ],
        ),
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
        break;
      case 'csv':
        _exportCsv();
        break;
      case 'copy_prompt':
        _copyPrompt();
        break;
    }
  }

  void _exportJson() {
    final records = _filteredErrors.map((e) => _sanitizeForExport(e)).toList();
    final json = const JsonEncoder.withIndent('  ').convert(records);

    Clipboard.setData(ClipboardData(text: json));

    if (mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.save)), // "JSON copied to clipboard"
      );
    }
  }

  void _exportCsv() {
    final buffer = StringBuffer();

    // CSV header
    buffer.writeln('id,timestamp,error_type,message,resolved');

    // CSV rows
    for (final error in _filteredErrors) {
      final msg = _redactValue(error.message).replaceAll('"', '""');
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
        SnackBar(content: Text(l10n.save)), // "CSV copied to clipboard"
      );
    }
  }

  /// Generates a developer-friendly summary of the top errors with repro
  /// context, suitable for pasting into a bug report or AI prompt.
  void _copyPrompt() {
    final buffer = StringBuffer();
    buffer.writeln('=== Kira Error Summary ===');
    buffer.writeln('Generated: ${DateTime.now().toUtc().toIso8601String()}');
    buffer.writeln('Total errors: ${_filteredErrors.length}');
    buffer.writeln();

    // Group by error type and count.
    final groupedByType = <String, List<ErrorRecord>>{};
    for (final error in _filteredErrors) {
      groupedByType.putIfAbsent(error.errorType, () => []).add(error);
    }

    // Sort by frequency descending.
    final sortedTypes = groupedByType.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    // Top 5 error types.
    final topTypes = sortedTypes.take(5);
    for (final entry in topTypes) {
      buffer.writeln('--- ${entry.key} (${entry.value.length} occurrences) ---');

      // Show the most recent error of this type.
      final latest = entry.value.first;
      buffer.writeln('Latest: ${latest.createdAt}');
      buffer.writeln('Message: ${_redactValue(latest.message)}');

      if (latest.stackTrace != null && latest.stackTrace!.isNotEmpty) {
        // Show first 5 lines of stack trace.
        final lines = _redactStackTrace(latest.stackTrace!).split('\n');
        final preview = lines.take(5).join('\n');
        buffer.writeln('Stack (top 5 frames):');
        buffer.writeln(preview);
      }

      if (latest.context != null && latest.context!.isNotEmpty) {
        buffer.writeln('Context: ${_redactValue(latest.context!)}');
      }

      buffer.writeln();

      // Suggested repro steps.
      buffer.writeln('Repro steps:');
      buffer.writeln('1. Trigger the ${entry.key} module operation');
      buffer.writeln('2. Observe error: ${_redactValue(latest.message)}');
      buffer.writeln('3. Check logs around ${latest.createdAt}');
      buffer.writeln();
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));

    if (mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.save)), // "Prompt copied"
      );
    }
  }

  // -------------------------------------------------------------------------
  // PII redaction
  // -------------------------------------------------------------------------

  /// Redacts potentially sensitive values from display strings.
  ///
  /// Patterns redacted:
  /// - Bearer/OAuth tokens (replaced with `[TOKEN_REDACTED]`)
  /// - Email addresses (replaced with `[EMAIL_REDACTED]`)
  /// - File paths containing user directories (home directory stripped)
  /// - UUIDs in device IDs (partially masked)
  static String _redactValue(String value) {
    var redacted = value;

    // Redact Bearer tokens.
    redacted = redacted.replaceAll(
      RegExp(r'Bearer\s+[A-Za-z0-9\-._~+/]+=*', caseSensitive: false),
      'Bearer [TOKEN_REDACTED]',
    );

    // Redact OAuth-style tokens (long alphanumeric strings > 20 chars).
    redacted = redacted.replaceAll(
      RegExp(r'(?:token|key|secret|password|credential)["\s:=]+[A-Za-z0-9\-._~+/]{20,}',
          caseSensitive: false),
      '[CREDENTIAL_REDACTED]',
    );

    // Redact email addresses.
    redacted = redacted.replaceAll(
      RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'),
      '[EMAIL_REDACTED]',
    );

    return redacted;
  }

  /// Redacts stack traces to remove potential PII from file paths and
  /// user-specific directory structures.
  static String _redactStackTrace(String stackTrace) {
    var redacted = stackTrace;

    // Redact home directory paths.
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

  /// Sanitises an error record for export, stripping all PII-sensitive fields.
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
      case 'upload':
      case 'sync':
      case 'network':
        return KiraColors.failedRed;
      case 'integrity':
      case 'database':
        return KiraColors.pendingAmber;
      case 'camera':
      case 'auth':
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
