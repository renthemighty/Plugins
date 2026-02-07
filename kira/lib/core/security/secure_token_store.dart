/// Secure token storage for OAuth credentials.
///
/// Wraps [FlutterSecureStorage] to provide a typed API for persisting,
/// retrieving, and deleting OAuth tokens.  On iOS tokens are stored in the
/// Keychain; on Android they use the platform Keystore-backed encrypted
/// shared preferences.
///
/// **Security invariant:** tokens are never written to logs, crash reports,
/// or any unencrypted persistence layer.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The set of keys we write into secure storage.  Keeping them in one place
/// makes auditing easier and prevents accidental collisions.
abstract final class _Keys {
  static String accessToken(String provider) => '${provider}_access_token';
  static String refreshToken(String provider) => '${provider}_refresh_token';
  static String tokenExpiry(String provider) => '${provider}_token_expiry';
  static String idToken(String provider) => '${provider}_id_token';
  static String codeVerifier(String provider) => '${provider}_code_verifier';
}

/// A lightweight value object that groups the tokens returned by an OAuth
/// authorization or refresh flow.
class OAuthTokens {
  final String accessToken;
  final String? refreshToken;
  final String? idToken;
  final DateTime? expiresAt;

  const OAuthTokens({
    required this.accessToken,
    this.refreshToken,
    this.idToken,
    this.expiresAt,
  });

  /// Returns `true` when [expiresAt] is known and the token has already
  /// expired (or will expire within the next 60 seconds).
  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().toUtc().isAfter(
          expiresAt!.subtract(const Duration(seconds: 60)),
        );
  }

  @override
  String toString() =>
      'OAuthTokens(accessToken: [REDACTED], refreshToken: '
      '${refreshToken != null ? "[REDACTED]" : "null"}, '
      'expiresAt: $expiresAt)';
}

/// Provides secure read/write/delete access to OAuth tokens.
///
/// Each provider (e.g. `google_drive`, `dropbox`) gets its own namespace so
/// that multiple cloud accounts can coexist.
class SecureTokenStore {
  SecureTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  final FlutterSecureStorage _storage;

  // ---------------------------------------------------------------------------
  // Persist
  // ---------------------------------------------------------------------------

  /// Saves a complete [OAuthTokens] bundle for [provider].
  Future<void> saveTokens(String provider, OAuthTokens tokens) async {
    await _storage.write(
      key: _Keys.accessToken(provider),
      value: tokens.accessToken,
    );

    if (tokens.refreshToken != null) {
      await _storage.write(
        key: _Keys.refreshToken(provider),
        value: tokens.refreshToken,
      );
    }

    if (tokens.idToken != null) {
      await _storage.write(
        key: _Keys.idToken(provider),
        value: tokens.idToken,
      );
    }

    if (tokens.expiresAt != null) {
      await _storage.write(
        key: _Keys.tokenExpiry(provider),
        value: tokens.expiresAt!.toUtc().toIso8601String(),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Retrieve
  // ---------------------------------------------------------------------------

  /// Reads the stored tokens for [provider], or returns `null` if none exist.
  Future<OAuthTokens?> readTokens(String provider) async {
    final accessToken = await _storage.read(
      key: _Keys.accessToken(provider),
    );
    if (accessToken == null) return null;

    final refreshToken = await _storage.read(
      key: _Keys.refreshToken(provider),
    );
    final idToken = await _storage.read(
      key: _Keys.idToken(provider),
    );
    final expiryString = await _storage.read(
      key: _Keys.tokenExpiry(provider),
    );

    DateTime? expiresAt;
    if (expiryString != null) {
      expiresAt = DateTime.tryParse(expiryString)?.toUtc();
    }

    return OAuthTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      idToken: idToken,
      expiresAt: expiresAt,
    );
  }

  /// Returns just the current access token, or `null`.
  Future<String?> readAccessToken(String provider) async {
    return _storage.read(key: _Keys.accessToken(provider));
  }

  /// Returns just the current refresh token, or `null`.
  Future<String?> readRefreshToken(String provider) async {
    return _storage.read(key: _Keys.refreshToken(provider));
  }

  // ---------------------------------------------------------------------------
  // PKCE code verifier
  // ---------------------------------------------------------------------------

  /// Temporarily stores the PKCE code verifier while the user is in the
  /// browser completing the OAuth consent screen.
  Future<void> saveCodeVerifier(String provider, String verifier) async {
    await _storage.write(
      key: _Keys.codeVerifier(provider),
      value: verifier,
    );
  }

  /// Reads and deletes the PKCE code verifier (one-time use).
  Future<String?> consumeCodeVerifier(String provider) async {
    final verifier = await _storage.read(
      key: _Keys.codeVerifier(provider),
    );
    if (verifier != null) {
      await _storage.delete(key: _Keys.codeVerifier(provider));
    }
    return verifier;
  }

  // ---------------------------------------------------------------------------
  // Delete
  // ---------------------------------------------------------------------------

  /// Removes all tokens for [provider].
  Future<void> deleteTokens(String provider) async {
    await Future.wait([
      _storage.delete(key: _Keys.accessToken(provider)),
      _storage.delete(key: _Keys.refreshToken(provider)),
      _storage.delete(key: _Keys.tokenExpiry(provider)),
      _storage.delete(key: _Keys.idToken(provider)),
      _storage.delete(key: _Keys.codeVerifier(provider)),
    ]);
  }

  /// Removes **all** Kira-managed entries from secure storage.
  ///
  /// This is the nuclear option -- used during account deletion or full reset.
  Future<void> deleteAll() async {
    await _storage.deleteAll();
  }

  // ---------------------------------------------------------------------------
  // Query
  // ---------------------------------------------------------------------------

  /// Returns `true` if an access token exists for [provider].
  Future<bool> hasTokens(String provider) async {
    final token = await _storage.read(key: _Keys.accessToken(provider));
    return token != null;
  }
}
