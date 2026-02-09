/// Abstract accounting-provider interface for the Kira app.
///
/// Every third-party accounting integration (QuickBooks, Xero, FreshBooks,
/// etc.) implements this contract so that the rest of the app can interact
/// with any provider through a single, uniform API.
///
/// Providers are responsible for their own authentication, token management,
/// and retry logic. The caller should never need to know the specifics of
/// each provider's OAuth flow or REST endpoint.
library;

/// Contract that all accounting-provider integrations must implement.
///
/// Methods that require network access are asynchronous and may throw
/// [AccountingProviderException] on transient or permanent failures.
abstract class AccountingProvider {
  /// Human-readable name of this provider (e.g. `"QuickBooks Online"`).
  String get providerName;

  /// Initiates the OAuth / authentication flow for this provider.
  ///
  /// On success the tokens are persisted via [SecureTokenStore].
  /// Throws [AccountingProviderException] if the user cancels or the
  /// authorization server returns an error.
  Future<void> authenticate();

  /// Returns `true` when valid (non-expired) credentials exist for this
  /// provider. Does **not** make a network call -- only checks the local
  /// token store.
  Future<bool> isAuthenticated();

  /// Revokes the current tokens (if the provider supports revocation) and
  /// deletes all locally stored credentials.
  Future<void> disconnect();

  /// Attaches a Kira receipt (identified by [receiptId]) to an existing
  /// expense or transaction in the provider's system.
  ///
  /// The semantics of "attach" vary by provider -- typically this means
  /// uploading the receipt image as an attachment to the expense identified
  /// by [expenseId].
  Future<void> attachReceiptToExpense(String receiptId, String expenseId);

  /// Fetches a list of expenses from the provider's system.
  ///
  /// When [from] and [to] are supplied the provider should filter server-side
  /// to reduce payload size. The returned maps use provider-specific keys;
  /// the caller is responsible for any mapping.
  Future<List<Map<String, dynamic>>> getExpenses({
    DateTime? from,
    DateTime? to,
  });

  /// Creates a new expense in the provider's system from Kira receipt data.
  ///
  /// [expenseData] should contain at minimum:
  ///   - `amount` (double)
  ///   - `currency` (String, ISO-4217)
  ///   - `date` (String, ISO-8601)
  ///   - `category` (String)
  ///   - `description` (String)
  Future<void> createExpense(Map<String, dynamic> expenseData);

  /// Pushes one or more Kira receipts to the provider in a single batch.
  ///
  /// This is a convenience method -- implementations may call
  /// [createExpense] in a loop or use a provider-specific batch API.
  Future<void> syncReceipts(List<String> receiptIds);
}

// ---------------------------------------------------------------------------
// Shared exception type
// ---------------------------------------------------------------------------

/// Exception thrown by [AccountingProvider] implementations when an operation
/// fails for a reason that should be surfaced to the user.
class AccountingProviderException implements Exception {
  /// The provider that raised the exception (e.g. `"QuickBooks Online"`).
  final String providerName;

  /// A human-readable description of what went wrong.
  final String message;

  /// The underlying error, if any (e.g. an HTTP response or socket error).
  final Object? cause;

  /// HTTP status code, if the failure originated from an API call.
  final int? statusCode;

  const AccountingProviderException({
    required this.providerName,
    required this.message,
    this.cause,
    this.statusCode,
  });

  @override
  String toString() =>
      'AccountingProviderException($providerName): $message'
      '${statusCode != null ? ' [HTTP $statusCode]' : ''}';
}
