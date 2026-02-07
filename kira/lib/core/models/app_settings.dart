/// Application settings model for the Kira receipt app.
///
/// [AppSettings] captures every user-configurable preference and is persisted
/// locally (SharedPreferences / SQLite). It is intentionally a pure value
/// object with no Flutter dependencies so that it can be tested in isolation.
library;

import 'package:collection/collection.dart';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// Where receipt images and index files are stored.
enum StorageMode {
  /// Images are stored only on the local device.
  localOnly,

  /// Images are stored locally and synced to the cloud.
  cloudSync,
}

/// Network policy for background sync operations.
enum SyncPolicy {
  /// Only sync when connected to Wi-Fi.
  wifiOnly,

  /// Sync over both Wi-Fi and cellular data.
  wifiCellular,
}

// ---------------------------------------------------------------------------
// Enum helpers
// ---------------------------------------------------------------------------

String _storageModeToString(StorageMode mode) {
  switch (mode) {
    case StorageMode.localOnly:
      return 'local_only';
    case StorageMode.cloudSync:
      return 'cloud_sync';
  }
}

StorageMode _storageModeFromString(String value) {
  switch (value) {
    case 'local_only':
      return StorageMode.localOnly;
    case 'cloud_sync':
      return StorageMode.cloudSync;
    default:
      throw ArgumentError('Unknown StorageMode value: $value');
  }
}

String _syncPolicyToString(SyncPolicy policy) {
  switch (policy) {
    case SyncPolicy.wifiOnly:
      return 'wifi_only';
    case SyncPolicy.wifiCellular:
      return 'wifi_cellular';
  }
}

SyncPolicy _syncPolicyFromString(String value) {
  switch (value) {
    case 'wifi_only':
      return SyncPolicy.wifiOnly;
    case 'wifi_cellular':
      return SyncPolicy.wifiCellular;
    default:
      throw ArgumentError('Unknown SyncPolicy value: $value');
  }
}

// ---------------------------------------------------------------------------
// AppSettings
// ---------------------------------------------------------------------------

/// All user-configurable application settings.
class AppSettings {
  /// The user's primary country context (`canada` or `us`).
  /// Determines tax rules, currency defaults, and localisation hints.
  final String country;

  /// Where images are persisted.
  final StorageMode storageMode;

  /// Network policy governing when sync is allowed.
  final SyncPolicy syncPolicy;

  /// When `true`, the app minimises data transfer (e.g. defers full-size
  /// image uploads, compresses more aggressively).
  final bool lowDataMode;

  /// Whether background sync via WorkManager is enabled.
  final bool backgroundSyncEnabled;

  /// Whether biometric / PIN lock is required to open the app.
  final bool appLockEnabled;

  /// An explicit locale override (e.g. `fr`, `en`). When `null` the app
  /// follows the system locale.
  final String? languageOverride;

  /// ISO-8601 date (`YYYY-MM-DD`) when the user's free trial started.
  final String trialStartDate;

  /// Whether the user has upgraded to the paid tier.
  final bool isUpgraded;

  /// The user's list of receipt categories. These are fully customisable;
  /// the app seeds a set of defaults on first launch.
  final List<String> categories;

  /// The currently selected province / state code (e.g. `ON`, `QC`, `CA`).
  final String selectedRegion;

  const AppSettings({
    required this.country,
    this.storageMode = StorageMode.cloudSync,
    this.syncPolicy = SyncPolicy.wifiOnly,
    this.lowDataMode = false,
    this.backgroundSyncEnabled = true,
    this.appLockEnabled = false,
    this.languageOverride,
    required this.trialStartDate,
    this.isUpgraded = false,
    this.categories = const <String>[],
    required this.selectedRegion,
  });

  /// Provides a sensible set of defaults for a new Canadian user.
  factory AppSettings.defaultCanada({
    required String trialStartDate,
    String selectedRegion = 'ON',
  }) {
    return AppSettings(
      country: 'canada',
      trialStartDate: trialStartDate,
      selectedRegion: selectedRegion,
      categories: const <String>[
        'Meals & Entertainment',
        'Travel',
        'Office Supplies',
        'Gas & Fuel',
        'Lodging',
        'Professional Services',
        'Utilities',
        'Other',
      ],
    );
  }

  /// Provides a sensible set of defaults for a new US user.
  factory AppSettings.defaultUS({
    required String trialStartDate,
    String selectedRegion = 'CA',
  }) {
    return AppSettings(
      country: 'us',
      trialStartDate: trialStartDate,
      selectedRegion: selectedRegion,
      categories: const <String>[
        'Meals & Entertainment',
        'Travel',
        'Office Supplies',
        'Gas & Fuel',
        'Lodging',
        'Professional Services',
        'Utilities',
        'Other',
      ],
    );
  }

  // -------------------------------------------------------------------------
  // JSON serialisation
  // -------------------------------------------------------------------------

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final rawCategories =
        json['categories'] as List<dynamic>? ?? <dynamic>[];
    return AppSettings(
      country: json['country'] as String,
      storageMode:
          _storageModeFromString(json['storage_mode'] as String? ?? 'cloud_sync'),
      syncPolicy:
          _syncPolicyFromString(json['sync_policy'] as String? ?? 'wifi_only'),
      lowDataMode: json['low_data_mode'] as bool? ?? false,
      backgroundSyncEnabled:
          json['background_sync_enabled'] as bool? ?? true,
      appLockEnabled: json['app_lock_enabled'] as bool? ?? false,
      languageOverride: json['language_override'] as String?,
      trialStartDate: json['trial_start_date'] as String,
      isUpgraded: json['is_upgraded'] as bool? ?? false,
      categories: rawCategories.cast<String>(),
      selectedRegion: json['selected_region'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'country': country,
      'storage_mode': _storageModeToString(storageMode),
      'sync_policy': _syncPolicyToString(syncPolicy),
      'low_data_mode': lowDataMode,
      'background_sync_enabled': backgroundSyncEnabled,
      'app_lock_enabled': appLockEnabled,
      'language_override': languageOverride,
      'trial_start_date': trialStartDate,
      'is_upgraded': isUpgraded,
      'categories': categories,
      'selected_region': selectedRegion,
    };
  }

  // -------------------------------------------------------------------------
  // copyWith
  // -------------------------------------------------------------------------

  AppSettings copyWith({
    String? country,
    StorageMode? storageMode,
    SyncPolicy? syncPolicy,
    bool? lowDataMode,
    bool? backgroundSyncEnabled,
    bool? appLockEnabled,
    String? Function()? languageOverride,
    String? trialStartDate,
    bool? isUpgraded,
    List<String>? categories,
    String? selectedRegion,
  }) {
    return AppSettings(
      country: country ?? this.country,
      storageMode: storageMode ?? this.storageMode,
      syncPolicy: syncPolicy ?? this.syncPolicy,
      lowDataMode: lowDataMode ?? this.lowDataMode,
      backgroundSyncEnabled:
          backgroundSyncEnabled ?? this.backgroundSyncEnabled,
      appLockEnabled: appLockEnabled ?? this.appLockEnabled,
      languageOverride: languageOverride != null
          ? languageOverride()
          : this.languageOverride,
      trialStartDate: trialStartDate ?? this.trialStartDate,
      isUpgraded: isUpgraded ?? this.isUpgraded,
      categories: categories ?? this.categories,
      selectedRegion: selectedRegion ?? this.selectedRegion,
    );
  }

  // -------------------------------------------------------------------------
  // Equality
  // -------------------------------------------------------------------------

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AppSettings) return false;
    return other.country == country &&
        other.storageMode == storageMode &&
        other.syncPolicy == syncPolicy &&
        other.lowDataMode == lowDataMode &&
        other.backgroundSyncEnabled == backgroundSyncEnabled &&
        other.appLockEnabled == appLockEnabled &&
        other.languageOverride == languageOverride &&
        other.trialStartDate == trialStartDate &&
        other.isUpgraded == isUpgraded &&
        const ListEquality<String>().equals(other.categories, categories) &&
        other.selectedRegion == selectedRegion;
  }

  @override
  int get hashCode => Object.hash(
        country,
        storageMode,
        syncPolicy,
        lowDataMode,
        backgroundSyncEnabled,
        appLockEnabled,
        languageOverride,
        trialStartDate,
        isUpgraded,
        const ListEquality<String>().hash(categories),
        selectedRegion,
      );

  @override
  String toString() =>
      'AppSettings(country: $country, region: $selectedRegion, '
      'storage: ${_storageModeToString(storageMode)}, '
      'upgraded: $isUpgraded)';
}
