/// Microsoft OneDrive implementation of [StorageProvider].
///
/// Uses OAuth 2.0 Authorization Code + PKCE via [flutter_appauth] against
/// the Microsoft identity platform v2.0 endpoints.
///
/// Scopes requested:
/// - `Files.ReadWrite.AppFolder` -- least privilege; limits access to the
///   application's own folder within the user's OneDrive.
/// - `offline_access` -- needed to receive a refresh token.
///
/// All HTTP calls enforce HTTPS and use [retryWithBackoff].
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

/// Microsoft Graph API base URL.
const String _graphBase = 'https://graph.microsoft.com/v1.0';

/// The special folder path for the app's dedicated folder in OneDrive.
const String _appRoot = '$_graphBase/me/drive/special/approot';

class OneDriveProvider implements StorageProvider {
  OneDriveProvider({
    required AuthService authService,
    required SecureTokenStore tokenStore,
    http.Client? httpClient,
  })  : _authService = authService,
        _tokenStore = tokenStore,
        _http = httpClient ?? SecureHttpClient();

  final AuthService _authService;
  final SecureTokenStore _tokenStore;
  final http.Client _http;

  static const _config = OAuthConfigs.oneDrive;

  // ---------------------------------------------------------------------------
  // Auth
  // ---------------------------------------------------------------------------

  @override
  String get providerName => 'OneDrive';

  @override
  Future<void> authenticate() async {
    await _authService.authorize(_config);
  }

  @override
  Future<bool> isAuthenticated() => _authService.isAuthenticated(_config);

  @override
  Future<void> logout() async {
    // Microsoft does not expose a token revocation endpoint.
    // We clear local tokens only.
    await _authService.logout(_config);
  }

  // ---------------------------------------------------------------------------
  // Folder operations
  // ---------------------------------------------------------------------------

  @override
  Future<void> createFolder(String remotePath) async {
    final segments = _segments(remotePath);
    if (segments.isEmpty) return;

    // Walk the segments and create each one if missing.
    var currentPath = '';
    for (final segment in segments) {
      currentPath = '$currentPath/$segment';
      await _createSingleFolder(currentPath, segment);
    }
  }

  Future<void> _createSingleFolder(String fullPath, String name) async {
    final parentPath = _parentDrivePath(fullPath);
    final token = await _accessToken();

    final uri = parentPath.isEmpty
        ? Uri.parse('$_appRoot/children')
        : Uri.parse('$_appRoot:/$parentPath:/children');

    try {
      await retryWithBackoff(() async {
        final resp = await _http.post(
          uri,
          headers: {
            ..._authHeaders(token),
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'name': name,
            'folder': <String, dynamic>{},
            '@microsoft.graph.conflictBehavior': 'fail',
          }),
        );

        // 409 Conflict means the folder already exists -- that's fine.
        if (resp.statusCode == 409) return;
        _checkResponse(resp);
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
    final drivePath = _drivePath(remotePath);
    final token = await _accessToken();

    // Simple upload for files <= 4 MB.  For larger files a resumable upload
    // session should be used (future enhancement).
    await retryWithBackoff(() async {
      final resp = await _http.put(
        Uri.parse('$_appRoot:/$drivePath:/content'),
        headers: {
          ..._authHeaders(token),
          'Content-Type': 'application/octet-stream',
        },
        body: bytes,
      );
      _checkResponse(resp);
    });
  }

  @override
  Future<void> downloadFile(String remotePath, String localPath) async {
    final drivePath = _drivePath(remotePath);
    final token = await _accessToken();

    final response = await retryWithBackoff(() async {
      final resp = await _http.get(
        Uri.parse('$_appRoot:/$drivePath:/content'),
        headers: _authHeaders(token),
      );
      _checkResponse(resp);
      return resp;
    });

    await File(localPath).writeAsBytes(response.bodyBytes, flush: true);
  }

  @override
  Future<List<String>> listFiles(String remotePath) async {
    final drivePath = _drivePath(remotePath);
    final token = await _accessToken();

    final uri = drivePath.isEmpty
        ? Uri.parse('$_appRoot/children?\$select=name')
        : Uri.parse('$_appRoot:/$drivePath:/children?\$select=name');

    final names = <String>[];
    var nextLink = uri.toString();

    while (nextLink.isNotEmpty) {
      final response = await retryWithBackoff(() async {
        final resp = await _http.get(
          Uri.parse(nextLink),
          headers: _authHeaders(token),
        );
        _checkResponse(resp);
        return resp;
      });

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final items = data['value'] as List<dynamic>? ?? [];
      for (final item in items) {
        names.add((item as Map<String, dynamic>)['name'] as String);
      }
      nextLink = (data['@odata.nextLink'] as String?) ?? '';
    }

    return names;
  }

  @override
  Future<bool> fileExists(String remotePath) async {
    final drivePath = _drivePath(remotePath);
    final token = await _accessToken();

    try {
      await retryWithBackoff(() async {
        final resp = await _http.get(
          Uri.parse('$_appRoot:/$drivePath'),
          headers: _authHeaders(token),
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
    final drivePath = _drivePath(remotePath);
    final token = await _accessToken();

    try {
      final response = await retryWithBackoff(() async {
        final resp = await _http.get(
          Uri.parse('$_appRoot:/$drivePath:/content'),
          headers: _authHeaders(token),
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
    final drivePath = _drivePath(remotePath);
    final token = await _accessToken();
    final bytes = utf8.encode(content);

    await retryWithBackoff(() async {
      final resp = await _http.put(
        Uri.parse('$_appRoot:/$drivePath:/content'),
        headers: {
          ..._authHeaders(token),
          'Content-Type': 'text/plain; charset=utf-8',
        },
        body: bytes,
      );
      _checkResponse(resp);
    });
  }

  @override
  Future<void> moveFile(String fromPath, String toPath) async {
    final fromDrivePath = _drivePath(fromPath);
    final toParent = _parentDrivePath(_drivePath(toPath));
    final toName = _nameOf(toPath);
    final token = await _accessToken();

    await retryWithBackoff(() async {
      final resp = await _http.patch(
        Uri.parse('$_appRoot:/$fromDrivePath'),
        headers: {
          ..._authHeaders(token),
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'name': toName,
          if (toParent.isNotEmpty)
            'parentReference': {
              'path': '/drive/special/approot:/$toParent',
            },
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

  /// Converts a logical Kira path to a drive-item path segment suitable for
  /// the Graph API `approot:/<path>:` pattern.
  String _drivePath(String path) {
    final segs = _segments(path);
    return segs.join('/');
  }

  /// Returns the parent portion of a drive path.
  String _parentDrivePath(String drivePath) {
    final segs = drivePath.split('/').where((s) => s.isNotEmpty).toList();
    if (segs.length <= 1) return '';
    return segs.sublist(0, segs.length - 1).join('/');
  }

  List<String> _segments(String path) =>
      path.split('/').where((s) => s.isNotEmpty).toList();

  String _nameOf(String path) {
    final parts = _segments(path);
    return parts.isEmpty ? '' : parts.last;
  }

  void _checkResponse(http.Response response) {
    final code = response.statusCode;
    if (code >= 200 && code < 300) return;

    if (code == 401) {
      throw StorageAuthException(
        'OneDrive authentication failed (HTTP $code).',
        cause: response.body,
      );
    }
    if (code == 404) {
      throw StorageNotFoundException(
        'OneDrive resource not found (HTTP $code).',
        cause: response.body,
      );
    }
    if (code == 507) {
      throw StorageQuotaException(
        'OneDrive storage quota exceeded.',
        cause: response.body,
      );
    }
    if (code == 429 || (code >= 500 && code < 600)) {
      throw RetryableHttpException(code, response.body);
    }

    throw StorageException(
      'OneDrive API error (HTTP $code).',
      cause: response.body,
    );
  }
}
