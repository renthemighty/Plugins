/// Google Drive implementation of [StorageProvider].
///
/// Uses OAuth 2.0 Authorization Code + PKCE via [flutter_appauth].  The only
/// scope requested is `drive.file` (least privilege -- limits access to files
/// created by this app).
///
/// All HTTP calls go through [SecureHttpClient] which enforces HTTPS, and
/// every API call is wrapped in [retryWithBackoff] for transient-failure
/// resilience.
///
/// **No client secret is embedded in the binary.**  The client ID is injected
/// at build time via `--dart-define=GOOGLE_DRIVE_CLIENT_ID=...`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../security/auth_service.dart';
import '../security/network_security.dart';
import '../security/secure_token_store.dart';
import 'storage_provider.dart';

/// Base URL for the Google Drive REST API v3.
const String _driveApiBase = 'https://www.googleapis.com/drive/v3';

/// Base URL for the Google Drive file-upload endpoint.
const String _uploadApiBase = 'https://www.googleapis.com/upload/drive/v3';

/// The MIME type Google Drive uses for folders.
const String _folderMimeType = 'application/vnd.google-apps.folder';

class GoogleDriveProvider implements StorageProvider {
  GoogleDriveProvider({
    required AuthService authService,
    required SecureTokenStore tokenStore,
    http.Client? httpClient,
  })  : _authService = authService,
        _tokenStore = tokenStore,
        _http = httpClient ?? SecureHttpClient();

  final AuthService _authService;
  final SecureTokenStore _tokenStore;
  final http.Client _http;

  /// Cache of path-segment -> Google Drive file ID so we don't resolve the
  /// same folder repeatedly within a single session.
  final Map<String, String> _idCache = {};

  static const _config = OAuthConfigs.googleDrive;

  // ---------------------------------------------------------------------------
  // StorageProvider -- auth
  // ---------------------------------------------------------------------------

  @override
  String get providerName => 'Google Drive';

  @override
  Future<void> authenticate() async {
    await _authService.authorize(_config);
  }

  @override
  Future<bool> isAuthenticated() => _authService.isAuthenticated(_config);

  @override
  Future<void> logout() async {
    _idCache.clear();
    await _authService.logout(_config);
  }

  // ---------------------------------------------------------------------------
  // StorageProvider -- folder operations
  // ---------------------------------------------------------------------------

  @override
  Future<void> createFolder(String remotePath) async {
    await _ensureFolderChain(remotePath);
  }

  // ---------------------------------------------------------------------------
  // StorageProvider -- file operations
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

    // Check for existing file to overwrite.
    final existingId = await _findFileId(fileName, parentId);

    final bytes = await file.readAsBytes();

    if (existingId != null) {
      await _updateFileContent(existingId, bytes);
    } else {
      await _createFileWithContent(fileName, parentId, bytes);
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
        Uri.parse('$_driveApiBase/files/$fileId?alt=media'),
        headers: _authHeaders(token),
      );
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
    final query = "'$folderId' in parents and trashed = false";
    final uri = Uri.parse('$_driveApiBase/files').replace(
      queryParameters: {
        'q': query,
        'fields': 'files(name)',
        'pageSize': '1000',
      },
    );

    final response = await retryWithBackoff(() async {
      final resp = await _http.get(uri, headers: _authHeaders(token));
      _checkResponse(resp);
      return resp;
    });

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final files = data['files'] as List<dynamic>? ?? [];
    return files
        .map((f) => (f as Map<String, dynamic>)['name'] as String)
        .toList();
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
    final response = await retryWithBackoff(() async {
      final resp = await _http.get(
        Uri.parse('$_driveApiBase/files/$fileId?alt=media'),
        headers: _authHeaders(token),
      );
      if (resp.statusCode == 404) return resp;
      _checkResponse(resp);
      return resp;
    });

    if (response.statusCode == 404) return null;
    return response.body;
  }

  @override
  Future<void> writeTextFile(String remotePath, String content) async {
    final parentPath = _parentOf(remotePath);
    final fileName = _nameOf(remotePath);
    final parentId = await _ensureFolderChain(parentPath);

    final existingId = await _findFileId(fileName, parentId);
    final bytes = utf8.encode(content);

    if (existingId != null) {
      await _updateFileContent(existingId, bytes);
    } else {
      await _createFileWithContent(fileName, parentId, bytes);
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

    // Move and rename in one PATCH request.
    final uri = Uri.parse('$_driveApiBase/files/$fileId').replace(
      queryParameters: {
        'addParents': toParentId,
        'removeParents': fromParentId,
      },
    );

    await retryWithBackoff(() async {
      final resp = await _http.patch(
        uri,
        headers: {
          ..._authHeaders(token),
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'name': toName}),
      );
      _checkResponse(resp);
    });
  }

  // ---------------------------------------------------------------------------
  // Internal: folder resolution
  // ---------------------------------------------------------------------------

  /// Resolves a logical path like `/receipts/2025/06` to its Google Drive
  /// folder ID, creating any missing folders along the way.
  ///
  /// Returns the ID of the deepest folder.
  Future<String> _ensureFolderChain(String path) async {
    final segments = _segments(path);
    var parentId = 'root';

    for (final segment in segments) {
      final cacheKey = '$parentId/$segment';
      if (_idCache.containsKey(cacheKey)) {
        parentId = _idCache[cacheKey]!;
        continue;
      }

      final existingId = await _findFolderId(segment, parentId);
      if (existingId != null) {
        _idCache[cacheKey] = existingId;
        parentId = existingId;
      } else {
        final newId = await _createFolder(segment, parentId);
        _idCache[cacheKey] = newId;
        parentId = newId;
      }
    }

    return parentId;
  }

  /// Resolves a logical path to its Google Drive folder ID, returning `null`
  /// if any segment is missing.
  Future<String?> _resolveFolderId(String path) async {
    final segments = _segments(path);
    var parentId = 'root';

    for (final segment in segments) {
      final cacheKey = '$parentId/$segment';
      if (_idCache.containsKey(cacheKey)) {
        parentId = _idCache[cacheKey]!;
        continue;
      }

      final folderId = await _findFolderId(segment, parentId);
      if (folderId == null) return null;
      _idCache[cacheKey] = folderId;
      parentId = folderId;
    }

    return parentId;
  }

  // ---------------------------------------------------------------------------
  // Internal: Drive API wrappers
  // ---------------------------------------------------------------------------

  Future<String?> _findFolderId(String name, String parentId) async {
    final token = await _accessToken();
    final query = "name = '$name' and '$parentId' in parents "
        "and mimeType = '$_folderMimeType' and trashed = false";
    final uri = Uri.parse('$_driveApiBase/files').replace(
      queryParameters: {'q': query, 'fields': 'files(id)', 'pageSize': '1'},
    );

    final response = await retryWithBackoff(() async {
      final resp = await _http.get(uri, headers: _authHeaders(token));
      _checkResponse(resp);
      return resp;
    });

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final files = data['files'] as List<dynamic>?;
    if (files == null || files.isEmpty) return null;
    return (files.first as Map<String, dynamic>)['id'] as String;
  }

  Future<String?> _findFileId(String name, String parentId) async {
    final token = await _accessToken();
    final query = "name = '$name' and '$parentId' in parents "
        "and mimeType != '$_folderMimeType' and trashed = false";
    final uri = Uri.parse('$_driveApiBase/files').replace(
      queryParameters: {'q': query, 'fields': 'files(id)', 'pageSize': '1'},
    );

    final response = await retryWithBackoff(() async {
      final resp = await _http.get(uri, headers: _authHeaders(token));
      _checkResponse(resp);
      return resp;
    });

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final files = data['files'] as List<dynamic>?;
    if (files == null || files.isEmpty) return null;
    return (files.first as Map<String, dynamic>)['id'] as String;
  }

  Future<String> _createFolder(String name, String parentId) async {
    final token = await _accessToken();
    final metadata = {
      'name': name,
      'mimeType': _folderMimeType,
      'parents': [parentId],
    };

    final response = await retryWithBackoff(() async {
      final resp = await _http.post(
        Uri.parse('$_driveApiBase/files'),
        headers: {
          ..._authHeaders(token),
          'Content-Type': 'application/json',
        },
        body: jsonEncode(metadata),
      );
      _checkResponse(resp);
      return resp;
    });

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['id'] as String;
  }

  Future<void> _createFileWithContent(
    String name,
    String parentId,
    List<int> bytes,
  ) async {
    final token = await _accessToken();
    final metadata = jsonEncode({
      'name': name,
      'parents': [parentId],
    });

    // Multipart upload for simplicity.  For files > 5 MB a resumable upload
    // would be preferred; that can be added as a future enhancement.
    final boundary = 'kira_boundary_${DateTime.now().millisecondsSinceEpoch}';
    final body = [
      '--$boundary\r\n',
      'Content-Type: application/json; charset=UTF-8\r\n\r\n',
      '$metadata\r\n',
      '--$boundary\r\n',
      'Content-Type: application/octet-stream\r\n\r\n',
    ].join();

    final bodyBytes = [
      ...utf8.encode(body),
      ...bytes,
      ...utf8.encode('\r\n--$boundary--'),
    ];

    await retryWithBackoff(() async {
      final resp = await _http.post(
        Uri.parse(
          '$_uploadApiBase/files?uploadType=multipart',
        ),
        headers: {
          ..._authHeaders(token),
          'Content-Type': 'multipart/related; boundary=$boundary',
          'Content-Length': bodyBytes.length.toString(),
        },
        body: bodyBytes,
      );
      _checkResponse(resp);
    });
  }

  Future<void> _updateFileContent(String fileId, List<int> bytes) async {
    final token = await _accessToken();

    await retryWithBackoff(() async {
      final resp = await _http.patch(
        Uri.parse(
          '$_uploadApiBase/files/$fileId?uploadType=media',
        ),
        headers: {
          ..._authHeaders(token),
          'Content-Type': 'application/octet-stream',
        },
        body: bytes,
      );
      _checkResponse(resp);
    });
  }

  // ---------------------------------------------------------------------------
  // Internal: helpers
  // ---------------------------------------------------------------------------

  Future<String> _accessToken() =>
      _authService.getValidAccessToken(_config);

  Map<String, String> _authHeaders(String token) => {
        'Authorization': 'Bearer $token',
      };

  /// Splits a logical path into non-empty segments.
  List<String> _segments(String path) =>
      path.split('/').where((s) => s.isNotEmpty).toList();

  /// Returns the parent directory portion of a path.
  String _parentOf(String path) {
    final parts = _segments(path);
    if (parts.length <= 1) return '/';
    return '/${parts.sublist(0, parts.length - 1).join('/')}';
  }

  /// Returns the file/folder name at the end of a path.
  String _nameOf(String path) {
    final parts = _segments(path);
    return parts.isEmpty ? '' : parts.last;
  }

  /// Inspects an HTTP response and throws appropriate exceptions for
  /// non-success status codes.
  void _checkResponse(http.Response response) {
    final code = response.statusCode;
    if (code >= 200 && code < 300) return;

    if (code == 401) {
      throw StorageAuthException(
        'Google Drive authentication failed (HTTP $code).',
        cause: response.body,
      );
    }
    if (code == 404) {
      throw StorageNotFoundException(
        'Google Drive resource not found (HTTP $code).',
        cause: response.body,
      );
    }
    if (code == 403 && response.body.contains('storageQuotaExceeded')) {
      throw StorageQuotaException(
        'Google Drive storage quota exceeded.',
        cause: response.body,
      );
    }
    if (code == 429 || (code >= 500 && code < 600)) {
      throw RetryableHttpException(code, response.body);
    }

    throw StorageException(
      'Google Drive API error (HTTP $code).',
      cause: response.body,
    );
  }
}
