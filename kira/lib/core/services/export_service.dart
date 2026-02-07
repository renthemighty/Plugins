/// Export service for the Kira app.
///
/// Generates CSV files, tax packages, TurboTax-ready exports, and business
/// expense reports from the local SQLite database. All exports are written to
/// a platform temp directory and return a file path suitable for sharing via
/// `share_plus` or any other file-sharing mechanism.
///
/// Formatting is locale-aware: dates, currency symbols, and decimal separators
/// adapt to the user's device locale and the currency of the receipts (CAD /
/// USD).
library;

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../db/database_helper.dart';
import '../models/receipt.dart';
import 'reports_service.dart';

// ---------------------------------------------------------------------------
// Export options
// ---------------------------------------------------------------------------

/// Options that control what is included in a CSV export.
class CsvExportOptions {
  /// Whether to append summary rows at the bottom of the CSV.
  final bool includeSummary;

  /// Whether to include receipts flagged as tax-applicable only.
  final bool taxApplicableOnly;

  /// Optional category filter -- when non-null only receipts in these
  /// categories are exported.
  final Set<String>? categories;

  /// Optional region filter.
  final Set<String>? regions;

  const CsvExportOptions({
    this.includeSummary = true,
    this.taxApplicableOnly = false,
    this.categories,
    this.regions,
  });
}

// ---------------------------------------------------------------------------
// ExportService
// ---------------------------------------------------------------------------

/// Generates shareable export files from local receipt data.
class ExportService {
  ExportService({DatabaseHelper? databaseHelper})
      : _dbHelper = databaseHelper ?? DatabaseHelper();

  final DatabaseHelper _dbHelper;

  // =========================================================================
  // Public API
  // =========================================================================

  // -------------------------------------------------------------------------
  // CSV export
  // -------------------------------------------------------------------------

  /// Exports receipt metadata as a CSV file for the given [dateRange].
  ///
  /// Returns the absolute path to the generated `.csv` file in the platform
  /// temp directory.
  Future<String> exportCsv(
    DateRange dateRange, {
    CsvExportOptions options = const CsvExportOptions(),
  }) async {
    final receipts = await _queryReceipts(dateRange, options);
    final csvContent = _buildCsv(receipts, options);

    final dir = await _exportDir();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final filePath = p.join(dir, 'kira_export_$timestamp.csv');
    await File(filePath).writeAsString(csvContent);
    return filePath;
  }

  // -------------------------------------------------------------------------
  // Tax package
  // -------------------------------------------------------------------------

  /// Exports a tax package for [taxYear].
  ///
  /// The package contains:
  ///   - `receipts.csv` -- full receipt metadata
  ///   - `day_index.csv` -- per-day summary
  ///   - `month_index.csv` -- per-month summary
  ///   - Optionally a ZIP archive of receipt images (when [includeImages] is
  ///     `true`). Images are organized in `YYYY/MM/DD/` sub-folders mirroring
  ///     the on-disk storage structure.
  ///
  /// Returns the path to the final file: either a `.zip` (when images are
  /// included) or the directory path containing the CSV files.
  Future<String> exportTaxPackage(
    int taxYear, {
    bool includeImages = false,
  }) async {
    final range = DateRange.year(taxYear);
    final receipts = await _queryReceipts(range, const CsvExportOptions());

    final baseDir = await _exportDir();
    final packageDir = p.join(baseDir, 'kira_tax_$taxYear');
    await Directory(packageDir).create(recursive: true);

    // Main CSV
    final csvContent = _buildCsv(
      receipts,
      const CsvExportOptions(includeSummary: true),
    );
    await File(p.join(packageDir, 'receipts.csv')).writeAsString(csvContent);

    // Day index
    final dayIndex = _buildDayIndex(receipts);
    await File(p.join(packageDir, 'day_index.csv')).writeAsString(dayIndex);

    // Month index
    final monthIndex = _buildMonthIndex(receipts);
    await File(p.join(packageDir, 'month_index.csv'))
        .writeAsString(monthIndex);

    if (!includeImages) {
      return packageDir;
    }

    // Build ZIP with images organized by date folder structure.
    return _buildZipWithImages(packageDir, receipts, 'kira_tax_$taxYear');
  }

  // -------------------------------------------------------------------------
  // TurboTax-ready export
  // -------------------------------------------------------------------------

  /// Exports a TurboTax-compatible CSV for [taxYear].
  ///
  /// The CSV maps Kira categories to TurboTax tax categories and provides
  /// categorized totals suitable for direct import into TurboTax.
  ///
  /// Returns the path to the generated `.csv` file (or `.zip` if
  /// [includeImages] is `true`).
  Future<String> exportTurboTaxReady(
    int taxYear, {
    bool includeImages = false,
  }) async {
    final range = DateRange.year(taxYear);
    final receipts = await _queryReceipts(range, const CsvExportOptions());

    final baseDir = await _exportDir();

    if (!includeImages) {
      final csvContent = _buildTurboTaxCsv(receipts, taxYear);
      final filePath = p.join(baseDir, 'kira_turbotax_$taxYear.csv');
      await File(filePath).writeAsString(csvContent);
      return filePath;
    }

    // Package with images.
    final packageDir = p.join(baseDir, 'kira_turbotax_$taxYear');
    await Directory(packageDir).create(recursive: true);

    final csvContent = _buildTurboTaxCsv(receipts, taxYear);
    await File(p.join(packageDir, 'turbotax_import.csv'))
        .writeAsString(csvContent);

    return _buildZipWithImages(
      packageDir,
      receipts,
      'kira_turbotax_$taxYear',
    );
  }

  // -------------------------------------------------------------------------
  // Business expense report
  // -------------------------------------------------------------------------

  /// Exports a business expense report identified by [reportId].
  ///
  /// Queries the `expense_reports` table for the report metadata and pulls
  /// all associated receipts. Produces a CSV with an appended summary page
  /// plus optional zipped images.
  ///
  /// Returns the path to the export file or directory.
  Future<String> exportExpenseReport(
    String reportId, {
    bool includeImages = false,
  }) async {
    final db = await _dbHelper.database;

    // Fetch the expense report metadata.
    final reportRows = await db.query(
      'expense_reports',
      where: 'report_id = ?',
      whereArgs: [reportId],
    );
    if (reportRows.isEmpty) {
      throw ExportException('Expense report not found: $reportId');
    }
    final report = reportRows.first;
    final title = (report['title'] as String?) ?? 'expense_report';
    final safeName = title.replaceAll(RegExp(r'[^\w\-]'), '_').toLowerCase();

    // Fetch receipts linked to this report.  The link is modeled as
    // receipts whose capture_session_id matches the report_id (convention
    // from the business-mode capture flow).
    final receipts = await _queryReceiptsByReportId(db, reportId);

    final baseDir = await _exportDir();
    final packageDir = p.join(baseDir, 'kira_report_$safeName');
    await Directory(packageDir).create(recursive: true);

    // Receipts CSV
    final csvContent = _buildCsv(
      receipts,
      const CsvExportOptions(includeSummary: true),
    );
    await File(p.join(packageDir, 'receipts.csv')).writeAsString(csvContent);

    // Day index
    final dayIndex = _buildDayIndex(receipts);
    await File(p.join(packageDir, 'day_index.csv')).writeAsString(dayIndex);

    // Month index
    final monthIndex = _buildMonthIndex(receipts);
    await File(p.join(packageDir, 'month_index.csv'))
        .writeAsString(monthIndex);

    // Summary page
    final summary = _buildExpenseReportSummary(report, receipts);
    await File(p.join(packageDir, 'summary.csv')).writeAsString(summary);

    if (!includeImages) {
      return packageDir;
    }

    return _buildZipWithImages(packageDir, receipts, 'kira_report_$safeName');
  }

  // =========================================================================
  // CSV builders
  // =========================================================================

  /// Builds the standard receipt CSV content with an optional summary footer.
  String _buildCsv(List<Receipt> receipts, CsvExportOptions options) {
    final buf = StringBuffer();

    // Header
    buf.writeln(
      'date,filename,amount,currency,category,region,notes,'
      'tax_applicable,checksum',
    );

    // Data rows
    double totalAmount = 0;
    final categoryTotals = <String, double>{};
    final regionTotals = <String, double>{};

    for (final r in receipts) {
      final date = r.capturedAt.substring(0, 10);
      final notes = _csvEscape(r.notes ?? '');
      final taxFlag = r.taxApplicable == null
          ? ''
          : (r.taxApplicable! ? 'yes' : 'no');

      buf.writeln(
        '$date,${_csvEscape(r.filename)},'
        '${_formatAmount(r.amountTracked, r.currencyCode)},'
        '${r.currencyCode},${_csvEscape(r.category)},'
        '${_csvEscape(r.region)},$notes,$taxFlag,'
        '${r.checksumSha256}',
      );

      totalAmount += r.amountTracked;
      categoryTotals[r.category] =
          (categoryTotals[r.category] ?? 0) + r.amountTracked;
      regionTotals[r.region] =
          (regionTotals[r.region] ?? 0) + r.amountTracked;
    }

    if (options.includeSummary) {
      buf.writeln();
      buf.writeln('# Summary');
      buf.writeln('Total Receipts,${receipts.length}');

      final dominantCurrency =
          receipts.isNotEmpty ? receipts.first.currencyCode : 'CAD';
      buf.writeln(
        'Total Amount,${_formatAmount(totalAmount, dominantCurrency)} '
        '$dominantCurrency',
      );

      buf.writeln();
      buf.writeln('# By Category');
      for (final entry in categoryTotals.entries) {
        buf.writeln(
          '${_csvEscape(entry.key)},'
          '${_formatAmount(entry.value, dominantCurrency)}',
        );
      }

      buf.writeln();
      buf.writeln('# By Region');
      for (final entry in regionTotals.entries) {
        buf.writeln(
          '${_csvEscape(entry.key)},'
          '${_formatAmount(entry.value, dominantCurrency)}',
        );
      }
    }

    return buf.toString();
  }

  /// Builds a per-day summary CSV.
  String _buildDayIndex(List<Receipt> receipts) {
    final buf = StringBuffer();
    buf.writeln('date,receipt_count,total_amount,currency');

    // Group by date.
    final byDay = <String, List<Receipt>>{};
    for (final r in receipts) {
      final date = r.capturedAt.substring(0, 10);
      byDay.putIfAbsent(date, () => []).add(r);
    }

    final sortedDays = byDay.keys.toList()..sort();
    for (final day in sortedDays) {
      final dayReceipts = byDay[day]!;
      final total =
          dayReceipts.fold<double>(0, (sum, r) => sum + r.amountTracked);
      final currency = dayReceipts.first.currencyCode;
      buf.writeln(
        '$day,${dayReceipts.length},'
        '${_formatAmount(total, currency)},$currency',
      );
    }

    return buf.toString();
  }

  /// Builds a per-month summary CSV.
  String _buildMonthIndex(List<Receipt> receipts) {
    final buf = StringBuffer();
    buf.writeln('month,receipt_count,total_amount,currency');

    // Group by YYYY-MM.
    final byMonth = <String, List<Receipt>>{};
    for (final r in receipts) {
      final month = r.capturedAt.substring(0, 7);
      byMonth.putIfAbsent(month, () => []).add(r);
    }

    final sortedMonths = byMonth.keys.toList()..sort();
    for (final month in sortedMonths) {
      final monthReceipts = byMonth[month]!;
      final total =
          monthReceipts.fold<double>(0, (sum, r) => sum + r.amountTracked);
      final currency = monthReceipts.first.currencyCode;
      buf.writeln(
        '$month,${monthReceipts.length},'
        '${_formatAmount(total, currency)},$currency',
      );
    }

    return buf.toString();
  }

  /// Builds a TurboTax-compatible CSV with category mapping.
  String _buildTurboTaxCsv(List<Receipt> receipts, int taxYear) {
    final buf = StringBuffer();

    // Header matching TurboTax generic CSV import format.
    buf.writeln(
      'Date,Description,Amount,Category,Tax Category,Currency',
    );

    final taxCategoryTotals = <String, double>{};

    for (final r in receipts) {
      final date = _formatDateForLocale(r.capturedAt.substring(0, 10));
      final description = _csvEscape(
        '${r.category} - ${r.region}'
        '${r.notes != null && r.notes!.isNotEmpty ? " - ${r.notes}" : ""}',
      );
      final taxCategory = _mapToTurboTaxCategory(r.category);
      buf.writeln(
        '$date,$description,'
        '${_formatAmount(r.amountTracked, r.currencyCode)},'
        '${_csvEscape(r.category)},$taxCategory,${r.currencyCode}',
      );

      taxCategoryTotals[taxCategory] =
          (taxCategoryTotals[taxCategory] ?? 0) + r.amountTracked;
    }

    // Categorized totals summary.
    final dominantCurrency =
        receipts.isNotEmpty ? receipts.first.currencyCode : 'CAD';
    buf.writeln();
    buf.writeln('# Tax Category Totals for $taxYear');
    buf.writeln('Tax Category,Total Amount,Currency');
    for (final entry in taxCategoryTotals.entries) {
      buf.writeln(
        '${entry.key},'
        '${_formatAmount(entry.value, dominantCurrency)},$dominantCurrency',
      );
    }

    final grandTotal =
        receipts.fold<double>(0, (sum, r) => sum + r.amountTracked);
    buf.writeln();
    buf.writeln(
      'Grand Total,${_formatAmount(grandTotal, dominantCurrency)},'
      '$dominantCurrency',
    );
    buf.writeln('Total Receipts,${receipts.length}');

    return buf.toString();
  }

  /// Builds the summary page for a business expense report.
  String _buildExpenseReportSummary(
    Map<String, dynamic> report,
    List<Receipt> receipts,
  ) {
    final buf = StringBuffer();

    buf.writeln('Expense Report Summary');
    buf.writeln();
    buf.writeln('Report Title,${_csvEscape(report['title'] as String? ?? '')}');
    buf.writeln('Report ID,${report['report_id']}');
    buf.writeln('Status,${report['status'] ?? 'draft'}');
    buf.writeln(
      'Currency,${report['currency_code'] ?? 'CAD'}',
    );

    final totalAmount =
        receipts.fold<double>(0, (sum, r) => sum + r.amountTracked);
    final currency =
        receipts.isNotEmpty ? receipts.first.currencyCode : 'CAD';
    buf.writeln(
      'Total Amount,${_formatAmount(totalAmount, currency)} $currency',
    );
    buf.writeln('Total Receipts,${receipts.length}');

    if (report['submitted_at'] != null) {
      buf.writeln('Submitted At,${report['submitted_at']}');
    }
    if (report['approved_at'] != null) {
      buf.writeln('Approved At,${report['approved_at']}');
    }
    if (report['notes'] != null) {
      buf.writeln('Notes,${_csvEscape(report['notes'] as String)}');
    }

    // Category breakdown.
    buf.writeln();
    buf.writeln('Category Breakdown');
    buf.writeln('Category,Amount,Count');
    final categoryTotals = <String, double>{};
    final categoryCounts = <String, int>{};
    for (final r in receipts) {
      categoryTotals[r.category] =
          (categoryTotals[r.category] ?? 0) + r.amountTracked;
      categoryCounts[r.category] = (categoryCounts[r.category] ?? 0) + 1;
    }
    for (final cat in categoryTotals.keys) {
      buf.writeln(
        '${_csvEscape(cat)},'
        '${_formatAmount(categoryTotals[cat]!, currency)},'
        '${categoryCounts[cat]}',
      );
    }

    // Region breakdown.
    buf.writeln();
    buf.writeln('Region Breakdown');
    buf.writeln('Region,Amount,Count');
    final regionTotals = <String, double>{};
    final regionCounts = <String, int>{};
    for (final r in receipts) {
      regionTotals[r.region] =
          (regionTotals[r.region] ?? 0) + r.amountTracked;
      regionCounts[r.region] = (regionCounts[r.region] ?? 0) + 1;
    }
    for (final reg in regionTotals.keys) {
      buf.writeln(
        '${_csvEscape(reg)},'
        '${_formatAmount(regionTotals[reg]!, currency)},'
        '${regionCounts[reg]}',
      );
    }

    return buf.toString();
  }

  // =========================================================================
  // ZIP builder
  // =========================================================================

  /// Creates a ZIP archive containing the files in [packageDir] plus receipt
  /// images organized into date-based sub-folders.
  ///
  /// Returns the path to the generated `.zip` file.
  Future<String> _buildZipWithImages(
    String packageDir,
    List<Receipt> receipts,
    String archiveName,
  ) async {
    final archive = Archive();

    // Add CSV files already written to packageDir.
    final packageDirEntity = Directory(packageDir);
    await for (final entity in packageDirEntity.list()) {
      if (entity is File) {
        final bytes = await entity.readAsBytes();
        final name = p.basename(entity.path);
        archive.addFile(
          ArchiveFile(
            '$archiveName/$name',
            bytes.length,
            bytes,
          ),
        );
      }
    }

    // Add receipt images, organized by YYYY/MM/DD/.
    for (final r in receipts) {
      if (r.toMap()['local_path'] == null) continue;
      final localPath = r.toMap()['local_path'] as String;
      final imageFile = File(localPath);
      if (!await imageFile.exists()) continue;

      final date = r.capturedAt.substring(0, 10); // YYYY-MM-DD
      final parts = date.split('-');
      final folderPath = '${parts[0]}/${parts[1]}/${parts[2]}';
      final bytes = await imageFile.readAsBytes();
      archive.addFile(
        ArchiveFile(
          '$archiveName/images/$folderPath/${r.filename}',
          bytes.length,
          bytes,
        ),
      );
    }

    final zipData = ZipEncoder().encode(archive);
    if (zipData == null) {
      throw ExportException('Failed to encode ZIP archive');
    }

    final parentDir = p.dirname(packageDir);
    final zipPath = p.join(parentDir, '$archiveName.zip');
    await File(zipPath).writeAsBytes(zipData);

    // Clean up the temporary unzipped directory.
    await packageDirEntity.delete(recursive: true);

    return zipPath;
  }

  // =========================================================================
  // Database queries
  // =========================================================================

  Future<List<Receipt>> _queryReceipts(
    DateRange range,
    CsvExportOptions options,
  ) async {
    final db = await _dbHelper.database;

    final whereClauses = <String>[
      'expired = 0',
      "captured_at >= '${range.startIso}'",
      "captured_at <= '${range.endIso}'",
    ];

    if (options.taxApplicableOnly) {
      whereClauses.add('tax_applicable = 1');
    }

    if (options.categories != null && options.categories!.isNotEmpty) {
      final cats =
          options.categories!.map((c) => "'${_sqlEscape(c)}'").join(',');
      whereClauses.add('category IN ($cats)');
    }

    if (options.regions != null && options.regions!.isNotEmpty) {
      final regs =
          options.regions!.map((r) => "'${_sqlEscape(r)}'").join(',');
      whereClauses.add('region IN ($regs)');
    }

    final where = whereClauses.join(' AND ');
    final rows = await db.query(
      'receipts',
      where: where,
      orderBy: 'captured_at ASC',
    );

    return rows.map(Receipt.fromMap).toList();
  }

  Future<List<Receipt>> _queryReceiptsByReportId(
    Database db,
    String reportId,
  ) async {
    // Convention: receipts linked to an expense report use
    // capture_session_id = report_id.
    final rows = await db.query(
      'receipts',
      where: 'expired = 0 AND capture_session_id = ?',
      whereArgs: [reportId],
      orderBy: 'captured_at ASC',
    );
    return rows.map(Receipt.fromMap).toList();
  }

  // =========================================================================
  // Formatting helpers
  // =========================================================================

  /// Formats a monetary amount with two decimal places.
  ///
  /// Uses locale-aware formatting for CAD and USD: comma thousands separator,
  /// dot decimal separator for `en_CA` / `en_US`.
  String _formatAmount(double amount, String currencyCode) {
    final locale = currencyCode == 'USD' ? 'en_US' : 'en_CA';
    final formatter = NumberFormat('#,##0.00', locale);
    return formatter.format(amount);
  }

  /// Formats a date string (`YYYY-MM-DD`) for locale-appropriate display.
  String _formatDateForLocale(String isoDate) {
    // TurboTax expects MM/DD/YYYY for US locale.
    final parts = isoDate.split('-');
    if (parts.length == 3) {
      return '${parts[1]}/${parts[2]}/${parts[0]}';
    }
    return isoDate;
  }

  /// Escapes a value for inclusion in a CSV cell.
  ///
  /// Wraps the value in double quotes if it contains commas, quotes, or
  /// newlines. Internal double quotes are doubled as per RFC 4180.
  String _csvEscape(String value) {
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  /// Basic SQL string escaping -- replaces single quotes with doubled quotes.
  String _sqlEscape(String value) => value.replaceAll("'", "''");

  /// Returns the path to a temporary export directory, creating it if needed.
  Future<String> _exportDir() async {
    final tempDir = await getTemporaryDirectory();
    final exportDir = p.join(tempDir.path, 'kira_exports');
    await Directory(exportDir).create(recursive: true);
    return exportDir;
  }

  // =========================================================================
  // TurboTax category mapping
  // =========================================================================

  /// Maps Kira user categories to TurboTax-recognized tax categories.
  ///
  /// Unmapped categories default to `"Other Expenses"`.
  static String _mapToTurboTaxCategory(String kiraCategory) {
    return _turboTaxCategoryMap[kiraCategory.toLowerCase()] ??
        'Other Expenses';
  }

  static const Map<String, String> _turboTaxCategoryMap = {
    // Business expenses
    'meals': 'Meals and Entertainment',
    'meals & entertainment': 'Meals and Entertainment',
    'dining': 'Meals and Entertainment',
    'transport': 'Car and Truck Expenses',
    'transportation': 'Car and Truck Expenses',
    'gas': 'Car and Truck Expenses',
    'fuel': 'Car and Truck Expenses',
    'parking': 'Car and Truck Expenses',
    'taxi': 'Car and Truck Expenses',
    'rideshare': 'Car and Truck Expenses',
    'office': 'Office Expenses',
    'office supplies': 'Office Expenses',
    'supplies': 'Supplies',
    'travel': 'Travel',
    'hotel': 'Travel',
    'lodging': 'Travel',
    'airfare': 'Travel',
    'flights': 'Travel',
    'phone': 'Utilities',
    'internet': 'Utilities',
    'utilities': 'Utilities',
    'rent': 'Rent or Lease',
    'insurance': 'Insurance',
    'medical': 'Medical and Dental',
    'health': 'Medical and Dental',
    'pharmacy': 'Medical and Dental',
    'education': 'Education',
    'training': 'Education',
    'software': 'Other Expenses',
    'subscriptions': 'Other Expenses',
    'equipment': 'Equipment',
    'hardware': 'Equipment',
    'advertising': 'Advertising',
    'marketing': 'Advertising',
    'legal': 'Legal and Professional Services',
    'accounting': 'Legal and Professional Services',
    'professional services': 'Legal and Professional Services',
    'repairs': 'Repairs and Maintenance',
    'maintenance': 'Repairs and Maintenance',
    'clothing': 'Other Expenses',
    'gifts': 'Gifts',
    'donations': 'Charitable Contributions',
    'charity': 'Charitable Contributions',
    'groceries': 'Other Expenses',
    'personal': 'Other Expenses',
    'miscellaneous': 'Other Expenses',
    'other': 'Other Expenses',
  };
}

// ---------------------------------------------------------------------------
// Exception
// ---------------------------------------------------------------------------

/// Exception thrown when an export operation fails.
class ExportException implements Exception {
  final String message;
  const ExportException(this.message);

  @override
  String toString() => 'ExportException: $message';
}
