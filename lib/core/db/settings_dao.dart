/// Data-access object for the `app_settings` key-value table.
///
/// Settings are stored as plain `TEXT` values.  The [AppSettings] value
/// object provides typed accessors and sensible defaults for every setting
/// used by the app.
library;

import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';

// ---------------------------------------------------------------------------
// Well-known setting keys
// ---------------------------------------------------------------------------

/// Keys used in the `app_settings` table.  Keeping them in one place avoids
/// typos and makes it easy to discover every persisted setting.
abstract final class SettingsKey {
  static const String country = 'country';
  static const String region = 'region';
  static const String currencyCode = 'currency_code';
  static const String language = 'language';
  static const String storageMode = 'storage_mode';
  static const String syncPolicy = 'sync_policy';
  static const String lowDataMode = 'low_data_mode';
  static const String backgroundSync = 'background_sync';
  static const String appLockEnabled = 'app_lock_enabled';
  static const String trialStartDate = 'trial_start_date';
  static const String upgraded = 'upgraded';
  static const String onboardingComplete = 'onboarding_complete';
  static const String deviceId = 'device_id';
  static const String retentionAcknowledged = 'retention_acknowledged';
  static const String paperDisclaimerAcknowledged =
      'paper_disclaimer_acknowledged';
  static const String lastSyncAt = 'last_sync_at';
}

// ---------------------------------------------------------------------------
// AppSettings value object
// ---------------------------------------------------------------------------

/// Typed snapshot of all persisted settings.
///
/// Constructed from the raw key-value map by [SettingsDao.getAppSettings].
class AppSettings {
  final String? country;
  final String? region;
  final String currencyCode;
  final String language;
  final String? storageMode;
  final String syncPolicy;
  final bool lowDataMode;
  final bool backgroundSync;
  final bool appLockEnabled;
  final String? trialStartDate;
  final bool upgraded;
  final bool onboardingComplete;
  final String? deviceId;
  final bool retentionAcknowledged;
  final bool paperDisclaimerAcknowledged;
  final String? lastSyncAt;

  const AppSettings({
    this.country,
    this.region,
    this.currencyCode = 'CAD',
    this.language = 'en',
    this.storageMode,
    this.syncPolicy = 'wifi_only',
    this.lowDataMode = false,
    this.backgroundSync = true,
    this.appLockEnabled = false,
    this.trialStartDate,
    this.upgraded = false,
    this.onboardingComplete = false,
    this.deviceId,
    this.retentionAcknowledged = false,
    this.paperDisclaimerAcknowledged = false,
    this.lastSyncAt,
  });

  /// Constructs an [AppSettings] from the raw key-value map stored in the
  /// database.
  factory AppSettings.fromMap(Map<String, String?> map) {
    return AppSettings(
      country: map[SettingsKey.country],
      region: map[SettingsKey.region],
      currencyCode: map[SettingsKey.currencyCode] ?? 'CAD',
      language: map[SettingsKey.language] ?? 'en',
      storageMode: map[SettingsKey.storageMode],
      syncPolicy: map[SettingsKey.syncPolicy] ?? 'wifi_only',
      lowDataMode: map[SettingsKey.lowDataMode] == 'true',
      backgroundSync: map[SettingsKey.backgroundSync] != 'false',
      appLockEnabled: map[SettingsKey.appLockEnabled] == 'true',
      trialStartDate: map[SettingsKey.trialStartDate],
      upgraded: map[SettingsKey.upgraded] == 'true',
      onboardingComplete: map[SettingsKey.onboardingComplete] == 'true',
      deviceId: map[SettingsKey.deviceId],
      retentionAcknowledged:
          map[SettingsKey.retentionAcknowledged] == 'true',
      paperDisclaimerAcknowledged:
          map[SettingsKey.paperDisclaimerAcknowledged] == 'true',
      lastSyncAt: map[SettingsKey.lastSyncAt],
    );
  }

  @override
  String toString() =>
      'AppSettings(country: $country, upgraded: $upgraded, '
      'onboarding: $onboardingComplete, storage: $storageMode)';
}

// ---------------------------------------------------------------------------
// DAO
// ---------------------------------------------------------------------------

class SettingsDao {
  final DatabaseHelper _dbHelper;

  SettingsDao([DatabaseHelper? helper]) : _dbHelper = helper ?? DatabaseHelper();

  Future<Database> get _db => _dbHelper.database;

  // ---------------------------------------------------------------------------
  // Generic get / set
  // ---------------------------------------------------------------------------

  /// Returns the raw string value for [key], or `null` if unset.
  Future<String?> get(String key) async {
    final db = await _db;
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  /// Upserts a single setting.
  Future<void> set(String key, String? value) async {
    final db = await _db;
    await db.insert(
      'app_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Removes a setting entirely.
  Future<void> remove(String key) async {
    final db = await _db;
    await db.delete('app_settings', where: 'key = ?', whereArgs: [key]);
  }

  // ---------------------------------------------------------------------------
  // Typed convenience setters / getters
  // ---------------------------------------------------------------------------

  Future<String?> getCountry() => get(SettingsKey.country);
  Future<void> setCountry(String value) => set(SettingsKey.country, value);

  Future<String?> getRegion() => get(SettingsKey.region);
  Future<void> setRegion(String value) => set(SettingsKey.region, value);

  Future<String> getCurrencyCode() async =>
      (await get(SettingsKey.currencyCode)) ?? 'CAD';
  Future<void> setCurrencyCode(String value) =>
      set(SettingsKey.currencyCode, value);

  Future<String> getLanguage() async =>
      (await get(SettingsKey.language)) ?? 'en';
  Future<void> setLanguage(String value) => set(SettingsKey.language, value);

  Future<String?> getStorageMode() => get(SettingsKey.storageMode);
  Future<void> setStorageMode(String value) =>
      set(SettingsKey.storageMode, value);

  Future<String> getSyncPolicy() async =>
      (await get(SettingsKey.syncPolicy)) ?? 'wifi_only';
  Future<void> setSyncPolicy(String value) =>
      set(SettingsKey.syncPolicy, value);

  Future<bool> getLowDataMode() async =>
      (await get(SettingsKey.lowDataMode)) == 'true';
  Future<void> setLowDataMode(bool value) =>
      set(SettingsKey.lowDataMode, value.toString());

  Future<bool> getBackgroundSync() async =>
      (await get(SettingsKey.backgroundSync)) != 'false';
  Future<void> setBackgroundSync(bool value) =>
      set(SettingsKey.backgroundSync, value.toString());

  Future<bool> getAppLockEnabled() async =>
      (await get(SettingsKey.appLockEnabled)) == 'true';
  Future<void> setAppLockEnabled(bool value) =>
      set(SettingsKey.appLockEnabled, value.toString());

  Future<String?> getDeviceId() => get(SettingsKey.deviceId);
  Future<void> setDeviceId(String value) => set(SettingsKey.deviceId, value);

  Future<bool> getRetentionAcknowledged() async =>
      (await get(SettingsKey.retentionAcknowledged)) == 'true';
  Future<void> setRetentionAcknowledged(bool value) =>
      set(SettingsKey.retentionAcknowledged, value.toString());

  Future<bool> getPaperDisclaimerAcknowledged() async =>
      (await get(SettingsKey.paperDisclaimerAcknowledged)) == 'true';
  Future<void> setPaperDisclaimerAcknowledged(bool value) =>
      set(SettingsKey.paperDisclaimerAcknowledged, value.toString());

  Future<bool> getOnboardingComplete() async =>
      (await get(SettingsKey.onboardingComplete)) == 'true';
  Future<void> setOnboardingComplete(bool value) =>
      set(SettingsKey.onboardingComplete, value.toString());

  Future<String?> getLastSyncAt() => get(SettingsKey.lastSyncAt);
  Future<void> setLastSyncAt(String value) =>
      set(SettingsKey.lastSyncAt, value);

  // ---------------------------------------------------------------------------
  // Trial / upgrade helpers
  // ---------------------------------------------------------------------------

  /// Persists the trial start date.  Should be called once during onboarding.
  Future<void> setTrialStartDate(String isoDate) =>
      set(SettingsKey.trialStartDate, isoDate);

  /// Returns the persisted trial start date, or `null` if never set.
  Future<String?> getTrialStartDate() => get(SettingsKey.trialStartDate);

  /// Returns `true` when the 7-day trial period has elapsed **and** the user
  /// has not upgraded.
  Future<bool> isTrialExpired() async {
    final upgraded = await isUpgraded();
    if (upgraded) return false;

    final startStr = await get(SettingsKey.trialStartDate);
    if (startStr == null) return false;

    final start = DateTime.tryParse(startStr);
    if (start == null) return false;

    return DateTime.now().toUtc().difference(start).inDays >= 7;
  }

  /// Returns `true` if the user has purchased a paid plan.
  Future<bool> isUpgraded() async =>
      (await get(SettingsKey.upgraded)) == 'true';

  /// Records that the user has upgraded to a paid plan.
  Future<void> setUpgraded(bool value) =>
      set(SettingsKey.upgraded, value.toString());

  // ---------------------------------------------------------------------------
  // Bulk read
  // ---------------------------------------------------------------------------

  /// Loads **all** settings from the database and returns a typed
  /// [AppSettings] snapshot.
  Future<AppSettings> getAppSettings() async {
    final db = await _db;
    final rows = await db.query('app_settings');
    final map = <String, String?>{};
    for (final row in rows) {
      map[row['key'] as String] = row['value'] as String?;
    }
    return AppSettings.fromMap(map);
  }
}
