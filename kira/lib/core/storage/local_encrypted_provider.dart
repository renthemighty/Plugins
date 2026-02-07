/// Local-only encrypted storage provider.
///
/// All data stays on-device.  Files are encrypted at rest with AES-256-GCM
/// using a key derived from the user's PIN (via PBKDF2) or unlocked from the
/// platform keystore after biometric authentication.
///
/// This provider implements the full [StorageProvider] interface but maps
/// every "remote" path to a directory inside the app's sandboxed documents
/// folder.  No network calls are made.
///
/// ## Directory layout
///
/// ```
/// <appDocDir>/kira_encrypted/
///   receipts/
///     2025/
///       06/
///         14/
///           receipt_abc123.jpg.enc
///   index/
///     months/
///       2025-06.json.enc
/// ```
///
/// Each `.enc` file contains the output of [EncryptionService.encrypt]:
/// `salt ++ iv ++ (ciphertext + GCM tag)`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../security/encryption_service.dart';
import 'storage_provider.dart';

/// File extension appended to encrypted files.
const String _encryptedExtension = '.enc';

class LocalEncryptedProvider implements StorageProvider {
  LocalEncryptedProvider({
    required EncryptionService encryptionService,
  }) : _encryption = encryptionService;

  final EncryptionService _encryption;

  /// The AES-256 key used for all encrypt/decrypt operations.
  ///
  /// Must be set before any file operation by calling [unlock].
  Uint8List? _key;

  /// Whether the provider has been unlocked for the current session.
  bool get isUnlocked => _key != null;

  // ---------------------------------------------------------------------------
  // Auth / unlock
  // ---------------------------------------------------------------------------

  @override
  String get providerName => 'Local Encrypted';

  /// Unlocks the provider with a key derived from the user's [pin].
  ///
  /// The salt is stored alongside the encrypted root so that the same PIN
  /// always produces the same key.
  Future<void> unlockWithPin(String pin) async {
    final root = await _rootDir();
    final saltFile = File(p.join(root.path, '.salt'));

    Uint8List salt;
    if (await saltFile.exists()) {
      salt = await saltFile.readAsBytes();
    } else {
      // First-time setup: generate a random salt.
      salt = _encryption.deriveKey('', Uint8List(16)); // temporary to get length
      // Actually generate a proper random salt.
      final tempKey = _encryption.encryptString('salt_probe', _zeroKey());
      // Use the first 16 bytes of a random encryption output as salt.
      final randomBytes = base64Decode(tempKey);
      salt = Uint8List.fromList(randomBytes.sublist(0, 16));
      await root.create(recursive: true);
      await saltFile.writeAsBytes(salt, flush: true);
    }

    _key = _encryption.deriveKey(pin, salt);
  }

  /// Unlocks the provider using a master key stored in the platform keystore
  /// (released after biometric authentication).
  Future<void> unlockWithMasterKey() async {
    final masterKey = await _encryption.loadMasterKey();
    if (masterKey == null) {
      throw StorageException(
        'No master key found. Set up local encryption first.',
      );
    }
    _key = masterKey;
  }

  /// Generates a new master key and stores it in the platform keystore.
  ///
  /// This is called during initial setup when the user chooses biometric
  /// unlock.
  Future<void> setupMasterKey() async {
    _key = await _encryption.generateAndStoreMasterKey();
  }

  /// For the [StorageProvider] contract, [authenticate] unlocks with the
  /// master key (biometric path).  Callers who want PIN-based unlock should
  /// call [unlockWithPin] directly.
  @override
  Future<void> authenticate() async {
    await unlockWithMasterKey();
  }

  @override
  Future<bool> isAuthenticated() async => isUnlocked;

  @override
  Future<void> logout() async {
    _key = null;
  }

  // ---------------------------------------------------------------------------
  // Folder operations
  // ---------------------------------------------------------------------------

  @override
  Future<void> createFolder(String remotePath) async {
    final dir = await _resolveDir(remotePath);
    if (!(await dir.exists())) {
      await dir.create(recursive: true);
    }
  }

  // ---------------------------------------------------------------------------
  // File operations
  // ---------------------------------------------------------------------------

  @override
  Future<void> uploadFile(String localPath, String remotePath) async {
    _assertUnlocked();

    final sourceFile = File(localPath);
    if (!(await sourceFile.exists())) {
      throw StorageException('Local file does not exist: $localPath');
    }

    final destFile = await _resolveFile(remotePath);
    await destFile.parent.create(recursive: true);

    await _encryption.encryptFile(localPath, destFile.path, _key!);
  }

  @override
  Future<void> downloadFile(String remotePath, String localPath) async {
    _assertUnlocked();

    final sourceFile = await _resolveFile(remotePath);
    if (!(await sourceFile.exists())) {
      throw StorageNotFoundException('File not found: $remotePath');
    }

    final destDir = Directory(p.dirname(localPath));
    if (!(await destDir.exists())) {
      await destDir.create(recursive: true);
    }

    await _encryption.decryptFile(sourceFile.path, localPath, _key!);
  }

  @override
  Future<List<String>> listFiles(String remotePath) async {
    final dir = await _resolveDir(remotePath);
    if (!(await dir.exists())) return [];

    final entities = await dir.list().toList();
    final names = <String>[];

    for (final entity in entities) {
      var name = p.basename(entity.path);
      // Strip the .enc extension for the caller.
      if (name.endsWith(_encryptedExtension)) {
        name = name.substring(
          0,
          name.length - _encryptedExtension.length,
        );
      }
      names.add(name);
    }

    return names;
  }

  @override
  Future<bool> fileExists(String remotePath) async {
    final file = await _resolveFile(remotePath);
    return file.exists();
  }

  @override
  Future<String?> readTextFile(String remotePath) async {
    _assertUnlocked();

    final file = await _resolveFile(remotePath);
    if (!(await file.exists())) return null;

    final ciphertext = await file.readAsBytes();
    try {
      final plaintext = _encryption.decrypt(
        Uint8List.fromList(ciphertext),
        _key!,
      );
      return utf8.decode(plaintext);
    } on EncryptionException catch (e) {
      throw StorageException(
        'Failed to decrypt file: $remotePath',
        cause: e,
      );
    }
  }

  @override
  Future<void> writeTextFile(String remotePath, String content) async {
    _assertUnlocked();

    final file = await _resolveFile(remotePath);
    await file.parent.create(recursive: true);

    final plaintext = Uint8List.fromList(utf8.encode(content));
    final ciphertext = _encryption.encrypt(plaintext, _key!);
    await file.writeAsBytes(ciphertext, flush: true);
  }

  @override
  Future<void> moveFile(String fromPath, String toPath) async {
    final fromFile = await _resolveFile(fromPath);
    if (!(await fromFile.exists())) {
      throw StorageNotFoundException('Source file not found: $fromPath');
    }

    final toFile = await _resolveFile(toPath);
    await toFile.parent.create(recursive: true);

    await fromFile.rename(toFile.path);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Returns the root directory for encrypted storage.
  Future<Directory> _rootDir() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    return Directory(p.join(appDocDir.path, 'kira_encrypted'));
  }

  /// Maps a logical "remote" path to a local [Directory].
  Future<Directory> _resolveDir(String remotePath) async {
    final root = await _rootDir();
    final segments = remotePath.split('/').where((s) => s.isNotEmpty);
    return Directory(p.joinAll([root.path, ...segments]));
  }

  /// Maps a logical "remote" path to a local encrypted [File].
  ///
  /// Appends [_encryptedExtension] so that the on-disk name clearly
  /// indicates the file is encrypted.
  Future<File> _resolveFile(String remotePath) async {
    final root = await _rootDir();
    final segments = remotePath.split('/').where((s) => s.isNotEmpty).toList();
    final relativePath = p.joinAll(segments);
    return File(p.join(root.path, '$relativePath$_encryptedExtension'));
  }

  void _assertUnlocked() {
    if (_key == null) {
      throw StorageAuthException(
        'Local encrypted storage is locked. Call authenticate() or '
        'unlockWithPin() first.',
      );
    }
  }

  /// Returns a zero-filled 32-byte key.  Used only during initial salt
  /// generation -- never for real encryption.
  static Uint8List _zeroKey() => Uint8List(32);
}
