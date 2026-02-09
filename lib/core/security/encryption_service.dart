/// AES-256-GCM encryption service for Kira's local-only storage mode.
///
/// Uses the [pointycastle] library for cryptographic primitives.  Key material
/// is derived from a user-supplied PIN (or a biometric-unlocked secret stored
/// in the platform keystore) using PBKDF2-HMAC-SHA256.
///
/// Every encryption operation generates a fresh random 96-bit IV.  The output
/// format is:
///
/// ```
/// [16-byte salt][12-byte IV][ciphertext + 16-byte GCM tag]
/// ```
///
/// This means the same plaintext encrypted twice produces entirely different
/// ciphertext, and the decryption routine can extract the salt and IV without
/// any external metadata.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';

/// Number of PBKDF2 iterations.  OWASP recommends >= 600 000 for
/// PBKDF2-HMAC-SHA256 as of 2023.  We use 100 000 as a pragmatic trade-off
/// for mobile devices while noting that the key material is also protected
/// by the platform keystore.
const int _kdf2Iterations = 100000;

/// Salt length in bytes.
const int _saltLength = 16;

/// AES-256-GCM nonce (IV) length in bytes.  NIST recommends 96 bits.
const int _ivLength = 12;

/// AES-256 key length in bytes.
const int _keyLength = 32;

/// GCM authentication tag length in bytes.
const int _tagLength = 16;

/// Key used in [FlutterSecureStorage] for the master key.
const String _masterKeyStorageKey = 'kira_encryption_master_key';

class EncryptionService {
  EncryptionService({FlutterSecureStorage? secureStorage})
      : _storage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility:
                    KeychainAccessibility.first_unlock_this_device,
              ),
            );

  final FlutterSecureStorage _storage;
  final Random _secureRandom = Random.secure();

  // ---------------------------------------------------------------------------
  // Key management
  // ---------------------------------------------------------------------------

  /// Derives a 256-bit key from [passphrase] and [salt] using
  /// PBKDF2-HMAC-SHA256.
  Uint8List deriveKey(String passphrase, Uint8List salt) {
    final params = Pbkdf2Parameters(salt, _kdf2Iterations, _keyLength);
    final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))..init(params);
    return kdf.process(Uint8List.fromList(utf8.encode(passphrase)));
  }

  /// Generates a cryptographically random master key, stores it in the
  /// platform keystore, and returns it.
  ///
  /// This is used when the user opts for biometric-only unlock: the master
  /// key lives in the Keychain/Keystore and is released only after a
  /// successful biometric check.
  Future<Uint8List> generateAndStoreMasterKey() async {
    final key = _randomBytes(_keyLength);
    await _storage.write(
      key: _masterKeyStorageKey,
      value: base64Encode(key),
    );
    return key;
  }

  /// Retrieves the master key from the platform keystore.
  ///
  /// Returns `null` if no master key has been generated yet.
  Future<Uint8List?> loadMasterKey() async {
    final encoded = await _storage.read(key: _masterKeyStorageKey);
    if (encoded == null) return null;
    return base64Decode(encoded);
  }

  /// Deletes the master key from the platform keystore.
  Future<void> deleteMasterKey() async {
    await _storage.delete(key: _masterKeyStorageKey);
  }

  // ---------------------------------------------------------------------------
  // Encrypt / decrypt bytes
  // ---------------------------------------------------------------------------

  /// Encrypts [plaintext] with AES-256-GCM using the given [key].
  ///
  /// Output format: `salt ++ iv ++ (ciphertext + tag)`.
  ///
  /// A fresh random salt is generated but is **not** used to derive a sub-key
  /// when a raw key is supplied.  The salt field is reserved for forward
  /// compatibility with passphrase-based encryption where the caller does
  /// `deriveKey(passphrase, salt)`.
  Uint8List encrypt(Uint8List plaintext, Uint8List key) {
    _assertKeyLength(key);

    final salt = _randomBytes(_saltLength);
    final iv = _randomBytes(_ivLength);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true, // encrypt
        AEADParameters(
          KeyParameter(key),
          _tagLength * 8, // tag length in bits
          iv,
          Uint8List(0), // no additional authenticated data
        ),
      );

    final ciphertext = Uint8List(plaintext.length + _tagLength);
    var offset = 0;
    offset += cipher.processBytes(plaintext, 0, plaintext.length, ciphertext, 0);
    cipher.doFinal(ciphertext, offset);

    // Pack: salt + iv + ciphertext_with_tag
    return Uint8List.fromList([...salt, ...iv, ...ciphertext]);
  }

  /// Decrypts data previously encrypted by [encrypt].
  ///
  /// Expects the format `salt ++ iv ++ (ciphertext + tag)`.
  Uint8List decrypt(Uint8List data, Uint8List key) {
    _assertKeyLength(key);

    if (data.length < _saltLength + _ivLength + _tagLength) {
      throw EncryptionException('Data too short to contain a valid payload.');
    }

    // Unpack.
    final salt = data.sublist(0, _saltLength); // reserved
    final iv = data.sublist(_saltLength, _saltLength + _ivLength);
    final ciphertextWithTag = data.sublist(_saltLength + _ivLength);

    // Silence the analyzer -- salt is parsed for forward-compat.
    assert(salt.isNotEmpty);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false, // decrypt
        AEADParameters(
          KeyParameter(key),
          _tagLength * 8,
          iv,
          Uint8List(0),
        ),
      );

    final plaintext = Uint8List(ciphertextWithTag.length - _tagLength);
    var offset = 0;
    offset += cipher.processBytes(
      ciphertextWithTag,
      0,
      ciphertextWithTag.length,
      plaintext,
      0,
    );
    cipher.doFinal(plaintext, offset);

    return plaintext;
  }

  // ---------------------------------------------------------------------------
  // Encrypt / decrypt strings
  // ---------------------------------------------------------------------------

  /// Encrypts a UTF-8 [plaintext] string and returns the result as a
  /// Base64-encoded string.
  String encryptString(String plaintext, Uint8List key) {
    final encrypted = encrypt(Uint8List.fromList(utf8.encode(plaintext)), key);
    return base64Encode(encrypted);
  }

  /// Decrypts a Base64-encoded ciphertext string produced by [encryptString].
  String decryptString(String ciphertext, Uint8List key) {
    final data = base64Decode(ciphertext);
    final decrypted = decrypt(data, key);
    return utf8.decode(decrypted);
  }

  // ---------------------------------------------------------------------------
  // Encrypt / decrypt files
  // ---------------------------------------------------------------------------

  /// Encrypts the file at [inputPath] and writes the result to [outputPath].
  Future<void> encryptFile(
    String inputPath,
    String outputPath,
    Uint8List key,
  ) async {
    final inputFile = File(inputPath);
    if (!(await inputFile.exists())) {
      throw EncryptionException('Input file does not exist: $inputPath');
    }

    final plaintext = await inputFile.readAsBytes();
    final ciphertext = encrypt(Uint8List.fromList(plaintext), key);
    await File(outputPath).writeAsBytes(ciphertext, flush: true);
  }

  /// Decrypts the file at [inputPath] and writes the result to [outputPath].
  Future<void> decryptFile(
    String inputPath,
    String outputPath,
    Uint8List key,
  ) async {
    final inputFile = File(inputPath);
    if (!(await inputFile.exists())) {
      throw EncryptionException('Input file does not exist: $inputPath');
    }

    final ciphertext = await inputFile.readAsBytes();
    final plaintext = decrypt(Uint8List.fromList(ciphertext), key);
    await File(outputPath).writeAsBytes(plaintext, flush: true);
  }

  // ---------------------------------------------------------------------------
  // Passphrase-based convenience methods
  // ---------------------------------------------------------------------------

  /// Encrypts [plaintext] using a key derived from [passphrase].
  ///
  /// The randomly generated salt is embedded in the output so that
  /// [decryptWithPassphrase] can recover it.
  Uint8List encryptWithPassphrase(Uint8List plaintext, String passphrase) {
    final salt = _randomBytes(_saltLength);
    final key = deriveKey(passphrase, salt);

    final iv = _randomBytes(_ivLength);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(
          KeyParameter(key),
          _tagLength * 8,
          iv,
          Uint8List(0),
        ),
      );

    final ciphertext = Uint8List(plaintext.length + _tagLength);
    var offset = 0;
    offset +=
        cipher.processBytes(plaintext, 0, plaintext.length, ciphertext, 0);
    cipher.doFinal(ciphertext, offset);

    return Uint8List.fromList([...salt, ...iv, ...ciphertext]);
  }

  /// Decrypts data encrypted by [encryptWithPassphrase].
  Uint8List decryptWithPassphrase(Uint8List data, String passphrase) {
    if (data.length < _saltLength + _ivLength + _tagLength) {
      throw EncryptionException('Data too short to contain a valid payload.');
    }

    final salt = data.sublist(0, _saltLength);
    final iv = data.sublist(_saltLength, _saltLength + _ivLength);
    final ciphertextWithTag = data.sublist(_saltLength + _ivLength);

    final key = deriveKey(passphrase, salt);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(
          KeyParameter(key),
          _tagLength * 8,
          iv,
          Uint8List(0),
        ),
      );

    final plaintext = Uint8List(ciphertextWithTag.length - _tagLength);
    var offset = 0;
    offset += cipher.processBytes(
      ciphertextWithTag,
      0,
      ciphertextWithTag.length,
      plaintext,
      0,
    );
    cipher.doFinal(plaintext, offset);

    return plaintext;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Uint8List _randomBytes(int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = _secureRandom.nextInt(256);
    }
    return bytes;
  }

  static void _assertKeyLength(Uint8List key) {
    if (key.length != _keyLength) {
      throw EncryptionException(
        'Key must be exactly $_keyLength bytes (got ${key.length}).',
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Exceptions
// ---------------------------------------------------------------------------

class EncryptionException implements Exception {
  final String message;
  const EncryptionException(this.message);

  @override
  String toString() => 'EncryptionException: $message';
}
