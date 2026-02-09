/// Kira - The Receipt Saver
///
/// Application entry point. Sets up the provider tree, initializes the local
/// database, runs an integrity audit, checks trial status, and routes the
/// user to the appropriate starting screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import 'core/db/database_helper.dart';
import 'core/db/receipt_dao.dart';
import 'core/db/settings_dao.dart';
import 'core/integrity/integrity_auditor.dart';
import 'core/services/reports_service.dart';
import 'core/services/trial_service.dart';
import 'core/sync/sync_engine.dart';
import 'ui/navigation/app_router.dart';
import 'ui/theme/kira_theme.dart';

// ---------------------------------------------------------------------------
// AppSettingsProvider
// ---------------------------------------------------------------------------

/// A [ChangeNotifier] that wraps [SettingsDao] and caches typed settings
/// in memory for synchronous access from the widget tree.
///
/// The provider loads all settings at initialization and exposes them as
/// simple getters. Writes go through the DAO and then update the in-memory
/// cache.
class AppSettingsProvider extends ChangeNotifier {
  final SettingsDao _dao;

  AppSettings _settings = const AppSettings();
  bool _initialized = false;

  AppSettingsProvider({required SettingsDao dao}) : _dao = dao;

  // ---- Getters -----------------------------------------------------------

  bool get initialized => _initialized;
  AppSettings get settings => _settings;

  String? get country => _settings.country;
  String? get storageMode => _settings.storageMode;
  String get syncPolicy => _settings.syncPolicy;
  bool get lowDataMode => _settings.lowDataMode;
  bool get backgroundSync => _settings.backgroundSync;
  bool get onboardingComplete => _settings.onboardingComplete;
  bool get isUpgraded => _settings.upgraded;
  String get language => _settings.language;
  String? get region => _settings.region;
  String get currencyCode => _settings.currencyCode;

  // ---- Initialization ----------------------------------------------------

  /// Bulk-loads all settings from the database.
  Future<void> initialize() async {
    _settings = await _dao.getAppSettings();
    _initialized = true;
    notifyListeners();
  }

  // ---- Setters (write-through) -------------------------------------------

  Future<void> setCountry(String value) async {
    await _dao.setCountry(value);
    _settings = await _dao.getAppSettings();
    notifyListeners();
  }

  Future<void> setStorageMode(String value) async {
    await _dao.setStorageMode(value);
    _settings = await _dao.getAppSettings();
    notifyListeners();
  }

  Future<void> setSyncPolicy(String value) async {
    await _dao.setSyncPolicy(value);
    _settings = await _dao.getAppSettings();
    notifyListeners();
  }

  Future<void> setLowDataMode(bool value) async {
    await _dao.setLowDataMode(value);
    _settings = await _dao.getAppSettings();
    notifyListeners();
  }

  Future<void> setOnboardingComplete(bool value) async {
    await _dao.setOnboardingComplete(value);
    _settings = await _dao.getAppSettings();
    notifyListeners();
  }

  Future<void> setLanguage(String value) async {
    await _dao.setLanguage(value);
    _settings = await _dao.getAppSettings();
    notifyListeners();
  }

  Future<void> setRegion(String value) async {
    await _dao.setRegion(value);
    _settings = await _dao.getAppSettings();
    notifyListeners();
  }

  Future<void> setRetentionAcknowledged(bool value) async {
    await _dao.setRetentionAcknowledged(value);
    _settings = await _dao.getAppSettings();
    notifyListeners();
  }

  Future<void> setPaperDisclaimerAcknowledged(bool value) async {
    await _dao.setPaperDisclaimerAcknowledged(value);
    _settings = await _dao.getAppSettings();
    notifyListeners();
  }

  Future<void> setBackgroundSync(bool value) async {
    await _dao.setBackgroundSync(value);
    _settings = await _dao.getAppSettings();
    notifyListeners();
  }
}

// ---------------------------------------------------------------------------
// main()
// ---------------------------------------------------------------------------

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the database first -- all other services depend on it.
  final dbHelper = DatabaseHelper();
  await dbHelper.database;

  // Build shared DAOs.
  final settingsDao = SettingsDao(dbHelper);
  final receiptDao = ReceiptDao(dbHelper);

  // Build services.
  final themeProvider = KiraThemeProvider()..initialize();
  final trialService = TrialService(
    settingsDao: settingsDao,
    receiptDao: receiptDao,
  );
  final syncEngine = SyncEngine(
    receiptDao: receiptDao,
    settingsDao: settingsDao,
  );
  final integrityAuditor = IntegrityAuditor(dbHelper);
  final reportsService = ReportsService(databaseHelper: dbHelper);
  final appSettings = AppSettingsProvider(dao: settingsDao);

  // Parallel initialization.
  await Future.wait([
    trialService.initialize(),
    syncEngine.initialize(),
    integrityAuditor.initialize(),
    appSettings.initialize(),
  ]);

  // Start trial on first launch if not already started.
  if (!trialService.hasTrialStarted) {
    await trialService.startTrial();
  }

  // Run integrity audit at launch (non-blocking).
  integrityAuditor.runAudit();

  // Purge expired trial receipts for non-upgraded users.
  if (!trialService.isUpgraded) {
    trialService.purgeExpiredReceipts();
  }

  // Determine the initial route.
  final String initialRoute;
  if (trialService.isUpgraded && appSettings.onboardingComplete) {
    initialRoute = AppRoutes.home;
  } else if (trialService.isTrialExpired) {
    initialRoute = AppRoutes.upgrade;
  } else {
    initialRoute = AppRoutes.trialWelcome;
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<KiraThemeProvider>.value(value: themeProvider),
        ChangeNotifierProvider<TrialService>.value(value: trialService),
        ChangeNotifierProvider<SyncEngine>.value(value: syncEngine),
        ChangeNotifierProvider<IntegrityAuditor>.value(value: integrityAuditor),
        Provider<ReportsService>.value(value: reportsService),
        ChangeNotifierProvider<AppSettingsProvider>.value(value: appSettings),
        Provider<ReceiptDao>.value(value: receiptDao),
        Provider<SettingsDao>.value(value: settingsDao),
      ],
      child: KiraApp(initialRoute: initialRoute),
    ),
  );
}

// ---------------------------------------------------------------------------
// KiraApp
// ---------------------------------------------------------------------------

class KiraApp extends StatelessWidget {
  final String initialRoute;

  const KiraApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<KiraThemeProvider>();

    return MaterialApp(
      title: 'Kira',
      debugShowCheckedModeBanner: false,

      // ---- Localization ----
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('fr'),
        Locale('fr', 'CA'),
        Locale('es'),
        Locale('es', 'US'),
      ],

      // ---- Theming ----
      theme: themeProvider.lightTheme,
      darkTheme: themeProvider.darkTheme,
      themeMode: themeProvider.themeMode,

      // ---- Routing ----
      initialRoute: initialRoute,
      onGenerateRoute: AppRouter.onGenerateRoute,
    );
  }
}
