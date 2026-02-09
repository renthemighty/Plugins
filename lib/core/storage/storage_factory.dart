/// Factory that instantiates the correct [StorageProvider] based on the
/// user's chosen [StorageMode].
///
/// Usage:
/// ```dart
/// final factory = StorageFactory(
///   authService: authService,
///   tokenStore: tokenStore,
///   encryptionService: encryptionService,
/// );
/// final provider = factory.create(StorageMode.googleDrive);
/// await provider.authenticate();
/// ```
library;

import 'package:http/http.dart' as http;

import '../security/auth_service.dart';
import '../security/encryption_service.dart';
import '../security/network_security.dart';
import '../security/secure_token_store.dart';
import 'box_provider.dart';
import 'dropbox_provider.dart';
import 'google_drive_provider.dart';
import 'kira_cloud_provider.dart';
import 'local_encrypted_provider.dart';
import 'onedrive_provider.dart';
import 'storage_provider.dart';

class StorageFactory {
  StorageFactory({
    required AuthService authService,
    required SecureTokenStore tokenStore,
    required EncryptionService encryptionService,
    http.Client? httpClient,
  })  : _authService = authService,
        _tokenStore = tokenStore,
        _encryptionService = encryptionService,
        _httpClient = httpClient;

  final AuthService _authService;
  final SecureTokenStore _tokenStore;
  final EncryptionService _encryptionService;
  final http.Client? _httpClient;

  /// Creates a [StorageProvider] for the given [mode].
  ///
  /// Each call returns a **new** instance.  The caller is responsible for
  /// holding on to it (typically via a Provider/Riverpod/Bloc) and calling
  /// [StorageProvider.authenticate] before performing file operations.
  StorageProvider create(StorageMode mode) {
    switch (mode) {
      case StorageMode.googleDrive:
        return GoogleDriveProvider(
          authService: _authService,
          tokenStore: _tokenStore,
          httpClient: _httpClient ?? SecureHttpClient(),
        );

      case StorageMode.dropbox:
        return DropboxProvider(
          authService: _authService,
          tokenStore: _tokenStore,
          httpClient: _httpClient ?? SecureHttpClient(),
        );

      case StorageMode.oneDrive:
        return OneDriveProvider(
          authService: _authService,
          tokenStore: _tokenStore,
          httpClient: _httpClient ?? SecureHttpClient(),
        );

      case StorageMode.box:
        return BoxProvider(
          authService: _authService,
          tokenStore: _tokenStore,
          httpClient: _httpClient ?? SecureHttpClient(),
        );

      case StorageMode.kiraCloud:
        return KiraCloudProvider(
          tokenStore: _tokenStore,
          httpClient: _httpClient ?? SecureHttpClient(),
        );

      case StorageMode.localEncrypted:
        return LocalEncryptedProvider(
          encryptionService: _encryptionService,
        );
    }
  }

  /// Convenience: returns a human-readable label for the given mode.
  static String labelFor(StorageMode mode) {
    switch (mode) {
      case StorageMode.googleDrive:
        return 'Google Drive';
      case StorageMode.dropbox:
        return 'Dropbox';
      case StorageMode.oneDrive:
        return 'OneDrive';
      case StorageMode.box:
        return 'Box';
      case StorageMode.kiraCloud:
        return 'Kira Cloud';
      case StorageMode.localEncrypted:
        return 'Local Encrypted';
    }
  }

  /// Returns all modes that require a network connection.
  static const List<StorageMode> cloudModes = [
    StorageMode.googleDrive,
    StorageMode.dropbox,
    StorageMode.oneDrive,
    StorageMode.box,
    StorageMode.kiraCloud,
  ];

  /// Returns `true` if [mode] requires network access.
  static bool isCloudMode(StorageMode mode) => cloudModes.contains(mode);
}
