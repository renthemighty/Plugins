/// Background sync service using WorkManager for periodic receipt uploads.
///
/// Registers a platform-native background task that runs periodically:
/// - **Android:** WorkManager with periodic constraints.
/// - **iOS:** BGTaskScheduler via the `workmanager` Flutter plugin.
///
/// The service respects:
/// - User's sync policy (Wi-Fi only vs. Wi-Fi + cellular).
/// - Low Data Mode (defers non-critical uploads when enabled).
/// - Battery optimisation (exponential backoff with jitter on failures).
/// - Network availability (skips when offline).
///
/// The background task is registered once and persists across app restarts.
/// It can be cancelled explicitly by the user or when the app is uninstalled.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../db/receipt_dao.dart';
import '../db/settings_dao.dart';
import 'network_monitor.dart';
import 'sync_engine.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// The unique task name registered with WorkManager.
const String _kTaskName = 'kira_background_sync';

/// Tag used to identify and manage Kira sync tasks.
const String _kTaskTag = 'kira_sync';

/// Minimum interval between periodic sync attempts (15 minutes is the
/// platform minimum on both Android and iOS).
const Duration _kMinInterval = Duration(minutes: 15);

/// Maximum number of consecutive failures before the task stops retrying
/// until the next periodic invocation.
const int _kMaxRetries = 5;

/// Base delay for exponential backoff (doubled on each retry).
const Duration _kBaseBackoff = Duration(seconds: 30);

/// Maximum jitter added to backoff delays to spread load.
const Duration _kMaxJitter = Duration(seconds: 15);

// ---------------------------------------------------------------------------
// BackgroundSyncService
// ---------------------------------------------------------------------------

/// Manages registration and cancellation of periodic background sync tasks.
///
/// This class is stateless -- all methods are static. The actual sync work
/// is performed inside [callbackDispatcher], which runs in a separate
/// isolate on Android and in the background on iOS.
class BackgroundSyncService {
  BackgroundSyncService._();

  /// Public task name for external reference.
  static const String taskName = _kTaskName;

  /// Public task tag for external reference.
  static const String taskTag = _kTaskTag;

  // -------------------------------------------------------------------------
  // Initialization
  // -------------------------------------------------------------------------

  /// Initialises the WorkManager plugin. Must be called once at app startup,
  /// typically in `main()` before `runApp()`.
  static Future<void> initialize() async {
    await Workmanager().initialize(
      _callbackDispatcherEntry,
      isInDebugMode: kDebugMode,
    );
  }

  // -------------------------------------------------------------------------
  // Registration
  // -------------------------------------------------------------------------

  /// Registers a periodic background sync task.
  ///
  /// If a task with the same name already exists, WorkManager replaces it
  /// (idempotent). The task runs at most once every 15 minutes and requires
  /// a network connection (the specific type is enforced inside the
  /// callback, not via WorkManager constraints, because the user's sync
  /// policy may change at any time).
  static Future<void> register() async {
    await Workmanager().registerPeriodicTask(
      _kTaskName,
      _kTaskName,
      tag: _kTaskTag,
      frequency: _kMinInterval,
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: _kBaseBackoff,
    );

    debugPrint('BackgroundSyncService: periodic task registered');
  }

  /// Registers a one-shot background sync task that runs as soon as
  /// constraints are met. Useful for triggering an immediate sync when the
  /// user changes storage providers or completes onboarding.
  static Future<void> registerOneShot() async {
    await Workmanager().registerOneOffTask(
      '${_kTaskName}_oneshot',
      _kTaskName,
      tag: _kTaskTag,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: _kBaseBackoff,
    );

    debugPrint('BackgroundSyncService: one-shot task registered');
  }

  // -------------------------------------------------------------------------
  // Cancellation
  // -------------------------------------------------------------------------

  /// Cancels all registered Kira background sync tasks.
  static Future<void> cancel() async {
    await Workmanager().cancelByTag(_kTaskTag);
    debugPrint('BackgroundSyncService: all tasks cancelled');
  }

  /// Cancels only the periodic sync task, leaving any one-shot tasks intact.
  static Future<void> cancelPeriodic() async {
    await Workmanager().cancelByUniqueName(_kTaskName);
    debugPrint('BackgroundSyncService: periodic task cancelled');
  }

  // -------------------------------------------------------------------------
  // Callback dispatcher (runs in background isolate)
  // -------------------------------------------------------------------------

  /// The top-level callback that WorkManager invokes in a background
  /// isolate. This is the entry point for all background sync work.
  ///
  /// The method:
  /// 1. Reads the user's current sync policy and Low Data Mode setting.
  /// 2. Checks network conditions against the policy.
  /// 3. If conditions are met, runs a full sync cycle.
  /// 4. On failure, applies exponential backoff with jitter.
  static Future<bool> callbackDispatcher(
    String taskName,
    Map<String, dynamic>? inputData,
  ) async {
    debugPrint(
      'BackgroundSyncService: callback invoked for task "$taskName"',
    );

    try {
      // Load user settings.
      final settingsDao = SettingsDao();
      final settings = await settingsDao.getAppSettings();

      // Bail out if background sync is disabled.
      if (!settings.backgroundSync) {
        debugPrint('BackgroundSyncService: background sync disabled by user');
        return true;
      }

      // Check network conditions.
      final networkMonitor = NetworkMonitor();
      final canSync = await _checkNetworkPolicy(
        networkMonitor,
        settings.syncPolicy,
        settings.lowDataMode,
      );
      networkMonitor.dispose();

      if (!canSync) {
        debugPrint(
          'BackgroundSyncService: network conditions do not meet sync policy',
        );
        return true; // Return true so WorkManager doesn't count as failure.
      }

      // Run the sync engine.
      final receiptDao = ReceiptDao();
      final syncEngine = SyncEngine(
        receiptDao: receiptDao,
        settingsDao: settingsDao,
      );

      await syncEngine.initialize();

      if (syncEngine.pendingCount == 0) {
        debugPrint('BackgroundSyncService: no pending items to sync');
        return true;
      }

      await syncEngine.syncAll();

      if (syncEngine.status == SyncEngineStatus.error) {
        debugPrint(
          'BackgroundSyncService: sync completed with errors: '
          '${syncEngine.lastError}',
        );
        // Returning false tells WorkManager to apply the backoff policy.
        return false;
      }

      // Record the successful sync timestamp.
      final now = DateTime.now().toUtc().toIso8601String();
      await settingsDao.setLastSyncAt(now);

      debugPrint('BackgroundSyncService: sync completed successfully');
      return true;
    } catch (e, stackTrace) {
      debugPrint(
        'BackgroundSyncService: unhandled error: $e\n$stackTrace',
      );
      return false;
    }
  }

  // -------------------------------------------------------------------------
  // Network policy enforcement
  // -------------------------------------------------------------------------

  /// Checks whether the current network status satisfies the user's sync
  /// policy and Low Data Mode setting.
  static Future<bool> _checkNetworkPolicy(
    NetworkMonitor monitor,
    String syncPolicy,
    bool lowDataMode,
  ) async {
    final status = await monitor.currentStatus;

    // No connection at all.
    if (status == NetworkStatus.none) return false;

    // Low Data Mode: only sync on Wi-Fi regardless of policy.
    if (lowDataMode && status != NetworkStatus.wifi) return false;

    // Enforce sync policy.
    switch (syncPolicy) {
      case 'wifi_only':
        return status == NetworkStatus.wifi;
      case 'wifi_cellular':
        return status == NetworkStatus.wifi ||
            status == NetworkStatus.cellular;
      default:
        return status == NetworkStatus.wifi;
    }
  }

  // -------------------------------------------------------------------------
  // Backoff with jitter
  // -------------------------------------------------------------------------

  /// Computes a backoff duration with jitter for the given [retryCount].
  ///
  /// The formula is: `baseDelay * 2^retryCount + random(0, maxJitter)`.
  /// This is used internally when manual retry logic is needed outside of
  /// WorkManager's built-in backoff.
  static Duration computeBackoff(int retryCount) {
    final capped = retryCount.clamp(0, _kMaxRetries);
    final baseMs = _kBaseBackoff.inMilliseconds * (1 << capped);
    final jitterMs = Random().nextInt(_kMaxJitter.inMilliseconds);
    return Duration(milliseconds: baseMs + jitterMs);
  }
}

// ---------------------------------------------------------------------------
// Top-level callback entry point
// ---------------------------------------------------------------------------

/// Top-level function passed to [Workmanager.initialize]. WorkManager
/// requires a top-level or static function for the callback dispatcher.
@pragma('vm:entry-point')
void _callbackDispatcherEntry() {
  Workmanager().executeTask((taskName, inputData) async {
    return BackgroundSyncService.callbackDispatcher(taskName, inputData);
  });
}
