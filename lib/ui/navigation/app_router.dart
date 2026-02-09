/// Centralized route management for the Kira app.
///
/// All named routes are defined in [AppRoutes]. The [AppRouter] class
/// provides route generation with guards based on trial/upgrade status.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/trial_service.dart';
import '../../main.dart';
import '../screens/admin/admin_panel_screen.dart';
import '../screens/admin/error_panel_screen.dart';
import '../screens/alerts_screen.dart';
import '../screens/capture_screen.dart';
import '../screens/home_screen.dart';
import '../screens/integrations_screen.dart';
import '../screens/onboarding/onboarding_flow.dart';
import '../screens/reports_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/trial_welcome_screen.dart';
import '../screens/upgrade_wall_screen.dart';

// ---------------------------------------------------------------------------
// Route constants
// ---------------------------------------------------------------------------

abstract final class AppRoutes {
  static const String trialWelcome = '/trial-welcome';
  static const String home = '/home';
  static const String capture = '/capture';
  static const String upgrade = '/upgrade';
  static const String backfill = '/backfill';

  // Onboarding
  static const String onboardingFlow = '/onboarding';
  static const String onboardingCountry = '/onboarding/country';
  static const String onboardingRetention = '/onboarding/retention';
  static const String onboardingPaperDisclaimer = '/onboarding/paper-disclaimer';
  static const String onboardingStorage = '/onboarding/storage';
  static const String onboardingCloudLogin = '/onboarding/cloud-login';
  static const String onboardingSyncPolicy = '/onboarding/sync-policy';
  static const String onboardingBackfill = '/onboarding/backfill';

  // Receipt screens
  static const String receiptDetail = '/receipt'; // expects /:id
  static const String receiptsDay = '/receipts/day'; // expects /:date

  // Tabs (navigated via bottom nav, not as push routes)
  static const String reports = '/reports';
  static const String alerts = '/alerts';
  static const String settings = '/settings';

  // Integrations
  static const String integrations = '/integrations';

  // Business mode
  static const String businessWorkspaces = '/business/workspaces';
  static const String businessTrips = '/business/trips';
  static const String businessReports = '/business/reports';

  // Admin
  static const String adminPanel = '/admin';
  static const String adminMetrics = '/admin/metrics';
  static const String adminErrors = '/admin/errors';
}

// ---------------------------------------------------------------------------
// AppRouter
// ---------------------------------------------------------------------------

class AppRouter {
  AppRouter._();

  /// Central route generation callback for [MaterialApp.onGenerateRoute].
  static Route<dynamic> onGenerateRoute(RouteSettings routeSettings) {
    final String? name = routeSettings.name;

    // Parse dynamic segments.
    final uri = Uri.parse(name ?? '');
    final segments = uri.pathSegments;

    switch (name) {
      case AppRoutes.trialWelcome:
        return _buildRoute(
          routeSettings,
          const TrialWelcomeScreen(),
        );

      case AppRoutes.home:
        return _buildRoute(
          routeSettings,
          const HomeScreen(),
        );

      case AppRoutes.capture:
        return _buildGuardedCaptureRoute(routeSettings);

      case AppRoutes.upgrade:
        return _buildRoute(
          routeSettings,
          const UpgradeWallScreen(),
        );

      case AppRoutes.onboardingFlow:
        return _buildRoute(
          routeSettings,
          const OnboardingFlow(),
        );

      case AppRoutes.adminPanel:
        return _buildRoute(
          routeSettings,
          const AdminPanelScreen(),
        );

      case AppRoutes.adminErrors:
        return _buildRoute(
          routeSettings,
          const ErrorPanelScreen(),
        );

      case AppRoutes.settings:
        return _buildRoute(
          routeSettings,
          const SettingsScreen(),
        );

      case AppRoutes.alerts:
        return _buildRoute(
          routeSettings,
          const AlertsScreen(),
        );

      case AppRoutes.reports:
        return _buildRoute(
          routeSettings,
          const ReportsScreen(),
        );

      case AppRoutes.integrations:
        return _buildRoute(
          routeSettings,
          const IntegrationsScreen(),
        );

      default:
        // Handle parameterized routes.
        if (segments.length == 2 && segments[0] == 'receipt') {
          final receiptId = segments[1];
          return _buildRoute(
            routeSettings,
            _ReceiptDetailPlaceholder(receiptId: receiptId),
          );
        }
        if (segments.length == 3 &&
            segments[0] == 'receipts' &&
            segments[1] == 'day') {
          final date = segments[2];
          return _buildRoute(
            routeSettings,
            _DayReceiptsPlaceholder(date: date),
          );
        }

        // Fallback for unregistered routes.
        return _buildRoute(
          routeSettings,
          const _NotFoundScreen(),
        );
    }
  }

  // -------------------------------------------------------------------------
  // Route builders
  // -------------------------------------------------------------------------

  static MaterialPageRoute<dynamic> _buildRoute(
    RouteSettings settings,
    Widget page,
  ) {
    return MaterialPageRoute<dynamic>(
      settings: settings,
      builder: (_) => page,
    );
  }

  /// Guard: only allow navigation to capture if the user can capture.
  /// If the trial is expired and user is not upgraded, redirect to the
  /// upgrade wall.
  static Route<dynamic> _buildGuardedCaptureRoute(RouteSettings settings) {
    return MaterialPageRoute<dynamic>(
      settings: settings,
      builder: (context) {
        final trial = context.read<TrialService>();
        if (!trial.canCapture) {
          return const UpgradeWallScreen();
        }
        return const CaptureScreen();
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Placeholder screens for routes not in this Part 1 delivery
// ---------------------------------------------------------------------------

/// Placeholder for the receipt detail screen (delivered in a later part).
class _ReceiptDetailPlaceholder extends StatelessWidget {
  final String receiptId;
  const _ReceiptDetailPlaceholder({required this.receiptId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(child: Text('Receipt: $receiptId')),
    );
  }
}

/// Placeholder for the day receipts list screen.
class _DayReceiptsPlaceholder extends StatelessWidget {
  final String date;
  const _DayReceiptsPlaceholder({required this.date});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(child: Text('Receipts for $date')),
    );
  }
}

/// Fallback screen for unknown routes.
class _NotFoundScreen extends StatelessWidget {
  const _NotFoundScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: const Center(child: Text('404 - Page Not Found')),
    );
  }
}
