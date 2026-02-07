/// Manages the 7-day free trial lifecycle.
///
/// The trial begins the first time the app is launched. During the trial:
/// - All receipts are stored locally only (no cloud sync).
/// - Trial receipts expire and are auto-deleted 7 days after capture.
/// - After 7 days the user must upgrade to continue capturing.
///
/// This service is a [ChangeNotifier] so that UI widgets rebuild reactively
/// when trial state changes (e.g. after upgrade or daily tick).
library;

import 'package:flutter/foundation.dart';

import '../db/settings_dao.dart';
import '../db/receipt_dao.dart';

/// Duration of the free trial in days.
const int kTrialDurationDays = 7;

class TrialService extends ChangeNotifier {
  final SettingsDao _settingsDao;
  final ReceiptDao _receiptDao;

  DateTime? _trialStartDate;
  bool _isUpgraded = false;
  bool _initialized = false;

  TrialService({
    required SettingsDao settingsDao,
    ReceiptDao? receiptDao,
  })  : _settingsDao = settingsDao,
        _receiptDao = receiptDao ?? ReceiptDao();

  // -------------------------------------------------------------------------
  // Public getters
  // -------------------------------------------------------------------------

  bool get initialized => _initialized;
  bool get isUpgraded => _isUpgraded;

  /// Whether the trial has been started (first launch happened).
  bool get hasTrialStarted => _trialStartDate != null;

  /// Whether the user is currently in an active trial period.
  bool get isTrialActive {
    if (_isUpgraded) return false;
    if (_trialStartDate == null) return false;
    return daysRemaining > 0;
  }

  /// Whether the trial has expired and the user has not upgraded.
  bool get isTrialExpired {
    if (_isUpgraded) return false;
    if (_trialStartDate == null) return false;
    return daysRemaining <= 0;
  }

  /// Number of full days remaining in the trial. Returns 0 if expired.
  int get daysRemaining {
    if (_trialStartDate == null) return 0;
    final elapsed = DateTime.now().difference(_trialStartDate!).inDays;
    return (kTrialDurationDays - elapsed).clamp(0, kTrialDurationDays);
  }

  /// Whether new captures are allowed.
  bool get canCapture => isTrialActive || _isUpgraded;

  // -------------------------------------------------------------------------
  // Initialization
  // -------------------------------------------------------------------------

  /// Loads persisted trial state from the database.
  Future<void> initialize() async {
    final startDateStr = await _settingsDao.getTrialStartDate();
    if (startDateStr != null) {
      _trialStartDate = DateTime.tryParse(startDateStr);
    }
    _isUpgraded = await _settingsDao.isUpgraded();
    _initialized = true;
    notifyListeners();
  }

  /// Starts the trial. Call this on the very first app launch.
  Future<void> startTrial() async {
    if (_trialStartDate != null) return; // Already started.
    _trialStartDate = DateTime.now();
    await _settingsDao.setTrialStartDate(
      _trialStartDate!.toIso8601String(),
    );
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Upgrade
  // -------------------------------------------------------------------------

  /// Marks the user as upgraded, unlocking all features.
  Future<void> upgrade() async {
    _isUpgraded = true;
    await _settingsDao.setUpgraded(true);
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Trial cleanup
  // -------------------------------------------------------------------------

  /// Deletes expired trial receipts (older than 7 days) for non-upgraded
  /// users. Returns the number of receipts removed.
  Future<int> purgeExpiredReceipts() async {
    if (_isUpgraded) return 0;
    return _receiptDao.deleteExpiredTrialReceipts(isUpgraded: _isUpgraded);
  }
}
