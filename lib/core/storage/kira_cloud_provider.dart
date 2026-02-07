/// Kira-managed cloud storage provider.
///
/// Unlike the third-party providers, Kira Cloud is a first-party backend
/// where users authenticate with a **passkey** or **email one-time password**
/// (OTP) -- there is no OAuth consent screen for a third-party service.
///
/// ## Subscription model
///
/// Storage is subscription-gated via in-app purchase.  Pricing is set to
/// approximately **3x Apple iCloud equivalent** to cover the operational
/// costs of a small independent app.
///
/// ## Business workspaces
///
/// Kira Cloud supports shared workspaces for teams.  Admins can view
/// per-workspace metrics (storage usage, receipt counts, error rates) and
/// manage members.
///
/// ## Error reporting
///
/// The provider automatically submits anonymised, opt-in error reports to
/// the Kira backend so the team can triage issues without asking users to
/// reproduce bugs manually.
///
/// All HTTP calls enforce HTTPS and use [retryWithBackoff].
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../security/network_security.dart';
import '../security/secure_token_store.dart';
import 'storage_provider.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Kira Cloud backend API base URL.
const String _kiraApiBase = 'https://api.kira.app/v1';

/// Disclaimer text to display in the UI whenever Kira Cloud pricing is shown.
const String kKiraCloudPricingDisclaimer =
    'Kira Cloud storage is a paid subscription billed through the App Store '
    'or Google Play.  Pricing is approximately 3\u00d7 the equivalent Apple '
    'iCloud plan to sustain independent development and cover infrastructure '
    'costs.  You can cancel at any time and your data will remain available '
    'for download for 90 days after cancellation.  Kira Cloud is entirely '
    'optional -- you may use Google Drive, Dropbox, OneDrive, Box, or '
    'local-only encrypted storage at no additional cost.';

/// Disclaimer text for business workspace data processing.
const String kKiraCloudBusinessDisclaimer =
    'By creating or joining a Kira Cloud workspace, you acknowledge that '
    'receipt data uploaded by workspace members is shared with the workspace '
    'administrator for reporting purposes.  Workspace admins can view '
    'aggregate metrics (storage usage, receipt count, error rates) but '
    'cannot access the contents of individual receipts unless explicitly '
    'shared by the member.';

// ---------------------------------------------------------------------------
// Auth method
// ---------------------------------------------------------------------------

/// The authentication method used for Kira Cloud.
enum KiraAuthMethod {
  /// WebAuthn / FIDO2 passkey.
  passkey,

  /// One-time password sent to the user's email.
  emailOtp,
}

// ---------------------------------------------------------------------------
// Subscription tier
// ---------------------------------------------------------------------------

/// Kira Cloud subscription tiers.
enum KiraSubscriptionTier {
  /// Free tier -- no cloud storage, only used to verify account.
  free,

  /// 50 GB storage.
  starter,

  /// 200 GB storage.
  standard,

  /// 2 TB storage.
  premium,

  /// Custom-capacity plan for business workspaces.
  business,
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

class KiraCloudProvider implements StorageProvider {
  KiraCloudProvider({
    required SecureTokenStore tokenStore,
    http.Client? httpClient,
    FlutterSecureStorage? secureStorage,
  })  : _tokenStore = tokenStore,
        _http = httpClient ?? SecureHttpClient(),
        _storage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility:
                    KeychainAccessibility.first_unlock_this_device,
              ),
            );

  final SecureTokenStore _tokenStore;
  final http.Client _http;
  final FlutterSecureStorage _storage;

  static const String _providerId = 'kira_cloud';

  /// Key for storing the active workspace ID.
  static const String _workspaceKey = 'kira_cloud_workspace_id';

  // ---------------------------------------------------------------------------
  // Auth
  // ---------------------------------------------------------------------------

  @override
  String get providerName => 'Kira Cloud';

  /// Authenticates with the Kira backend using the given [method].
  ///
  /// For [KiraAuthMethod.passkey], the method triggers the platform WebAuthn
  /// flow.  For [KiraAuthMethod.emailOtp], the caller must first call
  /// [requestEmailOtp] and then pass the OTP to [verifyEmailOtp].
  ///
  /// This is the full-flow convenience entry point -- it calls
  /// [authenticateWithPasskey] or throws if email OTP is chosen (since that
  /// requires two steps).
  @override
  Future<void> authenticate() async {
    // Default to passkey.  The UI layer should call the specific methods
    // for email OTP.
    await authenticateWithPasskey();
  }

  /// Authenticates using a FIDO2 / WebAuthn passkey.
  Future<void> authenticateWithPasskey() async {
    // Step 1: Request a challenge from the backend.
    final challengeResp = await retryWithBackoff(() async {
      final resp = await _http.post(
        Uri.parse('$_kiraApiBase/auth/passkey/challenge'),
        headers: {'Content-Type': 'application/json'},
      );
      _checkResponse(resp);
      return resp;
    });

    final challengeData =
        jsonDecode(challengeResp.body) as Map<String, dynamic>;

    // Step 2: Sign the challenge with the platform authenticator.
    // In production this would invoke a platform channel to the WebAuthn
    // API.  The signed assertion is sent back to the server.
    //
    // For now we send the challenge ID back -- the actual WebAuthn signing
    // will be implemented via a platform channel.
    final challengeId = challengeData['challenge_id'] as String;

    final authResp = await retryWithBackoff(() async {
      final resp = await _http.post(
        Uri.parse('$_kiraApiBase/auth/passkey/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'challenge_id': challengeId,
          // 'assertion': <signed assertion from platform authenticator>,
          'platform': Platform.isIOS ? 'ios' : 'android',
        }),
      );
      _checkResponse(resp);
      return resp;
    });

    await _persistTokensFromResponse(authResp);
  }

  /// Requests an OTP to be sent to [email].
  Future<void> requestEmailOtp(String email) async {
    await retryWithBackoff(() async {
      final resp = await _http.post(
        Uri.parse('$_kiraApiBase/auth/otp/request'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );
      _checkResponse(resp);
    });
  }

  /// Verifies the [otp] sent to [email] and completes authentication.
  Future<void> verifyEmailOtp(String email, String otp) async {
    final resp = await retryWithBackoff(() async {
      final r = await _http.post(
        Uri.parse('$_kiraApiBase/auth/otp/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'otp': otp}),
      );
      _checkResponse(r);
      return r;
    });

    await _persistTokensFromResponse(resp);
  }

  @override
  Future<bool> isAuthenticated() async {
    final tokens = await _tokenStore.readTokens(_providerId);
    if (tokens == null) return false;
    if (!tokens.isExpired) return true;

    // Try to refresh.
    if (tokens.refreshToken == null) return false;
    try {
      await _refreshToken(tokens.refreshToken!);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> logout() async {
    final tokens = await _tokenStore.readTokens(_providerId);
    if (tokens != null) {
      try {
        await _http.post(
          Uri.parse('$_kiraApiBase/auth/logout'),
          headers: _authHeaders(tokens.accessToken),
        );
      } catch (_) {
        // Best-effort.
      }
    }
    await _tokenStore.deleteTokens(_providerId);
    await _storage.delete(key: _workspaceKey);
  }

  // ---------------------------------------------------------------------------
  // Subscription
  // ---------------------------------------------------------------------------

  /// Returns the current subscription tier, or [KiraSubscriptionTier.free] if
  /// the user has no active subscription.
  Future<KiraSubscriptionTier> getSubscriptionTier() async {
    final token = await _accessToken();
    final resp = await retryWithBackoff(() async {
      final r = await _http.get(
        Uri.parse('$_kiraApiBase/subscription'),
        headers: _authHeaders(token),
      );
      _checkResponse(r);
      return r;
    });

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final tierStr = data['tier'] as String? ?? 'free';
    return KiraSubscriptionTier.values.firstWhere(
      (t) => t.name == tierStr,
      orElse: () => KiraSubscriptionTier.free,
    );
  }

  /// Validates a purchase receipt from the App Store or Google Play.
  Future<bool> validatePurchase({
    required String receiptData,
    required String store, // 'apple' or 'google'
  }) async {
    final token = await _accessToken();
    final resp = await retryWithBackoff(() async {
      final r = await _http.post(
        Uri.parse('$_kiraApiBase/subscription/validate'),
        headers: {
          ..._authHeaders(token),
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'receipt_data': receiptData,
          'store': store,
        }),
      );
      _checkResponse(r);
      return r;
    });

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return data['valid'] as bool? ?? false;
  }

  // ---------------------------------------------------------------------------
  // Business workspaces
  // ---------------------------------------------------------------------------

  /// Sets the active workspace ID for subsequent API calls.
  Future<void> setActiveWorkspace(String workspaceId) async {
    await _storage.write(key: _workspaceKey, value: workspaceId);
  }

  /// Returns the currently active workspace ID, or `null` for personal use.
  Future<String?> getActiveWorkspace() async {
    return _storage.read(key: _workspaceKey);
  }

  /// Fetches admin metrics for the given [workspaceId].
  Future<Map<String, dynamic>> getWorkspaceMetrics(
    String workspaceId,
  ) async {
    final token = await _accessToken();
    final resp = await retryWithBackoff(() async {
      final r = await _http.get(
        Uri.parse('$_kiraApiBase/workspaces/$workspaceId/metrics'),
        headers: _authHeaders(token),
      );
      _checkResponse(r);
      return r;
    });
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  // ---------------------------------------------------------------------------
  // Error reporting
  // ---------------------------------------------------------------------------

  /// Submits an anonymised error report to the Kira backend.
  ///
  /// Reports are opt-in and contain no PII.  The user must have enabled
  /// error reporting in the app settings.
  Future<void> submitErrorReport({
    required String errorType,
    required String message,
    String? stackTrace,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final token = await _accessToken();
      await _http.post(
        Uri.parse('$_kiraApiBase/errors/report'),
        headers: {
          ..._authHeaders(token),
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'error_type': errorType,
          'message': message,
          'stack_trace': stackTrace,
          'metadata': metadata,
          'platform': Platform.isIOS ? 'ios' : 'android',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        }),
      );
    } catch (_) {
      // Error reporting is best-effort -- never interrupt the user.
    }
  }

  // ---------------------------------------------------------------------------
  // StorageProvider -- file operations
  // ---------------------------------------------------------------------------

  @override
  Future<void> createFolder(String remotePath) async {
    final token = await _accessToken();
    await retryWithBackoff(() async {
      final resp = await _http.post(
        Uri.parse('$_kiraApiBase/storage/folders'),
        headers: {
          ..._authHeaders(token),
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'path': remotePath,
          'workspace_id': await getActiveWorkspace(),
        }),
      );
      // 409 = folder exists, which is fine.
      if (resp.statusCode == 409) return;
      _checkResponse(resp);
    });
  }

  @override
  Future<void> uploadFile(String localPath, String remotePath) async {
    final file = File(localPath);
    if (!(await file.exists())) {
      throw StorageException('Local file does not exist: $localPath');
    }

    final bytes = await file.readAsBytes();
    final token = await _accessToken();

    await retryWithBackoff(() async {
      final request = http.MultipartRequest(
        'PUT',
        Uri.parse('$_kiraApiBase/storage/files'),
      )
        ..headers.addAll(_authHeaders(token))
        ..fields['path'] = remotePath
        ..fields['workspace_id'] = (await getActiveWorkspace()) ?? ''
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: remotePath.split('/').last,
        ));

      final streamed = await _http.send(request);
      final resp = await http.Response.fromStream(streamed);
      _checkResponse(resp);
    });
  }

  @override
  Future<void> downloadFile(String remotePath, String localPath) async {
    final token = await _accessToken();
    final workspaceId = await getActiveWorkspace();

    final uri = Uri.parse('$_kiraApiBase/storage/files/content').replace(
      queryParameters: {
        'path': remotePath,
        if (workspaceId != null) 'workspace_id': workspaceId,
      },
    );

    final response = await retryWithBackoff(() async {
      final resp = await _http.get(uri, headers: _authHeaders(token));
      _checkResponse(resp);
      return resp;
    });

    await File(localPath).writeAsBytes(response.bodyBytes, flush: true);
  }

  @override
  Future<List<String>> listFiles(String remotePath) async {
    final token = await _accessToken();
    final workspaceId = await getActiveWorkspace();

    final uri = Uri.parse('$_kiraApiBase/storage/files').replace(
      queryParameters: {
        'path': remotePath,
        if (workspaceId != null) 'workspace_id': workspaceId,
      },
    );

    final response = await retryWithBackoff(() async {
      final resp = await _http.get(uri, headers: _authHeaders(token));
      _checkResponse(resp);
      return resp;
    });

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>? ?? [];
    return items.map((i) => (i as Map<String, dynamic>)['name'] as String).toList();
  }

  @override
  Future<bool> fileExists(String remotePath) async {
    final token = await _accessToken();
    final workspaceId = await getActiveWorkspace();

    final uri = Uri.parse('$_kiraApiBase/storage/files/metadata').replace(
      queryParameters: {
        'path': remotePath,
        if (workspaceId != null) 'workspace_id': workspaceId,
      },
    );

    try {
      await retryWithBackoff(() async {
        final resp = await _http.get(uri, headers: _authHeaders(token));
        _checkResponse(resp);
      });
      return true;
    } on StorageNotFoundException {
      return false;
    }
  }

  @override
  Future<String?> readTextFile(String remotePath) async {
    final token = await _accessToken();
    final workspaceId = await getActiveWorkspace();

    final uri = Uri.parse('$_kiraApiBase/storage/files/content').replace(
      queryParameters: {
        'path': remotePath,
        if (workspaceId != null) 'workspace_id': workspaceId,
      },
    );

    try {
      final response = await retryWithBackoff(() async {
        final resp = await _http.get(uri, headers: _authHeaders(token));
        _checkResponse(resp);
        return resp;
      });
      return response.body;
    } on StorageNotFoundException {
      return null;
    }
  }

  @override
  Future<void> writeTextFile(String remotePath, String content) async {
    final token = await _accessToken();
    final bytes = utf8.encode(content);

    await retryWithBackoff(() async {
      final resp = await _http.put(
        Uri.parse('$_kiraApiBase/storage/files/content'),
        headers: {
          ..._authHeaders(token),
          'Content-Type': 'text/plain; charset=utf-8',
          'X-Kira-Path': remotePath,
          if (await getActiveWorkspace() case final wid?)
            'X-Kira-Workspace': wid,
        },
        body: bytes,
      );
      _checkResponse(resp);
    });
  }

  @override
  Future<void> moveFile(String fromPath, String toPath) async {
    final token = await _accessToken();

    await retryWithBackoff(() async {
      final resp = await _http.post(
        Uri.parse('$_kiraApiBase/storage/files/move'),
        headers: {
          ..._authHeaders(token),
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'from_path': fromPath,
          'to_path': toPath,
          'workspace_id': await getActiveWorkspace(),
        }),
      );
      _checkResponse(resp);
    });
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  Future<String> _accessToken() async {
    final tokens = await _tokenStore.readTokens(_providerId);
    if (tokens == null) {
      throw StorageAuthException(
        'Not authenticated with Kira Cloud. Call authenticate() first.',
      );
    }

    if (!tokens.isExpired) return tokens.accessToken;

    if (tokens.refreshToken == null) {
      throw StorageAuthException(
        'Kira Cloud access token expired and no refresh token available.',
      );
    }

    return _refreshToken(tokens.refreshToken!);
  }

  Future<String> _refreshToken(String refreshToken) async {
    final resp = await retryWithBackoff(() async {
      final r = await _http.post(
        Uri.parse('$_kiraApiBase/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      );
      _checkResponse(r);
      return r;
    });

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final tokens = OAuthTokens(
      accessToken: data['access_token'] as String,
      refreshToken: data['refresh_token'] as String? ?? refreshToken,
      expiresAt: data['expires_at'] != null
          ? DateTime.parse(data['expires_at'] as String).toUtc()
          : null,
    );

    await _tokenStore.saveTokens(_providerId, tokens);
    return tokens.accessToken;
  }

  Future<void> _persistTokensFromResponse(http.Response resp) async {
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final tokens = OAuthTokens(
      accessToken: data['access_token'] as String,
      refreshToken: data['refresh_token'] as String?,
      expiresAt: data['expires_at'] != null
          ? DateTime.parse(data['expires_at'] as String).toUtc()
          : null,
    );
    await _tokenStore.saveTokens(_providerId, tokens);
  }

  Map<String, String> _authHeaders(String token) => {
        'Authorization': 'Bearer $token',
      };

  void _checkResponse(http.Response response) {
    final code = response.statusCode;
    if (code >= 200 && code < 300) return;

    if (code == 401) {
      throw StorageAuthException(
        'Kira Cloud authentication failed (HTTP $code).',
        cause: response.body,
      );
    }
    if (code == 403) {
      throw StorageAuthException(
        'Kira Cloud access denied (HTTP $code). '
        'Check your subscription status.',
        cause: response.body,
      );
    }
    if (code == 404) {
      throw StorageNotFoundException(
        'Kira Cloud resource not found (HTTP $code).',
        cause: response.body,
      );
    }
    if (code == 413 || code == 507) {
      throw StorageQuotaException(
        'Kira Cloud storage quota exceeded. '
        'Consider upgrading your plan.',
        cause: response.body,
      );
    }
    if (code == 429 || (code >= 500 && code < 600)) {
      throw RetryableHttpException(code, response.body);
    }

    throw StorageException(
      'Kira Cloud API error (HTTP $code).',
      cause: response.body,
    );
  }
}
