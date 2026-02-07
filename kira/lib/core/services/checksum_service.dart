/// SHA-256 checksum computation for receipt image integrity verification.
///
/// Every captured receipt image is checksummed immediately after the timestamp
/// is burned into the pixels. The hex digest is stored alongside the receipt
/// metadata in both the local SQLite database and the cloud index files so
/// that any later corruption or tampering can be detected.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Provides SHA-256 checksum utilities for files and raw byte buffers.
///
/// All methods are intentionally static -- there is no mutable state.
/// Callers may also instantiate this class when dependency-injecting behind
/// an interface for testing.
class ChecksumService {
  const ChecksumService();

  // ---------------------------------------------------------------------------
  // Core computation
  // ---------------------------------------------------------------------------

  /// Computes the SHA-256 digest of [bytes] and returns the lowercase hex
  /// string (64 characters).
  String computeBytesChecksum(Uint8List bytes) {
    final digest = sha256.convert(bytes);
    return digest.toString(); // lowercase hex
  }

  /// Reads the file at [filePath] into memory and returns its SHA-256
  /// lowercase hex digest.
  ///
  /// Throws a [FileSystemException] if the file does not exist or cannot be
  /// read.
  Future<String> computeFileChecksum(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException(
        'Cannot compute checksum -- file does not exist',
        filePath,
      );
    }

    // Stream the file through SHA-256 so that very large images do not require
    // holding the entire file in memory twice.
    final output = AccumulatorSink<Digest>();
    final input = sha256.startChunkedConversion(output);

    final stream = file.openRead();
    await for (final chunk in stream) {
      input.add(chunk);
    }
    input.close();

    return output.events.single.toString();
  }

  /// Verifies that the file at [filePath] matches [expectedChecksum].
  ///
  /// Returns `true` when the freshly computed digest equals
  /// [expectedChecksum] (case-insensitive comparison), `false` otherwise.
  ///
  /// Throws a [FileSystemException] if the file cannot be read.
  Future<bool> verifyChecksum(
    String filePath,
    String expectedChecksum,
  ) async {
    final actual = await computeFileChecksum(filePath);
    return actual.toLowerCase() == expectedChecksum.toLowerCase();
  }
}

/// A [Sink] that accumulates conversion events so we can retrieve the final
/// [Digest] after a chunked SHA-256 conversion completes.
///
/// This is a standard pattern recommended by the `crypto` package for
/// streaming hash computation.
class AccumulatorSink<T> implements Sink<T> {
  final List<T> events = <T>[];

  @override
  void add(T event) => events.add(event);

  @override
  void close() {
    // Nothing to release.
  }
}
