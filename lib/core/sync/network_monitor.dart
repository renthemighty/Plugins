/// Reactive network status monitoring for the Kira sync system.
///
/// Wraps the `connectivity_plus` package to provide:
/// - A [Stream] of [NetworkStatus] changes.
/// - Synchronous-style queries for the current connection type.
/// - Policy-aware helpers that check whether syncing is permitted given the
///   user's [SyncPolicy] preference.
///
/// The monitor automatically maps the platform connectivity results to the
/// simplified [NetworkStatus] enum used throughout Kira.
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// NetworkStatus enum
// ---------------------------------------------------------------------------

/// Simplified network connection type for sync policy enforcement.
enum NetworkStatus {
  /// Connected via Wi-Fi (or Ethernet on desktop).
  wifi,

  /// Connected via cellular (mobile data).
  cellular,

  /// No network connection available.
  none,
}

// ---------------------------------------------------------------------------
// NetworkMonitor
// ---------------------------------------------------------------------------

/// Monitors the device's network connectivity and exposes a reactive stream
/// of [NetworkStatus] values.
///
/// Usage:
/// ```dart
/// final monitor = NetworkMonitor();
/// monitor.statusStream.listen((status) {
///   print('Network: $status');
/// });
///
/// // Later:
/// monitor.dispose();
/// ```
class NetworkMonitor {
  final Connectivity _connectivity;

  StreamController<NetworkStatus>? _controller;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  NetworkStatus? _lastKnownStatus;

  /// Creates a [NetworkMonitor].
  ///
  /// An optional [Connectivity] instance can be injected for testing.
  NetworkMonitor({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  // -------------------------------------------------------------------------
  // Reactive stream
  // -------------------------------------------------------------------------

  /// A broadcast stream that emits [NetworkStatus] whenever the device's
  /// connectivity changes.
  ///
  /// The stream is lazy -- the platform listener is only attached when the
  /// first subscriber appears. Multiple subscribers share the same stream.
  Stream<NetworkStatus> get statusStream {
    _ensureController();
    return _controller!.stream;
  }

  void _ensureController() {
    if (_controller != null) return;

    _controller = StreamController<NetworkStatus>.broadcast(
      onListen: _startListening,
      onCancel: _stopListening,
    );
  }

  void _startListening() {
    _subscription = _connectivity.onConnectivityChanged.listen(
      (results) {
        final status = _mapResults(results);
        if (status != _lastKnownStatus) {
          _lastKnownStatus = status;
          _controller?.add(status);
        }
      },
      onError: (Object error) {
        debugPrint('NetworkMonitor: connectivity stream error: $error');
        _controller?.add(NetworkStatus.none);
      },
    );
  }

  void _stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }

  // -------------------------------------------------------------------------
  // Point-in-time queries
  // -------------------------------------------------------------------------

  /// Returns the current [NetworkStatus] by querying the platform.
  Future<NetworkStatus> get currentStatus async {
    try {
      final results = await _connectivity.checkConnectivity();
      final status = _mapResults(results);
      _lastKnownStatus = status;
      return status;
    } catch (e) {
      debugPrint('NetworkMonitor: failed to check connectivity: $e');
      return NetworkStatus.none;
    }
  }

  /// Returns `true` when the device has any network connection (Wi-Fi or
  /// cellular).
  Future<bool> get isConnected async {
    final status = await currentStatus;
    return status != NetworkStatus.none;
  }

  /// Returns `true` when the device is connected via Wi-Fi.
  Future<bool> get isWifi async {
    final status = await currentStatus;
    return status == NetworkStatus.wifi;
  }

  /// Returns `true` when the device is connected via cellular data.
  Future<bool> get isCellular async {
    final status = await currentStatus;
    return status == NetworkStatus.cellular;
  }

  // -------------------------------------------------------------------------
  // Policy-aware helpers
  // -------------------------------------------------------------------------

  /// Returns `true` when the current network status meets the requirements
  /// of the given sync [policy].
  ///
  /// Policy rules:
  /// - `wifi_only` -- only returns `true` on Wi-Fi.
  /// - `wifi_cellular` -- returns `true` on either Wi-Fi or cellular.
  ///
  /// An optional [lowDataMode] flag can further restrict syncing to Wi-Fi
  /// only, regardless of the policy.
  Future<bool> canSync({
    required String policy,
    bool lowDataMode = false,
  }) async {
    final status = await currentStatus;

    if (status == NetworkStatus.none) return false;

    // Low Data Mode overrides policy: only Wi-Fi is acceptable.
    if (lowDataMode) return status == NetworkStatus.wifi;

    switch (policy) {
      case 'wifi_only':
        return status == NetworkStatus.wifi;
      case 'wifi_cellular':
        return status == NetworkStatus.wifi ||
            status == NetworkStatus.cellular;
      default:
        // Unknown policy -- default to Wi-Fi only for safety.
        return status == NetworkStatus.wifi;
    }
  }

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  /// Returns the last known status without querying the platform.
  ///
  /// May be `null` if [currentStatus] or [statusStream] has never been
  /// accessed.
  NetworkStatus? get lastKnownStatus => _lastKnownStatus;

  /// Releases all resources. After calling [dispose], the monitor must not
  /// be used again.
  void dispose() {
    _stopListening();
    _controller?.close();
    _controller = null;
    _lastKnownStatus = null;
  }

  // -------------------------------------------------------------------------
  // Mapping helpers
  // -------------------------------------------------------------------------

  /// Maps a list of [ConnectivityResult] values (as returned by
  /// connectivity_plus) to a single [NetworkStatus].
  ///
  /// When multiple connections are available simultaneously (e.g. Wi-Fi and
  /// cellular), Wi-Fi takes precedence.
  static NetworkStatus _mapResults(List<ConnectivityResult> results) {
    if (results.isEmpty) return NetworkStatus.none;

    // Check for Wi-Fi first (highest priority).
    if (results.contains(ConnectivityResult.wifi)) {
      return NetworkStatus.wifi;
    }

    // Ethernet is treated as Wi-Fi equivalent (desktop / docked devices).
    if (results.contains(ConnectivityResult.ethernet)) {
      return NetworkStatus.wifi;
    }

    // Mobile / cellular.
    if (results.contains(ConnectivityResult.mobile)) {
      return NetworkStatus.cellular;
    }

    // VPN connections -- assume the underlying transport is adequate.
    if (results.contains(ConnectivityResult.vpn)) {
      return NetworkStatus.wifi;
    }

    // Bluetooth or other -- not sufficient for sync.
    if (results.contains(ConnectivityResult.bluetooth) ||
        results.contains(ConnectivityResult.other)) {
      return NetworkStatus.none;
    }

    // ConnectivityResult.none or unrecognised values.
    return NetworkStatus.none;
  }
}
