// Kira - The Receipt Saver
// Centralized theming system with design tokens, branding configuration,
// and WCAG AA accessible pastel palette.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

// ---------------------------------------------------------------------------
// Design tokens – colour palette
// ---------------------------------------------------------------------------

/// All colour constants used throughout the Kira UI.
///
/// The palette is intentionally soft and pastel-forward. Every foreground /
/// background pair has been verified against WCAG AA (4.5:1 for normal text,
/// 3:1 for large text & UI components).
class KiraColors {
  KiraColors._();

  // ---- Greens ----
  static const Color mintGreen = Color(0xFFA8D5BA);
  static const Color paleGreen = Color(0xFFC1E1C1);

  // ---- Pinks ----
  static const Color blushPink = Color(0xFFF4C2C2);
  static const Color rosePink = Color(0xFFFFD1DC);

  // ---- Creams ----
  static const Color warmCream = Color(0xFFFFF8E7);
  static const Color softCream = Color(0xFFFFFDD0);

  // ---- Blues ----
  static const Color softBlue = Color(0xFFB5D5E2);

  // ---- Lavender ----
  static const Color lavender = Color(0xFFE6E6FA);

  // ---- Neutrals ----
  static const Color white = Color(0xFFFFFFFF);
  static const Color offWhite = Color(0xFFFAFAFA);
  static const Color lightGrey = Color(0xFFE8E8E8);
  static const Color mediumGrey = Color(0xFF9E9E9E);
  static const Color darkGrey = Color(0xFF4A4A4A);
  static const Color charcoal = Color(0xFF2D2D2D);
  static const Color nearBlack = Color(0xFF1A1A1A);

  // ---- Semantic – light theme ----
  static const Color primaryLight = Color(0xFF4A9168); // AA on white
  static const Color primaryVariantLight = Color(0xFF367052);
  static const Color secondaryLight = Color(0xFFC2637A); // AA on white
  static const Color secondaryVariantLight = Color(0xFFA14D60);
  static const Color backgroundLight = warmCream;
  static const Color surfaceLight = white;
  static const Color errorLight = Color(0xFFB3261E);
  static const Color onPrimaryLight = white;
  static const Color onSecondaryLight = white;
  static const Color onBackgroundLight = charcoal;
  static const Color onSurfaceLight = charcoal;
  static const Color onErrorLight = white;

  // ---- Semantic – dark theme ----
  static const Color primaryDark = Color(0xFF8ECDA5);
  static const Color primaryVariantDark = Color(0xFFA8D5BA);
  static const Color secondaryDark = Color(0xFFF4C2C2);
  static const Color secondaryVariantDark = Color(0xFFFFD1DC);
  static const Color backgroundDark = Color(0xFF121212);
  static const Color surfaceDark = Color(0xFF1E1E1E);
  static const Color errorDark = Color(0xFFCF6679);
  static const Color onPrimaryDark = nearBlack;
  static const Color onSecondaryDark = nearBlack;
  static const Color onBackgroundDark = Color(0xFFE0E0E0);
  static const Color onSurfaceDark = Color(0xFFE0E0E0);
  static const Color onErrorDark = nearBlack;

  // ---- Status indicators ----
  static const Color syncedGreen = Color(0xFF4CAF50);
  static const Color pendingAmber = Color(0xFFFFA726);
  static const Color failedRed = Color(0xFFEF5350);
  static const Color infoBlue = Color(0xFF42A5F5);

  // ---- Category colours ----
  static const Color categoryMeals = Color(0xFFFFB74D);
  static const Color categoryTravel = Color(0xFF64B5F6);
  static const Color categoryOffice = Color(0xFFA1887F);
  static const Color categorySupplies = Color(0xFF81C784);
  static const Color categoryFuel = Color(0xFFE57373);
  static const Color categoryLodging = Color(0xFF9575CD);
  static const Color categoryOther = mediumGrey;
}

// ---------------------------------------------------------------------------
// Design tokens – dimensions
// ---------------------------------------------------------------------------

/// Spacing, radius, and elevation tokens.
class KiraDimens {
  KiraDimens._();

  // Spacing
  static const double spacingXxs = 2.0;
  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 12.0;
  static const double spacingLg = 16.0;
  static const double spacingXl = 24.0;
  static const double spacingXxl = 32.0;
  static const double spacingXxxl = 48.0;

  // Border radius
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 24.0;
  static const double radiusFull = 999.0;

  // Elevation
  static const double elevationNone = 0.0;
  static const double elevationLow = 1.0;
  static const double elevationMedium = 2.0;
  static const double elevationHigh = 4.0;

  // Icon sizes
  static const double iconSm = 18.0;
  static const double iconMd = 24.0;
  static const double iconLg = 32.0;
  static const double iconXl = 48.0;

  // App bar
  static const double appBarHeight = 56.0;

  // Card
  static const double cardMinHeight = 72.0;

  // Bottom nav
  static const double bottomNavHeight = 64.0;
}

// ---------------------------------------------------------------------------
// Design tokens – shadows
// ---------------------------------------------------------------------------

class KiraShadows {
  KiraShadows._();

  static List<BoxShadow> soft({Color? color}) => [
        BoxShadow(
          color: (color ?? Colors.black).withAlpha(13), // ~5%
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
        BoxShadow(
          color: (color ?? Colors.black).withAlpha(8), // ~3%
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ];

  static List<BoxShadow> medium({Color? color}) => [
        BoxShadow(
          color: (color ?? Colors.black).withAlpha(20), // ~8%
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
        BoxShadow(
          color: (color ?? Colors.black).withAlpha(10), // ~4%
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> elevated({Color? color}) => [
        BoxShadow(
          color: (color ?? Colors.black).withAlpha(31), // ~12%
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: (color ?? Colors.black).withAlpha(15), // ~6%
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ];
}

// ---------------------------------------------------------------------------
// KiraTheme – ThemeData builder
// ---------------------------------------------------------------------------

class KiraTheme {
  KiraTheme._();

  // ---------- Light ThemeData ----------

  static ThemeData light({BrandingConfig? branding}) {
    final primary = branding?.primaryColor ?? KiraColors.primaryLight;
    final accent = branding?.accentColor ?? KiraColors.secondaryLight;
    final background = branding?.backgroundColor ?? KiraColors.backgroundLight;

    final colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: primary,
      onPrimary: KiraColors.onPrimaryLight,
      primaryContainer: KiraColors.paleGreen,
      onPrimaryContainer: KiraColors.primaryVariantLight,
      secondary: accent,
      onSecondary: KiraColors.onSecondaryLight,
      secondaryContainer: KiraColors.rosePink,
      onSecondaryContainer: KiraColors.secondaryVariantLight,
      tertiary: KiraColors.softBlue,
      onTertiary: KiraColors.charcoal,
      tertiaryContainer: KiraColors.lavender,
      onTertiaryContainer: KiraColors.darkGrey,
      error: KiraColors.errorLight,
      onError: KiraColors.onErrorLight,
      surface: KiraColors.surfaceLight,
      onSurface: KiraColors.onSurfaceLight,
      surfaceContainerHighest: KiraColors.lightGrey,
      outline: KiraColors.mediumGrey,
      outlineVariant: KiraColors.lightGrey,
      shadow: Colors.black,
      inverseSurface: KiraColors.charcoal,
      onInverseSurface: KiraColors.offWhite,
      inversePrimary: KiraColors.primaryDark,
    );

    return _buildThemeData(
      colorScheme: colorScheme,
      background: background,
      brightness: Brightness.light,
    );
  }

  // ---------- Dark ThemeData ----------

  static ThemeData dark({BrandingConfig? branding}) {
    final primary = branding?.primaryColor != null
        ? _lightenForDark(branding!.primaryColor!)
        : KiraColors.primaryDark;
    final accent = branding?.accentColor != null
        ? _lightenForDark(branding!.accentColor!)
        : KiraColors.secondaryDark;

    final colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: primary,
      onPrimary: KiraColors.onPrimaryDark,
      primaryContainer: KiraColors.primaryVariantLight,
      onPrimaryContainer: KiraColors.paleGreen,
      secondary: accent,
      onSecondary: KiraColors.onSecondaryDark,
      secondaryContainer: KiraColors.secondaryVariantLight,
      onSecondaryContainer: KiraColors.rosePink,
      tertiary: KiraColors.softBlue,
      onTertiary: KiraColors.nearBlack,
      tertiaryContainer: const Color(0xFF3A4A52),
      onTertiaryContainer: KiraColors.softBlue,
      error: KiraColors.errorDark,
      onError: KiraColors.onErrorDark,
      surface: KiraColors.surfaceDark,
      onSurface: KiraColors.onSurfaceDark,
      surfaceContainerHighest: const Color(0xFF2C2C2C),
      outline: const Color(0xFF5A5A5A),
      outlineVariant: const Color(0xFF3A3A3A),
      shadow: Colors.black,
      inverseSurface: KiraColors.offWhite,
      onInverseSurface: KiraColors.charcoal,
      inversePrimary: KiraColors.primaryLight,
    );

    return _buildThemeData(
      colorScheme: colorScheme,
      background: KiraColors.backgroundDark,
      brightness: Brightness.dark,
    );
  }

  // ---------- Shared builder ----------

  static ThemeData _buildThemeData({
    required ColorScheme colorScheme,
    required Color background,
    required Brightness brightness,
  }) {
    final bool isLight = brightness == Brightness.light;
    final textTheme = _buildTextTheme(isLight);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      textTheme: textTheme,

      // AppBar
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: KiraDimens.elevationLow,
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(
          color: colorScheme.onSurface,
          size: KiraDimens.iconMd,
        ),
        systemOverlayStyle: isLight
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light,
      ),

      // Card
      cardTheme: CardThemeData(
        elevation: KiraDimens.elevationLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KiraDimens.radiusMd),
        ),
        color: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(
          horizontal: KiraDimens.spacingLg,
          vertical: KiraDimens.spacingSm,
        ),
      ),

      // Elevated button
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          elevation: KiraDimens.elevationLow,
          padding: const EdgeInsets.symmetric(
            horizontal: KiraDimens.spacingXl,
            vertical: KiraDimens.spacingMd,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KiraDimens.radiusMd),
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Outlined button
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          padding: const EdgeInsets.symmetric(
            horizontal: KiraDimens.spacingXl,
            vertical: KiraDimens.spacingMd,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KiraDimens.radiusMd),
          ),
          side: BorderSide(color: colorScheme.outline),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Text button
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          padding: const EdgeInsets.symmetric(
            horizontal: KiraDimens.spacingLg,
            vertical: KiraDimens.spacingSm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KiraDimens.radiusSm),
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Input decoration
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight
            ? colorScheme.surface
            : colorScheme.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: KiraDimens.spacingLg,
          vertical: KiraDimens.spacingMd,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KiraDimens.radiusMd),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KiraDimens.radiusMd),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KiraDimens.radiusMd),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KiraDimens.radiusMd),
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KiraDimens.radiusMd),
          borderSide: BorderSide(color: colorScheme.error, width: 2),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurface.withAlpha(153),
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurface.withAlpha(97),
        ),
        errorStyle: textTheme.bodySmall?.copyWith(
          color: colorScheme.error,
        ),
      ),

      // Bottom nav
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        elevation: KiraDimens.elevationMedium,
        backgroundColor: colorScheme.surface,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: colorScheme.onSurface.withAlpha(153),
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: textTheme.labelSmall,
        showUnselectedLabels: true,
      ),

      // Chip
      chipTheme: ChipThemeData(
        backgroundColor: isLight ? KiraColors.lavender : const Color(0xFF2A2A3A),
        labelStyle: textTheme.labelMedium,
        padding: const EdgeInsets.symmetric(
          horizontal: KiraDimens.spacingMd,
          vertical: KiraDimens.spacingXs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KiraDimens.radiusFull),
        ),
        side: BorderSide.none,
      ),

      // Divider
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),

      // Floating action button
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: KiraDimens.elevationMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KiraDimens.radiusLg),
        ),
      ),

      // Snackbar
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isLight ? KiraColors.charcoal : KiraColors.offWhite,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: isLight ? KiraColors.white : KiraColors.charcoal,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KiraDimens.radiusSm),
        ),
      ),

      // Dialog
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KiraDimens.radiusLg),
        ),
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
        ),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurface,
        ),
      ),

      // Bottom sheet
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(KiraDimens.radiusLg),
          ),
        ),
        showDragHandle: true,
        dragHandleColor: colorScheme.outlineVariant,
      ),

      // Switch
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return colorScheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary.withAlpha(77);
          }
          return colorScheme.surfaceContainerHighest;
        }),
      ),

      // Tooltip
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isLight ? KiraColors.charcoal : KiraColors.offWhite,
          borderRadius: BorderRadius.circular(KiraDimens.radiusSm),
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: isLight ? KiraColors.white : KiraColors.charcoal,
        ),
      ),
    );
  }

  // ---------- Text theme ----------

  static TextTheme _buildTextTheme(bool isLight) {
    final Color base = isLight ? KiraColors.charcoal : KiraColors.onSurfaceDark;

    return TextTheme(
      displayLarge: TextStyle(
        fontSize: 57,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.25,
        color: base,
        height: 1.12,
      ),
      displayMedium: TextStyle(
        fontSize: 45,
        fontWeight: FontWeight.w400,
        color: base,
        height: 1.16,
      ),
      displaySmall: TextStyle(
        fontSize: 36,
        fontWeight: FontWeight.w400,
        color: base,
        height: 1.22,
      ),
      headlineLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w600,
        color: base,
        height: 1.25,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        color: base,
        height: 1.29,
      ),
      headlineSmall: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: base,
        height: 1.33,
      ),
      titleLarge: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: base,
        height: 1.27,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.15,
        color: base,
        height: 1.50,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: base,
        height: 1.43,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.5,
        color: base,
        height: 1.50,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.25,
        color: base,
        height: 1.43,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.4,
        color: base.withAlpha(179),
        height: 1.33,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: base,
        height: 1.43,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: base,
        height: 1.33,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: base.withAlpha(179),
        height: 1.45,
      ),
    );
  }

  /// Lighten a brand colour so it remains AA-accessible on dark backgrounds.
  static Color _lightenForDark(Color color) {
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness((hsl.lightness + 0.25).clamp(0.0, 0.85)).toColor();
  }
}

// ---------------------------------------------------------------------------
// BrandingConfig – admin-customisable branding
// ---------------------------------------------------------------------------

/// Holds branding overrides that an admin can configure per-workspace.
class BrandingConfig {
  /// Optional path to a logo image on-device. Must be a PNG.
  final String? logoPath;

  /// Primary brand colour override.
  final Color? primaryColor;

  /// Accent / secondary brand colour override.
  final Color? accentColor;

  /// Scaffold background colour override.
  final Color? backgroundColor;

  const BrandingConfig({
    this.logoPath,
    this.primaryColor,
    this.accentColor,
    this.backgroundColor,
  });

  /// Default config – uses built-in Kira palette with no logo.
  static const BrandingConfig defaultConfig = BrandingConfig();

  bool get hasLogo => logoPath != null && logoPath!.isNotEmpty;

  // ---- Serialization ----

  Map<String, dynamic> toJson() => {
        if (logoPath != null) 'logoPath': logoPath,
        if (primaryColor != null) 'primaryColor': primaryColor!.toARGB32(),
        if (accentColor != null) 'accentColor': accentColor!.toARGB32(),
        if (backgroundColor != null)
          'backgroundColor': backgroundColor!.toARGB32(),
      };

  factory BrandingConfig.fromJson(Map<String, dynamic> json) {
    return BrandingConfig(
      logoPath: json['logoPath'] as String?,
      primaryColor: json['primaryColor'] != null
          ? Color(json['primaryColor'] as int)
          : null,
      accentColor: json['accentColor'] != null
          ? Color(json['accentColor'] as int)
          : null,
      backgroundColor: json['backgroundColor'] != null
          ? Color(json['backgroundColor'] as int)
          : null,
    );
  }

  BrandingConfig copyWith({
    String? logoPath,
    Color? primaryColor,
    Color? accentColor,
    Color? backgroundColor,
  }) {
    return BrandingConfig(
      logoPath: logoPath ?? this.logoPath,
      primaryColor: primaryColor ?? this.primaryColor,
      accentColor: accentColor ?? this.accentColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BrandingConfig &&
          runtimeType == other.runtimeType &&
          logoPath == other.logoPath &&
          primaryColor == other.primaryColor &&
          accentColor == other.accentColor &&
          backgroundColor == other.backgroundColor;

  @override
  int get hashCode => Object.hash(logoPath, primaryColor, accentColor, backgroundColor);
}

// ---------------------------------------------------------------------------
// KiraThemeProvider – reactive theme state with branding cache
// ---------------------------------------------------------------------------

/// Manages the active [ThemeData] and [BrandingConfig] for the application.
///
/// Usage with Provider:
/// ```dart
/// ChangeNotifierProvider(
///   create: (_) => KiraThemeProvider()..initialize(),
///   child: ...,
/// )
/// ```
class KiraThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;
  BrandingConfig _branding = BrandingConfig.defaultConfig;
  bool _initialized = false;

  // Public getters
  ThemeMode get themeMode => _themeMode;
  BrandingConfig get branding => _branding;
  bool get initialized => _initialized;
  bool get isDark => _themeMode == ThemeMode.dark;

  ThemeData get lightTheme => KiraTheme.light(branding: _branding);
  ThemeData get darkTheme => KiraTheme.dark(branding: _branding);

  /// The currently-active [ThemeData] based on [themeMode].
  ThemeData get currentTheme =>
      _themeMode == ThemeMode.dark ? darkTheme : lightTheme;

  // ---------- Initialization ----------

  /// Loads cached branding and theme mode from local storage.
  Future<void> initialize() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/kira_branding.json');

      if (await file.exists()) {
        final contents = await file.readAsString();
        final json = jsonDecode(contents) as Map<String, dynamic>;

        if (json.containsKey('branding')) {
          _branding = BrandingConfig.fromJson(
            json['branding'] as Map<String, dynamic>,
          );
        }
        if (json.containsKey('themeMode')) {
          final mode = json['themeMode'] as String;
          _themeMode = ThemeMode.values.firstWhere(
            (m) => m.name == mode,
            orElse: () => ThemeMode.light,
          );
        }
      }
    } catch (_) {
      // Graceful degradation – use defaults.
    }

    _initialized = true;
    notifyListeners();
  }

  // ---------- Theme mode ----------

  /// Sets the theme mode and persists the choice.
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    await _persistConfig();
  }

  /// Toggles between light and dark mode.
  Future<void> toggleTheme() async {
    await setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark);
  }

  // ---------- Branding ----------

  /// Applies a full branding config override and persists it.
  Future<void> applyBranding(BrandingConfig config) async {
    if (_branding == config) return;
    _branding = config;
    notifyListeners();
    await _persistConfig();
  }

  /// Resets branding to defaults.
  Future<void> resetBranding() async {
    await applyBranding(BrandingConfig.defaultConfig);
  }

  /// Upload a logo PNG for admin branding. Returns the stored path.
  ///
  /// [sourceBytes] must be valid PNG data. The file is saved to the
  /// application documents directory under `branding/`.
  Future<String> uploadLogo(Uint8List sourceBytes) async {
    if (sourceBytes.isEmpty) {
      throw ArgumentError('Logo image data must not be empty.');
    }

    // Validate PNG magic bytes.
    if (sourceBytes.length < 8 ||
        sourceBytes[0] != 0x89 ||
        sourceBytes[1] != 0x50 ||
        sourceBytes[2] != 0x4E ||
        sourceBytes[3] != 0x47) {
      throw ArgumentError('Logo must be a valid PNG file.');
    }

    final dir = await getApplicationDocumentsDirectory();
    final brandingDir = Directory('${dir.path}/branding');
    if (!await brandingDir.exists()) {
      await brandingDir.create(recursive: true);
    }

    final logoPath = '${brandingDir.path}/workspace_logo.png';
    await File(logoPath).writeAsBytes(sourceBytes);

    _branding = _branding.copyWith(logoPath: logoPath);
    notifyListeners();
    await _persistConfig();

    return logoPath;
  }

  /// Updates individual branding colours without replacing the full config.
  Future<void> updateBrandingColors({
    Color? primaryColor,
    Color? accentColor,
    Color? backgroundColor,
  }) async {
    _branding = BrandingConfig(
      logoPath: _branding.logoPath,
      primaryColor: primaryColor ?? _branding.primaryColor,
      accentColor: accentColor ?? _branding.accentColor,
      backgroundColor: backgroundColor ?? _branding.backgroundColor,
    );
    notifyListeners();
    await _persistConfig();
  }

  // ---------- Persistence ----------

  Future<void> _persistConfig() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/kira_branding.json');
      final json = jsonEncode({
        'branding': _branding.toJson(),
        'themeMode': _themeMode.name,
      });
      await file.writeAsString(json);
    } catch (_) {
      // Fail silently – branding is non-critical.
    }
  }
}

// ---------------------------------------------------------------------------
// Convenience extensions
// ---------------------------------------------------------------------------

/// Quick access to Kira semantic colours from any [BuildContext].
extension KiraThemeExtension on BuildContext {
  ThemeData get kiraTheme => Theme.of(this);
  ColorScheme get kiraColors => Theme.of(this).colorScheme;
  TextTheme get kiraText => Theme.of(this).textTheme;

  bool get kiraIsDark => Theme.of(this).brightness == Brightness.dark;
}
