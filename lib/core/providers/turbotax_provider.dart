/// TurboTax integration for the Kira app.
///
/// Provides two modes of operation:
///
///   1. **TurboTax-ready export** (always available) -- generates a CSV file
///      with categorized totals that the user can manually import into
///      TurboTax. This delegates to [ExportService.exportTurboTaxReady] for
///      the actual file generation.
///
///   2. **Direct TurboTax import** (behind feature flag) -- when partner API
///      access is available, this provider can push data directly into a
///      user's TurboTax account. This path is disabled by default
///      (`TURBOTAX_DIRECT_IMPORT_ENABLED = false`) and requires explicit
///      enablement through a build-time or remote config flag.
///
/// Kira's TurboTax integration maps Kira user categories to standard IRS /
/// CRA tax categories so that the exported data slots directly into TurboTax's
/// expense categorization.
library;

import '../db/database_helper.dart';
import '../security/secure_token_store.dart';
import '../services/export_service.dart';
import '../services/reports_service.dart';
import 'accounting_provider.dart';

// ---------------------------------------------------------------------------
// Feature flag
// ---------------------------------------------------------------------------

/// Master switch for the direct TurboTax import path.
///
/// When `false` (the default), only the CSV-export flow is available. Set to
/// `true` only when Intuit partner API access has been granted and the
/// necessary OAuth credentials are configured.
///
/// This value can be overridden at build time via
/// `--dart-define=TURBOTAX_DIRECT_IMPORT_ENABLED=true`.
const bool kTurboTaxDirectImportEnabled = bool.fromEnvironment(
  'TURBOTAX_DIRECT_IMPORT_ENABLED',
  defaultValue: false,
);

// ---------------------------------------------------------------------------
// Category mapping
// ---------------------------------------------------------------------------

/// Bidirectional mapping between Kira's user-facing categories and TurboTax
/// tax categories.
///
/// This is the canonical mapping used by both the CSV export and the direct
/// import path. Unmapped Kira categories fall through to `"Other Expenses"`.
abstract final class TurboTaxCategories {
  /// Kira category (lowercase) -> TurboTax tax category.
  static const Map<String, String> kiraToTurboTax = {
    // -- Business expense categories --
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

  /// All distinct TurboTax tax categories referenced by this mapping.
  static final Set<String> allTurboTaxCategories =
      kiraToTurboTax.values.toSet();

  /// Maps a Kira category to its TurboTax equivalent.
  static String map(String kiraCategory) =>
      kiraToTurboTax[kiraCategory.toLowerCase()] ?? 'Other Expenses';
}

// ---------------------------------------------------------------------------
// TurboTaxProvider
// ---------------------------------------------------------------------------

/// TurboTax implementation of [AccountingProvider].
///
/// In its default configuration (direct import disabled), most methods
/// delegate to [ExportService] to produce TurboTax-compatible CSV files.
/// When direct import is enabled, the provider authenticates via OAuth and
/// pushes data through the Intuit partner API.
class TurboTaxProvider implements AccountingProvider {
  TurboTaxProvider({
    required SecureTokenStore tokenStore,
    DatabaseHelper? databaseHelper,
    ExportService? exportService,
  })  : _tokenStore = tokenStore,
        _dbHelper = databaseHelper ?? DatabaseHelper(),
        _exportService = exportService ?? ExportService(databaseHelper: databaseHelper);

  final SecureTokenStore _tokenStore;
  final DatabaseHelper _dbHelper;
  final ExportService _exportService;

  /// Token storage namespace for TurboTax credentials.
  static const String _providerKey = 'turbotax';

  @override
  String get providerName => 'TurboTax';

  /// Whether the direct-import feature is available in this build.
  bool get isDirectImportEnabled => kTurboTaxDirectImportEnabled;

  // =========================================================================
  // Authentication
  // =========================================================================

  @override
  Future<void> authenticate() async {
    if (!kTurboTaxDirectImportEnabled) {
      throw const AccountingProviderException(
        providerName: 'TurboTax',
        message: 'Direct TurboTax import is not enabled in this build. '
            'Use exportTurboTaxReady() for CSV export instead.',
      );
    }

    // TODO: Implement Intuit partner OAuth flow when direct import is enabled.
    throw const AccountingProviderException(
      providerName: 'TurboTax',
      message: 'Direct TurboTax authentication is not yet implemented. '
          'Partner API access is required.',
    );
  }

  @override
  Future<bool> isAuthenticated() async {
    if (!kTurboTaxDirectImportEnabled) return false;
    final tokens = await _tokenStore.readTokens(_providerKey);
    return tokens != null && !tokens.isExpired;
  }

  @override
  Future<void> disconnect() async {
    await _tokenStore.deleteTokens(_providerKey);
  }

  // =========================================================================
  // Export-based operations (always available)
  // =========================================================================

  /// Generates a TurboTax-ready CSV export for [taxYear].
  ///
  /// This is the primary integration point -- it produces a CSV file with
  /// receipt data mapped to TurboTax tax categories that the user can
  /// import manually.
  ///
  /// Returns the absolute path to the generated file.
  Future<String> exportTurboTaxReady(
    int taxYear, {
    bool includeImages = false,
  }) async {
    return _exportService.exportTurboTaxReady(
      taxYear,
      includeImages: includeImages,
    );
  }

  /// Returns a categorized summary of expenses for [taxYear], grouped by
  /// TurboTax tax categories.
  ///
  /// Useful for rendering a preview before export.
  Future<Map<String, double>> getCategorizedTotals(int taxYear) async {
    final db = await _dbHelper.database;
    final range = DateRange.year(taxYear);

    final rows = await db.rawQuery(
      'SELECT category, COALESCE(SUM(amount_tracked), 0.0) AS total '
      'FROM receipts '
      "WHERE expired = 0 AND captured_at >= '${range.startIso}' "
      "AND captured_at <= '${range.endIso}' "
      'GROUP BY category ORDER BY total DESC',
    );

    // Map Kira categories to TurboTax categories and aggregate.
    final taxTotals = <String, double>{};
    for (final row in rows) {
      final kiraCategory = row['category'] as String;
      final amount = (row['total'] as num).toDouble();
      final taxCategory = TurboTaxCategories.map(kiraCategory);
      taxTotals[taxCategory] = (taxTotals[taxCategory] ?? 0.0) + amount;
    }

    return taxTotals;
  }

  /// Returns the TurboTax tax category for a given Kira category.
  String mapCategory(String kiraCategory) =>
      TurboTaxCategories.map(kiraCategory);

  // =========================================================================
  // AccountingProvider methods (direct import path)
  // =========================================================================

  @override
  Future<void> attachReceiptToExpense(
    String receiptId,
    String expenseId,
  ) async {
    _requireDirectImport();
    // TODO: Implement when partner API is available.
    throw const AccountingProviderException(
      providerName: 'TurboTax',
      message: 'Direct receipt attachment is not yet implemented.',
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getExpenses({
    DateTime? from,
    DateTime? to,
  }) async {
    _requireDirectImport();
    // TODO: Implement when partner API is available.
    throw const AccountingProviderException(
      providerName: 'TurboTax',
      message: 'Direct expense listing is not yet implemented.',
    );
  }

  @override
  Future<void> createExpense(Map<String, dynamic> expenseData) async {
    _requireDirectImport();
    // TODO: Implement when partner API is available.
    throw const AccountingProviderException(
      providerName: 'TurboTax',
      message: 'Direct expense creation is not yet implemented.',
    );
  }

  @override
  Future<void> syncReceipts(List<String> receiptIds) async {
    _requireDirectImport();
    // TODO: Implement when partner API is available.
    throw const AccountingProviderException(
      providerName: 'TurboTax',
      message: 'Direct receipt sync is not yet implemented.',
    );
  }

  // =========================================================================
  // Internal
  // =========================================================================

  /// Throws if direct import is not enabled in this build.
  void _requireDirectImport() {
    if (!kTurboTaxDirectImportEnabled) {
      throw const AccountingProviderException(
        providerName: 'TurboTax',
        message: 'Direct TurboTax import is not enabled. '
            'Use the CSV export workflow instead.',
      );
    }
  }
}
