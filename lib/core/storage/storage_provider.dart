/// Abstract contract for all Kira storage backends.
///
/// Every cloud provider (Google Drive, Dropbox, OneDrive, Box, Kira Cloud)
/// and the local-only encrypted provider implement this interface so that the
/// rest of the app can read/write receipts without knowing which backend is
/// active.
///
/// ## Path conventions
///
/// All `remotePath` arguments use POSIX-style forward-slash paths relative to
/// the Kira root folder inside the provider.  For example:
///
/// ```
/// /receipts/2025/06/14/receipt_abc123.jpg
/// /index/months/2025-06.json
/// ```
///
/// Each provider maps these logical paths to whatever the underlying API
/// requires (Google Drive file IDs, Dropbox namespace paths, etc.).
///
/// ## Error handling
///
/// Implementations should throw [StorageException] for all recoverable errors
/// and let truly fatal errors (e.g. [OutOfMemoryError]) propagate naturally.
library;

/// The set of supported storage backends.
enum StorageMode {
  googleDrive,
  dropbox,
  oneDrive,
  box,
  kiraCloud,
  localEncrypted,
}

/// The interface that every storage backend must implement.
abstract class StorageProvider {
  /// Initiates the authentication flow (OAuth, passkey, etc.).
  ///
  /// After a successful call, [isAuthenticated] must return `true`.
  Future<void> authenticate();

  /// Returns `true` when the provider has valid credentials that can be used
  /// to make API calls (refreshing tokens transparently if needed).
  Future<bool> isAuthenticated();

  /// Signs out of the provider, revoking tokens where possible and clearing
  /// local credential storage.
  Future<void> logout();

  /// Creates a folder (and any missing ancestors) at [remotePath].
  ///
  /// No-op if the folder already exists.
  Future<void> createFolder(String remotePath);

  /// Uploads the file at [localPath] to [remotePath], overwriting any
  /// existing file at that location.
  Future<void> uploadFile(String localPath, String remotePath);

  /// Downloads the file at [remotePath] to [localPath], overwriting any
  /// existing local file.
  Future<void> downloadFile(String remotePath, String localPath);

  /// Lists immediate children of the folder at [remotePath].
  ///
  /// Returns a list of relative names (not full paths).  For files the name
  /// includes the extension; for folders it is just the folder name.
  Future<List<String>> listFiles(String remotePath);

  /// Returns `true` when a file (not folder) exists at [remotePath].
  Future<bool> fileExists(String remotePath);

  /// Reads the UTF-8 text content of the file at [remotePath].
  ///
  /// Returns `null` if the file does not exist.
  Future<String?> readTextFile(String remotePath);

  /// Writes [content] as a UTF-8 text file at [remotePath], creating or
  /// overwriting as needed.
  Future<void> writeTextFile(String remotePath, String content);

  /// Atomically moves (renames) a file from [fromPath] to [toPath].
  Future<void> moveFile(String fromPath, String toPath);

  /// A human-readable name for this provider (e.g. `"Google Drive"`).
  String get providerName;
}

// ---------------------------------------------------------------------------
// Exceptions
// ---------------------------------------------------------------------------

/// Base exception for all storage operations.
class StorageException implements Exception {
  final String message;
  final Object? cause;

  const StorageException(this.message, {this.cause});

  @override
  String toString() {
    final buffer = StringBuffer('StorageException: $message');
    if (cause != null) {
      buffer.write(' (caused by: $cause)');
    }
    return buffer.toString();
  }
}

/// Thrown when an operation is attempted without valid authentication.
class StorageAuthException extends StorageException {
  const StorageAuthException(super.message, {super.cause});

  @override
  String toString() {
    final buffer = StringBuffer('StorageAuthException: $message');
    if (cause != null) {
      buffer.write(' (caused by: $cause)');
    }
    return buffer.toString();
  }
}

/// Thrown when a file or folder is not found.
class StorageNotFoundException extends StorageException {
  const StorageNotFoundException(super.message, {super.cause});

  @override
  String toString() {
    final buffer = StringBuffer('StorageNotFoundException: $message');
    if (cause != null) {
      buffer.write(' (caused by: $cause)');
    }
    return buffer.toString();
  }
}

/// Thrown when the storage quota has been exceeded.
class StorageQuotaException extends StorageException {
  const StorageQuotaException(super.message, {super.cause});

  @override
  String toString() {
    final buffer = StringBuffer('StorageQuotaException: $message');
    if (cause != null) {
      buffer.write(' (caused by: $cause)');
    }
    return buffer.toString();
  }
}
