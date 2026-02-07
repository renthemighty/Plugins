/// Box implementation of [StorageProvider].
///
/// Uses OAuth 2.0 Authorization Code + PKCE via [flutter_appauth].
/// Box scopes are managed at the application level in the developer console,
/// so no explicit scope parameter is sent in the authorization request.
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

/// Box Content API base URL.
const String _apiBase = 'https://api.box.com/2.0';

/// Box Upload API base URL.
const String _uploadBase = 'https://upload.box.com/api/2.0';

/// The Box folder ID that represents the root of the user's account.
const String _rootFolderId = '0';

class BoxProvider implements StorageProvider {
  BoxProvider({
    required AuthService authService,
    required SecureTokenStore tokenStore,
    http.Client? httpClient,
  })  : _authService = authService,
        _tokenStore = tokenStore,
        _http = httpClient ?? SecureHttpClient();

  final AuthService _authService;
  final SecureTokenStore _tokenStore;
  final http.Client _http;

  /// Cache of logical path -> Box folder ID.
  final Map<String, String> _folderIdCache = {};

  static const _config = OAuthConfigs.box;

  // ---------------------------------------------------------------------------
  // Auth
  // ---------------------------------------------------------------------------

  @override
  String get providerName => 'Box';

  @override
  Future<void> authenticate() async {
    await _authService.authorize(_config);
  }

  @override
  Future<bool> isAuthenticated() => _authService.isAuthenticated(_config);

  @override
  Future<void> logout() async {
    _folderIdCache.clear();
    await _authService.logout(_config);
  }

  // ---------------------------------------------------------------------------
  // Folder operations
  // ---------------------------------------------------------------------------

  @override
  Future<void> createFolder(String remotePath) async {
    await _ensureFolderChain(remotePath);
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

    final parentPath = _parentOf(remotePath);
    final fileName = _nameOf(remotePath);
    final parentId = await _ensureFolderChain(parentPath);
    final bytes = await file.readAsBytes();

    // Check if file exists -- if so, upload a new version.
    final existingId = await _findFileId(fileName, parentId);

    if (existingId != null) {
      await _uploadNewVersion(existingId, bytes, fileName);
    } else {
      await _uploadNewFile(parentId, bytes, fileName);
    }
  }

  @override
  Future<void> downloadFile(String remotePath, String localPath) async {
    final parentPath = _parentOf(remotePath);
    final fileName = _nameOf(remotePath);
    final parentId = await _resolveFolderId(parentPath);
    if (parentId == null) {
      throw StorageNotFoundException('Folder not found: $parentPath');
    }

    final fileId = await _findFileId(fileName, parentId);
    if (fileId == null) {
      throw StorageNotFoundException('File not found: $remotePath');
    }

    final token = await _accessToken();
    final response = await retryWithBackoff(() async {
      final resp = await _http.get(
        Uri.parse('$_apiBase/files/$fileId/content'),
        headers: _authHeaders(token),
      );
      // Box returns a 302 redirect to the actual download URL.
      // The http package follows redirects automatically.
      _checkResponse(resp);
      return resp;
    });

    await File(localPath).writeAsBytes(response.bodyBytes, flush: true);
  }

  @override
  Future<List<String>> listFiles(String remotePath) async {
    final folderId = await _resolveFolderId(remotePath);
    if (folderId == null) return [];

    final token = await _accessToken();
    final names = <String>[];
    var offset = 0;
    const limit = 1000;

    while (true) {
      final uri = Uri.parse(
        '$_apiBase/folders/$folderId/items'
        '?fields=name&limit=$limit&offset=$offset',
      );

      final response = await retryWithBackoff(() async {
        final resp = await _http.get(uri, headers: _authHeaders(token));
        _checkResponse(resp);
        return resp;
      });

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final entries = data['entries'] as List<dynamic>? ?? [];
      for (final entry in entries) {
        names.add((entry as Map<String, dynamic>)['name'] as String);
      }

      final totalCount = data['total_count'] as int? ?? 0;
      offset += entries.length;
      if (offset >= totalCount) break;
    }

    return names;
  }

  @override
  Future<bool> fileExists(String remotePath) async {
    final parentPath = _parentOf(remotePath);
    final fileName = _nameOf(remotePath);
    final parentId = await _resolveFolderId(parentPath);
    if (parentId == null) return false;
    final fileId = await _findFileId(fileName, parentId);
    return fileId != null;
  }

  @override
  Future<String?> readTextFile(String remotePath) async {
    final parentPath = _parentOf(remotePath);
    final fileName = _nameOf(remotePath);
    final parentId = await _resolveFolderId(parentPath);
    if (parentId == null) return null;

    final fileId = await _findFileId(fileName, parentId);
    if (fileId == null) return null;

    final token = await _accessToken();
    try {
      final response = await retryWithBackoff(() async {
        final resp = await _http.get(
          Uri.parse('$_apiBase/files/$fileId/content'),
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
    final parentPath = _parentOf(remotePath);
    final fileName = _nameOf(remotePath);
    final parentId = await _ensureFolderChain(parentPath);
    final bytes = utf8.encode(content);

    final existingId = await _findFileId(fileName, parentId);
    if (existingId != null) {
      await _uploadNewVersion(existingId, bytes, fileName);
    } else {
      await _uploadNewFile(parentId, bytes, fileName);
    }
  }

  @override
  Future<void> moveFile(String fromPath, String toPath) async {
    final fromParent = _parentOf(fromPath);
    final fromName = _nameOf(fromPath);
    final toParent = _parentOf(toPath);
    final toName = _nameOf(toPath);

    final fromParentId = await _resolveFolderId(fromParent);
    if (fromParentId == null) {
      throw StorageNotFoundException('Source folder not found: $fromParent');
    }

    final fileId = await _findFileId(fromName, fromParentId);
    if (fileId == null) {
      throw StorageNotFoundException('Source file not found: $fromPath');
    }

    final toParentId = await _ensureFolderChain(toParent);
    final token = await _accessToken();

    await retryWithBackoff(() async {
      final resp = await _http.put(
        Uri.parse('$_apiBase/files/$fileId'),
        headers: {
          ..._authHeaders(token),
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'name': toName,
          'parent': {'id': toParentId},
        }),
      );
      _checkResponse(resp);
    });
  }

  // ---------------------------------------------------------------------------
  // Internal: folder resolution
  // ---------------------------------------------------------------------------

  Future<String> _ensureFolderChain(String path) async {
    final segments = _segments(path);
    var parentId = _rootFolderId;

    for (final segment in segments) {
      final cacheKey = '$parentId/$segment';
      if (_folderIdCache.containsKey(cacheKey)) {
        parentId = _folderIdCache[cacheKey]!;
        continue;
      }

      final existingId = await _findSubfolderId(segment, parentId);
      if (existingId != null) {
        _folderIdCache[cacheKey] = existingId;
        parentId = existingId;
      } else {
        final newId = await _createSubfolder(segment, parentId);
        _folderIdCache[cacheKey] = newId;
        parentId = newId;
      }
    }

    return parentId;
  }

  Future<String?> _resolveFolderId(String path) async {
    final segments = _segments(path);
    var parentId = _rootFolderId;

    for (final segment in segments) {
      final cacheKey = '$parentId/$segment';
      if (_folderIdCache.containsKey(cacheKey)) {
        parentId = _folderIdCache[cacheKey]!;
        continue;
      }

      final folderId = await _findSubfolderId(segment, parentId);
      if (folderId == null) return null;
      _folderIdCache[cacheKey] = folderId;
      parentId = folderId;
    }

    return parentId;
  }

  // ---------------------------------------------------------------------------
  // Internal: Box API wrappers
  // ---------------------------------------------------------------------------

  Future<String?> _findSubfolderId(String name, String parentId) async {
    final token = await _accessToken();
    final uri = Uri.parse(
      '$_apiBase/folders/$parentId/items?fields=name,type&limit=1000',
    );

    final response = await retryWithBackoff(() async {
      final resp = await _http.get(uri, headers: _authHeaders(token));
      _checkResponse(resp);
      return resp;
    });

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final entries = data['entries'] as List<dynamic>? ?? [];
    for (final entry in entries) {
      final e = entry as Map<String, dynamic>;
      if (e['type'] == 'folder' && e['name'] == name) {
        return e['id'] as String;
      }
    }
    return null;
  }

  Future<String?> _findFileId(String name, String parentId) async {
    final token = await _accessToken();
    final uri = Uri.parse(
      '$_apiBase/folders/$parentId/items?fields=name,type&limit=1000',
    );

    final response = await retryWithBackoff(() async {
      final resp = await _http.get(uri, headers: _authHeaders(token));
      _checkResponse(resp);
      return resp;
    });

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final entries = data['entries'] as List<dynamic>? ?? [];
    for (final entry in entries) {
      final e = entry as Map<String, dynamic>;
      if (e['type'] == 'file' && e['name'] == name) {
        return e['id'] as String;
      }
    }
    return null;
  }

  Future<String> _createSubfolder(String name, String parentId) async {
    final token = await _accessToken();

    final response = await retryWithBackoff(() async {
      final resp = await _http.post(
        Uri.parse('$_apiBase/folders'),
        headers: {
          ..._authHeaders(token),
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'name': name,
          'parent': {'id': parentId},
        }),
      );
      // 409 means the folder already exists; fetch its ID.
      if (resp.statusCode == 409) {
        final existing = await _findSubfolderId(name, parentId);
        if (existing != null) return resp; // We'll return the ID below.
        _checkResponse(resp);
      }
      _checkResponse(resp);
      return resp;
    });

    if (response.statusCode == 409) {
      // Folder was created concurrently -- fetch its ID.
      final existing = await _findSubfolderId(name, parentId);
      if (existing != null) return existing;
      throw StorageException('Failed to create or find folder: $name');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['id'] as String;
  }

  Future<void> _uploadNewFile(
    String parentId,
    List<int> bytes,
    String fileName,
  ) async {
    final token = await _accessToken();

    final attributes = jsonEncode({
      'name': fileName,
      'parent': {'id': parentId},
    });

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_uploadBase/files/content'),
    )
      ..headers.addAll(_authHeaders(token))
      ..fields['attributes'] = attributes
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName,
      ));

    await retryWithBackoff(() async {
      final streamed = await _http.send(request);
      final resp = await http.Response.fromStream(streamed);
      _checkResponse(resp);
    });
  }

  Future<void> _uploadNewVersion(
    String fileId,
    List<int> bytes,
    String fileName,
  ) async {
    final token = await _accessToken();

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_uploadBase/files/$fileId/content'),
    )
      ..headers.addAll(_authHeaders(token))
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName,
      ));

    await retryWithBackoff(() async {
      final streamed = await _http.send(request);
      final resp = await http.Response.fromStream(streamed);
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

  List<String> _segments(String path) =>
      path.split('/').where((s) => s.isNotEmpty).toList();

  String _parentOf(String path) {
    final parts = _segments(path);
    if (parts.length <= 1) return '/';
    return '/${parts.sublist(0, parts.length - 1).join('/')}';
  }

  String _nameOf(String path) {
    final parts = _segments(path);
    return parts.isEmpty ? '' : parts.last;
  }

  void _checkResponse(http.Response response) {
    final code = response.statusCode;
    if (code >= 200 && code < 300) return;

    if (code == 401) {
      throw StorageAuthException(
        'Box authentication failed (HTTP $code).',
        cause: response.body,
      );
    }
    if (code == 404) {
      throw StorageNotFoundException(
        'Box resource not found (HTTP $code).',
        cause: response.body,
      );
    }
    if (code == 403 && response.body.contains('storage_limit_exceeded')) {
      throw StorageQuotaException(
        'Box storage quota exceeded.',
        cause: response.body,
      );
    }
    if (code == 429 || (code >= 500 && code < 600)) {
      throw RetryableHttpException(code, response.body);
    }

    throw StorageException(
      'Box API error (HTTP $code).',
      cause: response.body,
    );
  }
}
