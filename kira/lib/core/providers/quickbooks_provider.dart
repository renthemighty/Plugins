/// QuickBooks Online integration for the Kira app.
///
/// Implements [AccountingProvider] to connect Kira with a user's QuickBooks
/// Online company. Uses OAuth 2.0 with PKCE for secure authorization and
/// requests only the least-privilege scopes required for expense management.
///
/// Tokens are stored in [SecureTokenStore] and refreshed automatically when
/// they expire. All API calls include retry-with-exponential-backoff logic
/// for transient failures.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:http/http.dart' as http;

import '../db/database_helper.dart';
import '../models/receipt.dart';
import '../security/secure_token_store.dart';
import 'accounting_provider.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// OAuth / API configuration for QuickBooks Online.
///
/// In production these values should come from a build-time config or
/// remote config service, never hard-coded secrets.
abstract final class _QboConfig {
  /// OAuth 2.0 client identifier (public -- not a secret for PKCE flows).
  static const String clientId = String.fromEnvironment(
    'QBO_CLIENT_ID',
    defaultValue: '',
  );

  /// Redirect URI registered with the Intuit developer portal.
  static const String redirectUri = 'com.kira.app://oauth/quickbooks';

  /// Intuit OAuth 2.0 endpoints.
  static const String authorizationEndpoint =
      'https://appcenter.intuit.com/connect/oauth2';
  static const String tokenEndpoint =
      'https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer';
  static const String revocationEndpoint =
      'https://developer.api.intuit.com/v2/oauth2/tokens/revoke';

  /// QuickBooks Online API base URL (production).
  static const String apiBaseUrl =
      'https://quickbooks.api.intuit.com/v3/company';

  /// Least-privilege scopes: only what we need for expense management.
  static const List<String> scopes = [
    'com.intuit.quickbooks.accounting',
  ];

  /// Provider key used for token storage namespacing.
  static const String providerKey = 'quickbooks';

  /// Maximum number of retry attempts for transient API failures.
  static const int maxRetries = 3;

  /// Base delay for exponential backoff (doubles each attempt).
  static const Duration baseRetryDelay = Duration(seconds: 1);
}

// ---------------------------------------------------------------------------
// QuickBooksProvider
// ---------------------------------------------------------------------------

/// QuickBooks Online implementation of [AccountingProvider].
///
/// Usage:
/// ```dart
/// final qb = QuickBooksProvider(tokenStore: myTokenStore);
/// await qb.authenticate();
/// final expenses = await qb.getExpenses(from: startDate, to: endDate);
/// ```
class QuickBooksProvider implements AccountingProvider {
  QuickBooksProvider({
    required SecureTokenStore tokenStore,
    DatabaseHelper? databaseHelper,
    FlutterAppAuth? appAuth,
    http.Client? httpClient,
  })  : _tokenStore = tokenStore,
        _dbHelper = databaseHelper ?? DatabaseHelper(),
        _appAuth = appAuth ?? const FlutterAppAuth(),
        _httpClient = httpClient ?? http.Client();

  final SecureTokenStore _tokenStore;
  final DatabaseHelper _dbHelper;
  final FlutterAppAuth _appAuth;
  final http.Client _httpClient;

  /// The QuickBooks company (realm) ID, populated after authentication.
  String? _realmId;

  @override
  String get providerName => 'QuickBooks Online';

  // =========================================================================
  // Authentication
  // =========================================================================

  @override
  Future<void> authenticate() async {
    if (_QboConfig.clientId.isEmpty) {
      throw const AccountingProviderException(
        providerName: 'QuickBooks Online',
        message: 'QuickBooks client ID is not configured. '
            'Set QBO_CLIENT_ID at build time.',
      );
    }

    try {
      final result = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          _QboConfig.clientId,
          _QboConfig.redirectUri,
          serviceConfiguration: const AuthorizationServiceConfiguration(
            authorizationEndpoint: _QboConfig.authorizationEndpoint,
            tokenEndpoint: _QboConfig.tokenEndpoint,
          ),
          scopes: _QboConfig.scopes,
          preferEphemeralSession: true,
        ),
      );

      if (result == null || result.accessToken == null) {
        throw const AccountingProviderException(
          providerName: 'QuickBooks Online',
          message: 'Authorization was cancelled or returned no tokens.',
        );
      }

      // Extract the realm ID from the authorization response.
      // QuickBooks returns it as a query parameter on the redirect URI.
      _realmId = result.tokenAdditionalParameters?['realmId'];

      // Persist the realm ID alongside the tokens.
      if (_realmId != null) {
        await _tokenStore.saveCodeVerifier(
          '${_QboConfig.providerKey}_realm',
          _realmId!,
        );
      }

      await _tokenStore.saveTokens(
        _QboConfig.providerKey,
        OAuthTokens(
          accessToken: result.accessToken!,
          refreshToken: result.refreshToken,
          idToken: result.idToken,
          expiresAt: result.accessTokenExpirationDateTime?.toUtc(),
        ),
      );
    } on AccountingProviderException {
      rethrow;
    } catch (e) {
      throw AccountingProviderException(
        providerName: 'QuickBooks Online',
        message: 'Authentication failed: $e',
        cause: e,
      );
    }
  }

  @override
  Future<bool> isAuthenticated() async {
    final tokens = await _tokenStore.readTokens(_QboConfig.providerKey);
    return tokens != null && !tokens.isExpired;
  }

  @override
  Future<void> disconnect() async {
    // Attempt to revoke the token server-side (best-effort).
    try {
      final tokens = await _tokenStore.readTokens(_QboConfig.providerKey);
      if (tokens != null) {
        final tokenToRevoke = tokens.refreshToken ?? tokens.accessToken;
        await _httpClient.post(
          Uri.parse(_QboConfig.revocationEndpoint),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'token': tokenToRevoke}),
        );
      }
    } catch (_) {
      // Revocation failure is non-fatal -- we still clean up locally.
    }

    await _tokenStore.deleteTokens(_QboConfig.providerKey);
    _realmId = null;
  }

  // =========================================================================
  // Expense operations
  // =========================================================================

  @override
  Future<void> attachReceiptToExpense(
    String receiptId,
    String expenseId,
  ) async {
    final realmId = await _ensureRealmId();
    final receipt = await _loadReceipt(receiptId);
    final localPath = receipt.toMap()['local_path'] as String?;

    if (localPath == null || !await File(localPath).exists()) {
      throw AccountingProviderException(
        providerName: providerName,
        message: 'Receipt image not found locally for $receiptId.',
      );
    }

    // Upload the receipt image as an attachable linked to the purchase.
    final imageBytes = await File(localPath).readAsBytes();
    final fileName = receipt.filename;

    final uri = Uri.parse(
      '${_QboConfig.apiBaseUrl}/$realmId/upload?'
      'minorversion=65',
    );

    await _authenticatedMultipartRequest(
      uri: uri,
      fileName: fileName,
      fileBytes: imageBytes,
      entityRef: expenseId,
      entityType: 'Purchase',
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getExpenses({
    DateTime? from,
    DateTime? to,
  }) async {
    final realmId = await _ensureRealmId();

    // Build a QuickBooks query.
    final queryParts = <String>["SELECT * FROM Purchase"];
    final whereClauses = <String>[];

    if (from != null) {
      final fromStr = _isoDate(from);
      whereClauses.add("TxnDate >= '$fromStr'");
    }
    if (to != null) {
      final toStr = _isoDate(to);
      whereClauses.add("TxnDate <= '$toStr'");
    }

    if (whereClauses.isNotEmpty) {
      queryParts.add('WHERE ${whereClauses.join(' AND ')}');
    }
    queryParts.add('ORDERBY TxnDate DESC');
    queryParts.add('MAXRESULTS 1000');

    final query = queryParts.join(' ');
    final uri = Uri.parse(
      '${_QboConfig.apiBaseUrl}/$realmId/query?'
      'query=${Uri.encodeComponent(query)}&minorversion=65',
    );

    final response = await _authenticatedGet(uri);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final queryResponse =
        body['QueryResponse'] as Map<String, dynamic>? ?? {};
    final purchases =
        queryResponse['Purchase'] as List<dynamic>? ?? <dynamic>[];

    return purchases.cast<Map<String, dynamic>>();
  }

  @override
  Future<void> createExpense(Map<String, dynamic> expenseData) async {
    final realmId = await _ensureRealmId();

    // Build a QuickBooks Purchase object.
    final purchase = <String, dynamic>{
      'PaymentType': 'Cash',
      'TotalAmt': expenseData['amount'] ?? 0.0,
      'CurrencyRef': {
        'value': expenseData['currency'] ?? 'CAD',
      },
      'TxnDate': expenseData['date'] ?? _isoDate(DateTime.now()),
      'PrivateNote': expenseData['description'] ?? '',
      'Line': [
        {
          'DetailType': 'AccountBasedExpenseLineDetail',
          'Amount': expenseData['amount'] ?? 0.0,
          'Description':
              expenseData['category'] ?? expenseData['description'] ?? '',
          'AccountBasedExpenseLineDetail': {
            'AccountRef': {
              // The actual account ref should be looked up from QBO chart of
              // accounts. For now we use the description as a placeholder.
              'name': expenseData['category'] ?? 'Expenses',
            },
          },
        },
      ],
    };

    final uri = Uri.parse(
      '${_QboConfig.apiBaseUrl}/$realmId/purchase?minorversion=65',
    );

    await _authenticatedPost(uri, purchase);
  }

  @override
  Future<void> syncReceipts(List<String> receiptIds) async {
    for (final receiptId in receiptIds) {
      final receipt = await _loadReceipt(receiptId);
      await createExpense({
        'amount': receipt.amountTracked,
        'currency': receipt.currencyCode,
        'date': receipt.capturedAt.substring(0, 10),
        'category': receipt.category,
        'description': '${receipt.category} - ${receipt.region}'
            '${receipt.notes != null ? " - ${receipt.notes}" : ""}',
      });
    }
  }

  // =========================================================================
  // HTTP helpers with retry + token refresh
  // =========================================================================

  Future<http.Response> _authenticatedGet(Uri uri) async {
    return _withRetry(() async {
      final accessToken = await _getValidAccessToken();
      final response = await _httpClient.get(
        uri,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/json',
        },
      );
      _checkResponse(response);
      return response;
    });
  }

  Future<http.Response> _authenticatedPost(
    Uri uri,
    Map<String, dynamic> body,
  ) async {
    return _withRetry(() async {
      final accessToken = await _getValidAccessToken();
      final response = await _httpClient.post(
        uri,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(body),
      );
      _checkResponse(response);
      return response;
    });
  }

  Future<http.Response> _authenticatedMultipartRequest({
    required Uri uri,
    required String fileName,
    required List<int> fileBytes,
    required String entityRef,
    required String entityType,
  }) async {
    return _withRetry(() async {
      final accessToken = await _getValidAccessToken();

      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $accessToken';
      request.headers['Accept'] = 'application/json';

      // Metadata part.
      final metadata = jsonEncode({
        'AttachableRef': [
          {
            'EntityRef': {'type': entityType, 'value': entityRef},
          },
        ],
        'FileName': fileName,
        'ContentType': 'image/jpeg',
      });
      request.fields['file_metadata_01'] = metadata;

      // File part.
      request.files.add(
        http.MultipartFile.fromBytes(
          'file_content_01',
          fileBytes,
          filename: fileName,
        ),
      );

      final streamedResponse = await _httpClient.send(request);
      final response = await http.Response.fromStream(streamedResponse);
      _checkResponse(response);
      return response;
    });
  }

  // -------------------------------------------------------------------------
  // Token management
  // -------------------------------------------------------------------------

  /// Returns a valid access token, refreshing if expired.
  Future<String> _getValidAccessToken() async {
    final tokens = await _tokenStore.readTokens(_QboConfig.providerKey);

    if (tokens == null) {
      throw const AccountingProviderException(
        providerName: 'QuickBooks Online',
        message: 'Not authenticated. Please connect QuickBooks first.',
      );
    }

    if (!tokens.isExpired) {
      return tokens.accessToken;
    }

    // Token is expired -- attempt refresh.
    if (tokens.refreshToken == null) {
      throw const AccountingProviderException(
        providerName: 'QuickBooks Online',
        message: 'Session expired and no refresh token is available. '
            'Please reconnect QuickBooks.',
      );
    }

    try {
      final result = await _appAuth.token(
        TokenRequest(
          _QboConfig.clientId,
          _QboConfig.redirectUri,
          serviceConfiguration: const AuthorizationServiceConfiguration(
            authorizationEndpoint: _QboConfig.authorizationEndpoint,
            tokenEndpoint: _QboConfig.tokenEndpoint,
          ),
          refreshToken: tokens.refreshToken,
          scopes: _QboConfig.scopes,
        ),
      );

      if (result == null || result.accessToken == null) {
        throw const AccountingProviderException(
          providerName: 'QuickBooks Online',
          message: 'Token refresh returned no credentials.',
        );
      }

      final newTokens = OAuthTokens(
        accessToken: result.accessToken!,
        refreshToken: result.refreshToken ?? tokens.refreshToken,
        idToken: result.idToken,
        expiresAt: result.accessTokenExpirationDateTime?.toUtc(),
      );
      await _tokenStore.saveTokens(_QboConfig.providerKey, newTokens);

      return newTokens.accessToken;
    } catch (e) {
      throw AccountingProviderException(
        providerName: 'QuickBooks Online',
        message: 'Token refresh failed: $e',
        cause: e,
      );
    }
  }

  // -------------------------------------------------------------------------
  // Retry logic
  // -------------------------------------------------------------------------

  /// Wraps an API call with exponential-backoff retry for transient failures.
  Future<T> _withRetry<T>(Future<T> Function() action) async {
    int attempt = 0;
    while (true) {
      try {
        return await action();
      } on AccountingProviderException catch (e) {
        // Retry on server errors (5xx) and rate limits (429).
        final retryable = e.statusCode != null &&
            (e.statusCode! >= 500 || e.statusCode == 429);
        attempt++;
        if (!retryable || attempt >= _QboConfig.maxRetries) {
          rethrow;
        }
        final delay = _QboConfig.baseRetryDelay * pow(2, attempt - 1);
        await Future<void>.delayed(delay);
      }
    }
  }

  // -------------------------------------------------------------------------
  // Response validation
  // -------------------------------------------------------------------------

  void _checkResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;

    String message;
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final fault = body['Fault'] as Map<String, dynamic>?;
      if (fault != null) {
        final errors = fault['Error'] as List<dynamic>?;
        if (errors != null && errors.isNotEmpty) {
          final firstError = errors.first as Map<String, dynamic>;
          message = firstError['Message'] as String? ??
              firstError['Detail'] as String? ??
              'Unknown QuickBooks error';
        } else {
          message = 'QuickBooks API error';
        }
      } else {
        message = response.body;
      }
    } catch (_) {
      message = 'HTTP ${response.statusCode}: ${response.reasonPhrase}';
    }

    throw AccountingProviderException(
      providerName: providerName,
      message: message,
      statusCode: response.statusCode,
    );
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  /// Ensures we have a realm ID, loading from storage if needed.
  Future<String> _ensureRealmId() async {
    if (_realmId != null) return _realmId!;

    // Attempt to load from secure storage (stored during authenticate()).
    // Note: consumeCodeVerifier would delete it, so we use a read approach.
    // We stored it under a special key during auth.
    final stored = await _tokenStore.readAccessToken(
      '${_QboConfig.providerKey}_realm',
    );
    // Fallback: check the code verifier storage path we used.
    if (stored == null) {
      throw const AccountingProviderException(
        providerName: 'QuickBooks Online',
        message: 'No QuickBooks company is connected. Please authenticate '
            'first.',
      );
    }
    _realmId = stored;
    return _realmId!;
  }

  /// Loads a receipt from the local database.
  Future<Receipt> _loadReceipt(String receiptId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'receipts',
      where: 'receipt_id = ?',
      whereArgs: [receiptId],
    );
    if (rows.isEmpty) {
      throw AccountingProviderException(
        providerName: providerName,
        message: 'Receipt not found locally: $receiptId',
      );
    }
    return Receipt.fromMap(rows.first);
  }

  /// Formats a DateTime as `YYYY-MM-DD` for QuickBooks queries.
  String _isoDate(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-'
      '${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')}';
}
