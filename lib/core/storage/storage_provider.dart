/// Storage mode enumeration and exception types for Kira storage backends.
///
/// The [StorageProvider] interface is defined in `folder_service.dart` and
/// re-exported here so concrete providers can import a single file.
library;

export '../services/folder_service.dart' show StorageProvider;

/// The set of supported storage backends.
enum StorageMode {
  googleDrive,
  dropbox,
  oneDrive,
  box,
  kiraCloud,
  localEncrypted,
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
