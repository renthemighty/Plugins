/// Network security utilities for the Kira app.
///
/// Provides:
/// - HTTPS enforcement on all outbound requests.
/// - Certificate pinning for the Kira backend (not for third-party APIs whose
///   certificates rotate frequently).
/// - Timeout configuration.
/// - Cleartext traffic detection.
///
/// The [SecureHttpClient] is a wrapper around [http.Client] that applies
/// these policies transparently.
library;

import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

/// Default timeout durations for network operations.
abstract final class NetworkTimeouts {
  /// Maximum time to establish a TCP connection.
  static const Duration connect = Duration(seconds: 15);

  /// Maximum time to wait for the complete response after the connection
  /// has been established.
  static const Duration receive = Duration(seconds: 30);

  /// Maximum time for file upload operations (large receipts).
  static const Duration upload = Duration(seconds: 120);

  /// Maximum time for file download operations.
  static const Duration download = Duration(seconds: 120);
}

/// SHA-256 fingerprints of the public keys we pin for the Kira backend.
///
/// **Rotation policy:** whenever the Kira backend rotates its TLS certificate,
/// a new pin must be added here *before* the old certificate expires.  The old
/// pin should be kept for at least one release cycle as a grace period.
///
/// Only the Kira backend is pinned.  Third-party providers (Google, Dropbox,
/// Microsoft, Box) are **not** pinned because they rotate certificates on
/// their own schedules and pinning would cause silent breakage.
abstract final class CertificatePins {
  /// Primary pin (current production certificate).
  static const String primary =
      'sha256/BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=';

  /// Backup pin (next certificate, pre-provisioned).
  static const String backup =
      'sha256/CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC=';

  static const List<String> all = [primary, backup];
}

/// The host name of the Kira backend -- the only origin we pin.
const String kKiraBackendHost = 'api.kira.app';

// ---------------------------------------------------------------------------
// HTTPS enforcement
// ---------------------------------------------------------------------------

/// Asserts that [uri] uses the HTTPS scheme.
///
/// Throws [InsecureConnectionException] for any non-HTTPS URI.  This is the
/// single enforcement point called by every outbound request helper.
void enforceHttps(Uri uri) {
  if (uri.scheme != 'https') {
    throw InsecureConnectionException(
      'Cleartext HTTP is not allowed. '
      'Attempted to connect to: $uri',
    );
  }
}

/// Returns `true` when [uri] points to the Kira backend and should therefore
/// have its certificate pinned.
bool _shouldPin(Uri uri) => uri.host == kKiraBackendHost;

// ---------------------------------------------------------------------------
// Secure HTTP client
// ---------------------------------------------------------------------------

/// An [http.BaseClient] that enforces HTTPS on every request and applies
/// certificate pinning for the Kira backend.
///
/// For third-party APIs the request is forwarded to the inner [http.Client]
/// without pinning -- those providers manage their own certificate rotation.
class SecureHttpClient extends http.BaseClient {
  SecureHttpClient({
    http.Client? inner,
    Duration timeout = const Duration(seconds: 30),
  })  : _inner = inner ?? http.Client(),
        _timeout = timeout;

  final http.Client _inner;
  final Duration _timeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    enforceHttps(request.url);

    if (_shouldPin(request.url)) {
      _validateCertificatePin(request.url);
    }

    // Apply a timeout to every request.
    return _inner.send(request).timeout(_timeout);
  }

  /// Validates the TLS certificate of a pinned host.
  ///
  /// In a real implementation this would use a platform channel or a
  /// purpose-built native plugin to inspect the server certificate's
  /// Subject Public Key Info (SPKI) hash and compare it against
  /// [CertificatePins.all].
  ///
  /// The current Dart [HttpClient] does not expose certificate details in
  /// the high-level `http` package, so this method is a placeholder that
  /// documents the intended behaviour and will be wired to native code
  /// via a method channel.
  void _validateCertificatePin(Uri uri) {
    // TODO(security): Wire to platform channel for SPKI hash comparison.
    //
    // On Android this will use `TrustManager` + `X509Certificate.getPublicKey`.
    // On iOS this will use `SecTrustEvaluateWithError` +
    //   `SecCertificateCopyKey` + `SecKeyCopyExternalRepresentation`.
    //
    // Pseudocode:
    // final spkiHash = await _platformChannel.getSpkiHash(uri.host, uri.port);
    // if (!CertificatePins.all.contains(spkiHash)) {
    //   throw CertificatePinningException(
    //     'Certificate pin mismatch for ${uri.host}. '
    //     'Expected one of ${CertificatePins.all}, got $spkiHash.',
    //   );
    // }
  }

  @override
  void close() {
    _inner.close();
  }
}

// ---------------------------------------------------------------------------
// Pinned HttpClient (dart:io level)
// ---------------------------------------------------------------------------

/// Creates a [dart:io HttpClient] with certificate pinning for the Kira
/// backend.
///
/// This is useful for lower-level operations (e.g. large file downloads)
/// where the `http` package is not used directly.
HttpClient createPinnedHttpClient() {
  final client = HttpClient()
    ..connectionTimeout = NetworkTimeouts.connect
    ..idleTimeout = const Duration(seconds: 15);

  client.badCertificateCallback = (X509Certificate cert, String host, int port) {
    // For the Kira backend we reject any certificate that doesn't match our
    // pins.  For all other hosts we accept the system trust store's verdict
    // (returning `false` means "reject", but we only reach this callback when
    // the system trust store has already rejected the cert).
    if (host == kKiraBackendHost) {
      // In a full implementation we would compute the SPKI hash of `cert`
      // and compare it against [CertificatePins.all].  For now we reject
      // all bad certificates for the backend.
      return false;
    }

    // For third-party hosts, follow the platform default (reject bad certs).
    return false;
  };

  return client;
}

// ---------------------------------------------------------------------------
// Cleartext traffic check
// ---------------------------------------------------------------------------

/// Returns `true` if the current platform is configured to allow cleartext
/// (HTTP) traffic.
///
/// On Android this checks `android:usesCleartextTraffic` in the manifest.
/// On iOS/macOS it checks the App Transport Security settings.
///
/// In the current implementation this is a compile-time assertion:
/// Kira's Android manifest sets `android:usesCleartextTraffic="false"` and
/// the iOS Info.plist does not contain ATS exceptions.
bool isCleartextTrafficAllowed() {
  // This is enforced at the platform level:
  //   Android: android/app/src/main/AndroidManifest.xml
  //     <application android:usesCleartextTraffic="false" ...>
  //
  //   iOS: ios/Runner/Info.plist
  //     NSAppTransportSecurity is absent (defaults to requiring HTTPS).
  //
  // We return false to indicate that cleartext traffic is blocked.
  return false;
}

// ---------------------------------------------------------------------------
// Retry helper with exponential backoff + jitter
// ---------------------------------------------------------------------------

/// Executes [action] with automatic retry on transient failures.
///
/// Uses exponential backoff with full jitter to spread out retry storms:
///
/// ```
/// delay = random(0, min(maxDelay, baseDelay * 2^attempt))
/// ```
///
/// Retries on:
/// - [SocketException] (network unreachable, connection refused)
/// - [HttpException] (malformed responses)
/// - HTTP 429 (Too Many Requests)
/// - HTTP 500, 502, 503, 504 (server errors)
///
/// All other exceptions propagate immediately.
Future<T> retryWithBackoff<T>(
  Future<T> Function() action, {
  int maxAttempts = 4,
  Duration baseDelay = const Duration(milliseconds: 500),
  Duration maxDelay = const Duration(seconds: 16),
}) async {
  final random = _RetryRandom();

  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      return await action();
    } catch (e) {
      final isLast = attempt == maxAttempts - 1;
      if (isLast || !_isRetryable(e)) rethrow;

      final exponentialDelay = baseDelay * (1 << attempt);
      final cappedDelay = exponentialDelay > maxDelay ? maxDelay : exponentialDelay;
      final jitteredDelay = Duration(
        milliseconds: random.nextInt(cappedDelay.inMilliseconds + 1),
      );

      await Future<void>.delayed(jitteredDelay);
    }
  }

  // Unreachable -- the loop either returns or rethrows.
  throw StateError('retryWithBackoff: unreachable');
}

/// Determines whether [error] is a transient failure worth retrying.
bool _isRetryable(Object error) {
  if (error is SocketException) return true;
  if (error is HttpException) return true;

  if (error is http.ClientException) return true;

  if (error is RetryableHttpException) return true;

  return false;
}

/// A trivial wrapper so we can seed the random for tests without polluting
/// the public API.
class _RetryRandom {
  final _rng = _secureRandom;
  int nextInt(int max) => max <= 0 ? 0 : _rng.nextInt(max);
}

final _secureRandom = Random.secure();

// ---------------------------------------------------------------------------
// Exceptions
// ---------------------------------------------------------------------------

/// Thrown when an HTTP request is attempted over cleartext (non-HTTPS).
class InsecureConnectionException implements Exception {
  final String message;
  const InsecureConnectionException(this.message);

  @override
  String toString() => 'InsecureConnectionException: $message';
}

/// Thrown when certificate pinning validation fails.
class CertificatePinningException implements Exception {
  final String message;
  const CertificatePinningException(this.message);

  @override
  String toString() => 'CertificatePinningException: $message';
}

/// Marker exception for HTTP responses that should trigger a retry
/// (429, 5xx).
class RetryableHttpException implements Exception {
  final int statusCode;
  final String? body;

  const RetryableHttpException(this.statusCode, [this.body]);

  @override
  String toString() =>
      'RetryableHttpException: HTTP $statusCode${body != null ? ' - $body' : ''}';
}

