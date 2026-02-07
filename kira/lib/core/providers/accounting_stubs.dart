/// Roadmap accounting-provider stubs for the Kira app.
///
/// These are placeholder implementations of [AccountingProvider] for
/// integrations that are on the roadmap but not yet built. Each stub
/// implements the full interface and throws [UnimplementedError] with a
/// descriptive message explaining that the integration is planned.
///
/// When an integration is ready for development, move it to its own file
/// (e.g. `xero_provider.dart`) and replace the stub methods with real logic.
///
/// ## CRA / IRS compliance note
///
/// Kira is a **recordkeeping and export tool**. It does not file taxes,
/// calculate tax liability, or provide tax advice. All accounting integrations
/// produce exports suitable for import into the user's accounting or tax
/// software. Users are responsible for verifying accuracy and filing with the
/// appropriate tax authority (CRA, IRS, etc.).
library;

import 'accounting_provider.dart';

// ---------------------------------------------------------------------------
// Xero
// ---------------------------------------------------------------------------

/// Stub for the Xero accounting integration.
///
/// Planned features:
///   - OAuth 2.0 connection to Xero organizations
///   - Push receipts as bank transaction attachments
///   - Pull expense data for reconciliation
///   - Multi-currency support (CAD, USD, and Xero-supported currencies)
class XeroProvider implements AccountingProvider {
  @override
  String get providerName => 'Xero';

  @override
  Future<void> authenticate() {
    throw UnimplementedError(
      'Xero integration is on the roadmap. '
      'See https://kira.app/roadmap for timeline.',
    );
  }

  @override
  Future<bool> isAuthenticated() {
    throw UnimplementedError(
      'Xero integration is on the roadmap.',
    );
  }

  @override
  Future<void> disconnect() {
    throw UnimplementedError(
      'Xero integration is on the roadmap.',
    );
  }

  @override
  Future<void> attachReceiptToExpense(String receiptId, String expenseId) {
    throw UnimplementedError(
      'Xero receipt attachment is on the roadmap.',
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getExpenses({
    DateTime? from,
    DateTime? to,
  }) {
    throw UnimplementedError(
      'Xero expense listing is on the roadmap.',
    );
  }

  @override
  Future<void> createExpense(Map<String, dynamic> expenseData) {
    throw UnimplementedError(
      'Xero expense creation is on the roadmap.',
    );
  }

  @override
  Future<void> syncReceipts(List<String> receiptIds) {
    throw UnimplementedError(
      'Xero receipt sync is on the roadmap.',
    );
  }
}

// ---------------------------------------------------------------------------
// FreshBooks
// ---------------------------------------------------------------------------

/// Stub for the FreshBooks accounting integration.
///
/// Planned features:
///   - OAuth 2.0 connection to FreshBooks accounts
///   - Create expenses from receipts
///   - Attach receipt images to expense entries
///   - Pull expense categories for mapping
class FreshBooksProvider implements AccountingProvider {
  @override
  String get providerName => 'FreshBooks';

  @override
  Future<void> authenticate() {
    throw UnimplementedError(
      'FreshBooks integration is on the roadmap. '
      'See https://kira.app/roadmap for timeline.',
    );
  }

  @override
  Future<bool> isAuthenticated() {
    throw UnimplementedError(
      'FreshBooks integration is on the roadmap.',
    );
  }

  @override
  Future<void> disconnect() {
    throw UnimplementedError(
      'FreshBooks integration is on the roadmap.',
    );
  }

  @override
  Future<void> attachReceiptToExpense(String receiptId, String expenseId) {
    throw UnimplementedError(
      'FreshBooks receipt attachment is on the roadmap.',
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getExpenses({
    DateTime? from,
    DateTime? to,
  }) {
    throw UnimplementedError(
      'FreshBooks expense listing is on the roadmap.',
    );
  }

  @override
  Future<void> createExpense(Map<String, dynamic> expenseData) {
    throw UnimplementedError(
      'FreshBooks expense creation is on the roadmap.',
    );
  }

  @override
  Future<void> syncReceipts(List<String> receiptIds) {
    throw UnimplementedError(
      'FreshBooks receipt sync is on the roadmap.',
    );
  }
}

// ---------------------------------------------------------------------------
// Zoho Books
// ---------------------------------------------------------------------------

/// Stub for the Zoho Books accounting integration.
///
/// Planned features:
///   - OAuth 2.0 connection to Zoho Books organizations
///   - Create expenses from receipt data
///   - Attach receipt images to expense records
///   - Category synchronization between Kira and Zoho Books
class ZohoBooksProvider implements AccountingProvider {
  @override
  String get providerName => 'Zoho Books';

  @override
  Future<void> authenticate() {
    throw UnimplementedError(
      'Zoho Books integration is on the roadmap. '
      'See https://kira.app/roadmap for timeline.',
    );
  }

  @override
  Future<bool> isAuthenticated() {
    throw UnimplementedError(
      'Zoho Books integration is on the roadmap.',
    );
  }

  @override
  Future<void> disconnect() {
    throw UnimplementedError(
      'Zoho Books integration is on the roadmap.',
    );
  }

  @override
  Future<void> attachReceiptToExpense(String receiptId, String expenseId) {
    throw UnimplementedError(
      'Zoho Books receipt attachment is on the roadmap.',
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getExpenses({
    DateTime? from,
    DateTime? to,
  }) {
    throw UnimplementedError(
      'Zoho Books expense listing is on the roadmap.',
    );
  }

  @override
  Future<void> createExpense(Map<String, dynamic> expenseData) {
    throw UnimplementedError(
      'Zoho Books expense creation is on the roadmap.',
    );
  }

  @override
  Future<void> syncReceipts(List<String> receiptIds) {
    throw UnimplementedError(
      'Zoho Books receipt sync is on the roadmap.',
    );
  }
}

// ---------------------------------------------------------------------------
// Sage Accounting
// ---------------------------------------------------------------------------

/// Stub for the Sage Accounting integration.
///
/// Planned features:
///   - OAuth 2.0 connection to Sage Business Cloud Accounting
///   - Push receipt data as purchase invoices or other costs
///   - Attach receipt images to transactions
///   - Support for Canadian and US Sage Accounting editions
class SageAccountingProvider implements AccountingProvider {
  @override
  String get providerName => 'Sage Accounting';

  @override
  Future<void> authenticate() {
    throw UnimplementedError(
      'Sage Accounting integration is on the roadmap. '
      'See https://kira.app/roadmap for timeline.',
    );
  }

  @override
  Future<bool> isAuthenticated() {
    throw UnimplementedError(
      'Sage Accounting integration is on the roadmap.',
    );
  }

  @override
  Future<void> disconnect() {
    throw UnimplementedError(
      'Sage Accounting integration is on the roadmap.',
    );
  }

  @override
  Future<void> attachReceiptToExpense(String receiptId, String expenseId) {
    throw UnimplementedError(
      'Sage Accounting receipt attachment is on the roadmap.',
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getExpenses({
    DateTime? from,
    DateTime? to,
  }) {
    throw UnimplementedError(
      'Sage Accounting expense listing is on the roadmap.',
    );
  }

  @override
  Future<void> createExpense(Map<String, dynamic> expenseData) {
    throw UnimplementedError(
      'Sage Accounting expense creation is on the roadmap.',
    );
  }

  @override
  Future<void> syncReceipts(List<String> receiptIds) {
    throw UnimplementedError(
      'Sage Accounting receipt sync is on the roadmap.',
    );
  }
}
