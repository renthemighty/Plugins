/// Dropbox implementation of [StorageProvider].
///
/// Uses OAuth 2.0 Authorization Code + PKCE via [flutter_appauth].
/// Requests `token_access_type=offline` for long-lived refresh tokens.
/// No additional scopes are needed -- the Dropbox API grants full access
/// to the app folder by default when using an "App folder" type app.
///
/// All HTTP calls go through [SecureHttpClient] (HTTPS-only) and are
/// wrapped in [retryWithBackoff] for transient-failure resilience.
///
/// **No client secret is embedded in the binary.**
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../security/auth_service.dart';
import '../security/network_security.dart';
import '../security/secure_token_store.dart';
import 'storage_provider.dart';

/// Dropbox API v2 RPC endpoint.
const String _apiBase = 'https://api.dropboxapi.com/2';

/// Dropbox content upload/download endpoint.
const String _contentBase = 'https://content.dropboxapi.com/2';

class DropboxProvider implements StorageProvider {
  DropboxProvider({
    required AuthService authService,
    required SecureTokenStore tokenStore,
    http.Client? httpClient,
  })  : _authService = authService,
        _tokenStore = tokenStore,
        _http = httpClient ?? SecureHttpClient();

  final AuthService _authService;
  final SecureTokenStore _tokenStore;
  final http.Client _http;

  static const _config = OAuthConfigs.dropbox;

  // ---------------------------------------------------------------------------
  // Auth
  // ---------------------------------------------------------------------------

  @override
  String get providerName => 'Dropbox';

  @override
  Future<void> authenticate() async {
    await _authService.authorize(_config);
  }

  @override
  Future<bool> isAuthenticated() => _authService.isAuthenticated(_config);

  @override
  Future<void> logout() async {
    // Dropbox token revocation is a POST to /2/auth/token/revoke.
    // AuthService.logout handles this via the revocationEndpoint config.
    await _authService.logout(_config);
  }

  // ---------------------------------------------------------------------------
  // Folder operations
  // ---------------------------------------------------------------------------

  @override
  Future<void> createFolder(String remotePath) async {
    final path = _normalize(remotePath);
    final token = await _accessToken();

    try {
      await retryWithBackoff(() async {
        final resp = await _http.post(
          Uri.parse('$_apiBase/files/create_folder_v2'),
          headers: {
            ..._authHeaders(token),
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'path': path,
            'autorename': false,
          }),
        );

        // 409 with "path/conflict/folder" means the folder already exists.
        if (resp.statusCode == 409) {
          final body = jsonDecode(resp.body) as Map<String, dynamic>;
          final tag = _extractErrorTag(body);
          if (tag == 'folder') return;
          _checkResponse(resp);
        } else {
          _checkResponse(resp);
        }
      });
    } on StorageException {
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // File operations
  // ---------------------------------------------------------------------------

  @override
  Future<void> uploadFile(String localPath, String remotePath) async {
    final file = File(localPath);
    if (!(await file.exists())) {
      throw StorageException('Local file does not exist: $localPath');
    }

    final bytes = await file.readAsBytes();
    final path = _normalize(remotePath);
    final token = await _accessToken();

    await retryWithBackoff(() async {
      final resp = await _http.post(
        Uri.parse('$_contentBase/files/upload'),
        headers: {
          ..._authHeaders(token),
          'Content-Type': 'application/octet-stream',
          'Dropbox-API-Arg': jsonEncode({
            'path': path,
            'mode': 'overwrite',
            'autorename': false,
            'mute': true,
          }),
        },
        body: bytes,
      );
      _checkResponse(resp);
    });
  }

  @override
  Future<void> downloadFile(String remotePath, String localPath) async {
    final path = _normalize(remotePath);
    final token = await _accessToken();

    final response = await retryWithBackoff(() async {
      final resp = await _http.post(
        Uri.parse('$_contentBase/files/download'),
        headers: {
          ..._authHeaders(token),
          'Dropbox-API-Arg': jsonEncode({'path': path}),
        },
      );
      _checkResponse(resp);
      return resp;
    });

    await File(localPath).writeAsBytes(response.bodyBytes, flush: true);
  }

  @override
  Future<List<String>> listFiles(String remotePath) async {
    final path = _normalize(remotePath);
    final token = await _accessToken();
    final names = <String>[];
    var hasMore = true;
    String? cursor;

    while (hasMore) {
      final response = await retryWithBackoff(() async {
        final http.Response resp;
        if (cursor == null) {
          resp = await _http.post(
            Uri.parse('$_apiBase/files/list_folder'),
            headers: {
              ..._authHeaders(token),
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'path': path, 'limit': 2000}),
          );
        } else {
          resp = await _http.post(
            Uri.parse('$_apiBase/files/list_folder/continue'),
            headers: {
              ..._authHeaders(token),
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'cursor': cursor}),
          );
        }
        _checkResponse(resp);
        return resp;
      });

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final entries = data['entries'] as List<dynamic>? ?? [];
      for (final entry in entries) {
        names.add((entry as Map<String, dynamic>)['name'] as String);
      }
      hasMore = data['has_more'] as bool? ?? false;
      cursor = data['cursor'] as String?;
    }

    return names;
  }

  @override
  Future<bool> fileExists(String remotePath) async {
    final path = _normalize(remotePath);
    final token = await _accessToken();

    try {
      await retryWithBackoff(() async {
        final resp = await _http.post(
          Uri.parse('$_apiBase/files/get_metadata'),
          headers: {
            ..._authHeaders(token),
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'path': path}),
        );
        _checkResponse(resp);
      });
      return true;
    } on StorageNotFoundException {
      return false;
    }
  }

  @override
  Future<String?> readTextFile(String remotePath) async {
    final path = _normalize(remotePath);
    final token = await _accessToken();

    try {
      final response = await retryWithBackoff(() async {
        final resp = await _http.post(
          Uri.parse('$_contentBase/files/download'),
          headers: {
            ..._authHeaders(token),
            'Dropbox-API-Arg': jsonEncode({'path': path}),
          },
        );
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
    final path = _normalize(remotePath);
    final token = await _accessToken();
    final bytes = utf8.encode(content);

    await retryWithBackoff(() async {
      final resp = await _http.post(
        Uri.parse('$_contentBase/files/upload'),
        headers: {
          ..._authHeaders(token),
          'Content-Type': 'application/octet-stream',
          'Dropbox-API-Arg': jsonEncode({
            'path': path,
            'mode': 'overwrite',
            'autorename': false,
            'mute': true,
          }),
        },
        body: bytes,
      );
      _checkResponse(resp);
    });
  }

  @override
  Future<void> moveFile(String fromPath, String toPath) async {
    final from = _normalize(fromPath);
    final to = _normalize(toPath);
    final token = await _accessToken();

    await retryWithBackoff(() async {
      final resp = await _http.post(
        Uri.parse('$_apiBase/files/move_v2'),
        headers: {
          ..._authHeaders(token),
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'from_path': from,
          'to_path': to,
          'autorename': false,
          'allow_ownership_transfer': false,
        }),
      );
      _checkResponse(resp);
    });
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<String> _accessToken() =>
      _authService.getValidAccessToken(_config);

  Map<String, String> _authHeaders(String token) => {
        'Authorization': 'Bearer $token',
      };

  /// Normalises a logical path for the Dropbox API.
  ///
  /// Dropbox requires paths to start with `/` and uses empty string `""` to
  /// represent the root of the app folder.
  String _normalize(String path) {
    if (path == '/' || path.isEmpty) return '';
    var normalized = path;
    if (!normalized.startsWith('/')) normalized = '/$normalized';
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  /// Extracts the deepest `.tag` value from a Dropbox error response.
  String? _extractErrorTag(Map<String, dynamic> body) {
    try {
      final error = body['error'] as Map<String, dynamic>?;
      if (error == null) return null;
      final path = error['path'] as Map<String, dynamic>?;
      final conflict = path?['.tag'] as String?;
      if (conflict != null) return conflict;
      return error['.tag'] as String?;
    } catch (_) {
      return null;
    }
  }

  void _checkResponse(http.Response response) {
    final code = response.statusCode;
    if (code >= 200 && code < 300) return;

    if (code == 401) {
      throw StorageAuthException(
        'Dropbox authentication failed (HTTP $code).',
        cause: response.body,
      );
    }
    if (code == 409) {
      // Path lookup errors.
      final body =
          jsonDecode(response.body) as Map<String, dynamic>? ?? {};
      final tag = _extractErrorTag(body);
      if (tag == 'not_found') {
        throw StorageNotFoundException(
          'Dropbox resource not found.',
          cause: response.body,
        );
      }
      throw StorageException(
        'Dropbox conflict error (HTTP $code).',
        cause: response.body,
      );
    }
    if (code == 429 || (code >= 500 && code < 600)) {
      throw RetryableHttpException(code, response.body);
    }

    throw StorageException(
      'Dropbox API error (HTTP $code).',
      cause: response.body,
    );
  }
}
