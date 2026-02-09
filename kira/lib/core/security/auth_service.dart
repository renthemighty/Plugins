/// Orchestrates OAuth 2.0 Authorization Code + PKCE flows for all cloud
/// storage providers.
///
/// Responsibilities:
/// - Generate cryptographically random PKCE code verifiers and S256 challenges.
/// - Drive the authorization flow via [FlutterAppAuth].
/// - Exchange authorization codes for access/refresh tokens.
/// - Transparently refresh expired tokens.
/// - Revoke tokens on logout.
///
/// **Security invariants:**
/// - Client secrets are never embedded in the app binary.
/// - All redirect URIs use HTTPS or a private-use URI scheme.
/// - Tokens are never logged, printed, or written to unencrypted storage.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:http/http.dart' as http;

import 'secure_token_store.dart';

// ---------------------------------------------------------------------------
// Provider configuration
// ---------------------------------------------------------------------------

/// Immutable configuration for a single OAuth 2.0 provider.
class OAuthProviderConfig {
  final String providerId;
  final String authorizationEndpoint;
  final String tokenEndpoint;
  final String? revocationEndpoint;
  final String redirectUri;
  final List<String> scopes;

  /// Optional `resource` parameter required by some providers (e.g. Microsoft).
  final String? resource;

  /// Additional query parameters appended to the authorization request.
  final Map<String, String>? additionalParameters;

  const OAuthProviderConfig({
    required this.providerId,
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    this.revocationEndpoint,
    required this.redirectUri,
    required this.scopes,
    this.resource,
    this.additionalParameters,
  });
}

/// Pre-built configurations for the four third-party cloud providers.
///
/// The `clientId` is injected at build time via `--dart-define` so that it
/// never appears in version control.  Each provider registers a private-use
/// URI scheme redirect (e.g. `com.kira.app:/oauth2redirect`).
abstract final class OAuthConfigs {
  static const _redirectUri = 'com.kira.app:/oauth2redirect';

  static const googleDrive = OAuthProviderConfig(
    providerId: 'google_drive',
    authorizationEndpoint: 'https://accounts.google.com/o/oauth2/v2/auth',
    tokenEndpoint: 'https://oauth2.googleapis.com/token',
    revocationEndpoint: 'https://oauth2.googleapis.com/revoke',
    redirectUri: _redirectUri,
    scopes: ['https://www.googleapis.com/auth/drive.file'],
    additionalParameters: {'access_type': 'offline', 'prompt': 'consent'},
  );

  static const dropbox = OAuthProviderConfig(
    providerId: 'dropbox',
    authorizationEndpoint: 'https://www.dropbox.com/oauth2/authorize',
    tokenEndpoint: 'https://api.dropboxapi.com/oauth2/token',
    revocationEndpoint: 'https://api.dropboxapi.com/2/auth/token/revoke',
    redirectUri: _redirectUri,
    scopes: [],
    additionalParameters: {'token_access_type': 'offline'},
  );

  static const oneDrive = OAuthProviderConfig(
    providerId: 'onedrive',
    authorizationEndpoint:
        'https://login.microsoftonline.com/common/oauth2/v2.0/authorize',
    tokenEndpoint:
        'https://login.microsoftonline.com/common/oauth2/v2.0/token',
    revocationEndpoint: null, // Microsoft does not expose a revocation endpoint.
    redirectUri: _redirectUri,
    scopes: [
      'Files.ReadWrite.AppFolder',
      'offline_access',
    ],
  );

  static const box = OAuthProviderConfig(
    providerId: 'box',
    authorizationEndpoint: 'https://account.box.com/api/oauth2/authorize',
    tokenEndpoint: 'https://api.box.com/oauth2/token',
    revocationEndpoint: 'https://api.box.com/oauth2/revoke',
    redirectUri: _redirectUri,
    scopes: [],
  );
}

// ---------------------------------------------------------------------------
// Auth service
// ---------------------------------------------------------------------------

class AuthService {
  AuthService({
    required SecureTokenStore tokenStore,
    FlutterAppAuth? appAuth,
    http.Client? httpClient,
  })  : _tokenStore = tokenStore,
        _appAuth = appAuth ?? const FlutterAppAuth(),
        _httpClient = httpClient ?? http.Client();

  final SecureTokenStore _tokenStore;
  final FlutterAppAuth _appAuth;
  final http.Client _httpClient;

  // ---------------------------------------------------------------------------
  // PKCE helpers
  // ---------------------------------------------------------------------------

  /// Generates a 128-character URL-safe random string for use as a PKCE code
  /// verifier (RFC 7636 section 4.1).
  static String generateCodeVerifier() {
    final random = Random.secure();
    final bytes = Uint8List(96); // 96 bytes -> 128 base64url characters
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  /// Derives the S256 code challenge from a [codeVerifier]
  /// (RFC 7636 section 4.2).
  static String generateCodeChallenge(String codeVerifier) {
    final digest = sha256.convert(utf8.encode(codeVerifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  // ---------------------------------------------------------------------------
  // Authorization
  // ---------------------------------------------------------------------------

  /// Runs the full OAuth 2.0 Authorization Code + PKCE flow for [config].
  ///
  /// Opens a secure browser session, waits for the redirect, exchanges the
  /// code for tokens, and persists them in [SecureTokenStore].
  ///
  /// Returns the resulting [OAuthTokens], or throws on failure.
  Future<OAuthTokens> authorize(OAuthProviderConfig config) async {
    // Resolve the client ID from compile-time defines.
    final clientId = _clientIdForProvider(config.providerId);

    final result = await _appAuth.authorizeAndExchangeCode(
      AuthorizationTokenRequest(
        clientId,
        config.redirectUri,
        serviceConfiguration: AuthorizationServiceConfiguration(
          authorizationEndpoint: config.authorizationEndpoint,
          tokenEndpoint: config.tokenEndpoint,
        ),
        scopes: config.scopes,
        additionalParameters: config.additionalParameters,
        // flutter_appauth handles PKCE internally when no client secret
        // is provided.
      ),
    );

    if (result == null) {
      throw AuthException('Authorization was cancelled by the user.');
    }

    final tokens = OAuthTokens(
      accessToken: result.accessToken!,
      refreshToken: result.refreshToken,
      idToken: result.idToken,
      expiresAt: result.accessTokenExpirationDateTime?.toUtc(),
    );

    await _tokenStore.saveTokens(config.providerId, tokens);
    return tokens;
  }

  // ---------------------------------------------------------------------------
  // Token refresh
  // ---------------------------------------------------------------------------

  /// Returns a valid access token for [config], refreshing transparently if
  /// the current one has expired.
  ///
  /// If no tokens exist at all, throws [AuthException].
  Future<String> getValidAccessToken(OAuthProviderConfig config) async {
    final existing = await _tokenStore.readTokens(config.providerId);
    if (existing == null) {
      throw AuthException(
        'No tokens stored for ${config.providerId}. '
        'Call authorize() first.',
      );
    }

    if (!existing.isExpired) {
      return existing.accessToken;
    }

    // The access token has expired -- try to refresh.
    if (existing.refreshToken == null) {
      throw AuthException(
        'Access token expired and no refresh token available for '
        '${config.providerId}.',
      );
    }

    return _refreshTokens(config, existing.refreshToken!);
  }

  /// Exchanges a refresh token for a fresh access token and persists the
  /// result.
  Future<String> _refreshTokens(
    OAuthProviderConfig config,
    String refreshToken,
  ) async {
    final clientId = _clientIdForProvider(config.providerId);

    final result = await _appAuth.token(
      TokenRequest(
        clientId,
        config.redirectUri,
        serviceConfiguration: AuthorizationServiceConfiguration(
          authorizationEndpoint: config.authorizationEndpoint,
          tokenEndpoint: config.tokenEndpoint,
        ),
        refreshToken: refreshToken,
        scopes: config.scopes,
      ),
    );

    if (result == null) {
      throw AuthException('Token refresh failed for ${config.providerId}.');
    }

    final tokens = OAuthTokens(
      accessToken: result.accessToken!,
      refreshToken: result.refreshToken ?? refreshToken,
      idToken: result.idToken,
      expiresAt: result.accessTokenExpirationDateTime?.toUtc(),
    );

    await _tokenStore.saveTokens(config.providerId, tokens);
    return tokens.accessToken;
  }

  // ---------------------------------------------------------------------------
  // Logout / revoke
  // ---------------------------------------------------------------------------

  /// Revokes tokens with the provider (best-effort) and removes them from
  /// local secure storage.
  Future<void> logout(OAuthProviderConfig config) async {
    final tokens = await _tokenStore.readTokens(config.providerId);

    // Best-effort revocation -- don't block logout on network failures.
    if (tokens != null && config.revocationEndpoint != null) {
      try {
        await _revokeToken(
          config.revocationEndpoint!,
          tokens.accessToken,
        );
        if (tokens.refreshToken != null) {
          await _revokeToken(
            config.revocationEndpoint!,
            tokens.refreshToken!,
          );
        }
      } catch (_) {
        // Swallow -- the tokens will expire naturally, and we are removing
        // them from local storage regardless.
      }
    }

    await _tokenStore.deleteTokens(config.providerId);
  }

  Future<void> _revokeToken(String endpoint, String token) async {
    final uri = Uri.parse(endpoint);
    // Google uses a query parameter; most others use a form body.
    if (uri.host.contains('googleapis.com')) {
      await _httpClient.post(
        uri.replace(queryParameters: {'token': token}),
      );
    } else {
      await _httpClient.post(
        uri,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'token=$token',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Status
  // ---------------------------------------------------------------------------

  /// Returns `true` when a non-expired access token (or a refresh token that
  /// can be used to obtain one) exists for [config].
  Future<bool> isAuthenticated(OAuthProviderConfig config) async {
    final tokens = await _tokenStore.readTokens(config.providerId);
    if (tokens == null) return false;
    if (!tokens.isExpired) return true;
    return tokens.refreshToken != null;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Reads the client ID for [providerId] from compile-time `--dart-define`
  /// constants.
  ///
  /// Example build invocation:
  /// ```
  /// flutter run \
  ///   --dart-define=GOOGLE_DRIVE_CLIENT_ID=abc123 \
  ///   --dart-define=DROPBOX_CLIENT_ID=xyz789
  /// ```
  static String _clientIdForProvider(String providerId) {
    const env = <String, String>{
      'google_drive': String.fromEnvironment('GOOGLE_DRIVE_CLIENT_ID'),
      'dropbox': String.fromEnvironment('DROPBOX_CLIENT_ID'),
      'onedrive': String.fromEnvironment('ONEDRIVE_CLIENT_ID'),
      'box': String.fromEnvironment('BOX_CLIENT_ID'),
      'kira_cloud': String.fromEnvironment('KIRA_CLOUD_CLIENT_ID'),
    };

    final clientId = env[providerId];
    if (clientId == null || clientId.isEmpty) {
      throw AuthException(
        'Missing client ID for provider "$providerId". '
        'Pass it via --dart-define=${providerId.toUpperCase()}_CLIENT_ID=<id>.',
      );
    }
    return clientId;
  }

  /// Disposes the internally created [http.Client].  Call this when the
  /// service is no longer needed.
  void dispose() {
    _httpClient.close();
  }
}

// ---------------------------------------------------------------------------
// Exceptions
// ---------------------------------------------------------------------------

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => 'AuthException: $message';
}
