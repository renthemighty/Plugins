// Kira - The Receipt Saver
// Custom app bar with pastel styling and optional branding logo.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/kira_icons.dart';
import '../theme/kira_theme.dart';

/// A styled [AppBar] that follows the Kira design language.
///
/// Supports an optional workspace logo (loaded from [KiraThemeProvider]),
/// custom actions, and a pastel-tinted background.
class KiraAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// The title displayed in the app bar.
  final String? title;

  /// A custom title widget. Takes precedence over [title].
  final Widget? titleWidget;

  /// Trailing action buttons.
  final List<Widget>? actions;

  /// Whether to show the workspace logo (from branding) as the leading widget.
  final bool showLogo;

  /// Custom leading widget. Takes precedence over logo.
  final Widget? leading;

  /// Whether the leading widget should be automatically implied (back arrow).
  final bool automaticallyImplyLeading;

  /// Optional bottom widget (e.g. a [TabBar] or search field).
  final PreferredSizeWidget? bottom;

  /// Background colour override. Defaults to the theme surface colour.
  final Color? backgroundColor;

  /// Elevation override.
  final double? elevation;

  const KiraAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.actions,
    this.showLogo = false,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.bottom,
    this.backgroundColor,
    this.elevation,
  });

  @override
  Size get preferredSize => Size.fromHeight(
        KiraDimens.appBarHeight + (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final themeProvider = context.watch<KiraThemeProvider>();

    Widget? leadingWidget = leading;
    if (leadingWidget == null && showLogo) {
      leadingWidget = _buildLogo(context, themeProvider);
    }

    return AppBar(
      leading: leadingWidget,
      automaticallyImplyLeading: automaticallyImplyLeading,
      title: titleWidget ?? (title != null ? Text(title!) : null),
      actions: actions,
      bottom: bottom,
      elevation: elevation ?? 0,
      scrolledUnderElevation: KiraDimens.elevationLow,
      backgroundColor: backgroundColor ?? colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: theme.textTheme.titleLarge?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: IconThemeData(
        color: colorScheme.onSurface,
        size: KiraDimens.iconMd,
      ),
    );
  }

  Widget? _buildLogo(BuildContext context, KiraThemeProvider themeProvider) {
    final branding = themeProvider.branding;
    if (!branding.hasLogo) {
      // Show the Kira icon placeholder when no custom logo is set.
      return Padding(
        padding: const EdgeInsets.all(KiraDimens.spacingSm),
        child: Icon(
          KiraIcons.logo,
          color: Theme.of(context).colorScheme.primary,
          size: KiraDimens.iconLg,
        ),
      );
    }

    final logoFile = File(branding.logoPath!);

    return Padding(
      padding: const EdgeInsets.all(KiraDimens.spacingSm),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(KiraDimens.radiusSm),
        child: Image.file(
          logoFile,
          width: KiraDimens.iconLg + KiraDimens.spacingSm,
          height: KiraDimens.iconLg,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Icon(
            KiraIcons.logo,
            color: Theme.of(context).colorScheme.primary,
            size: KiraDimens.iconLg,
          ),
        ),
      ),
    );
  }
}

/// A [SliverAppBar] variant using the Kira design language.
///
/// Useful for screens with scrollable content that want a collapsing header.
class KiraSliverAppBar extends StatelessWidget {
  final String? title;
  final Widget? titleWidget;
  final List<Widget>? actions;
  final bool showLogo;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final bool pinned;
  final bool floating;
  final bool snap;
  final double? expandedHeight;
  final Widget? flexibleSpace;

  const KiraSliverAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.actions,
    this.showLogo = false,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.pinned = true,
    this.floating = false,
    this.snap = false,
    this.expandedHeight,
    this.flexibleSpace,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SliverAppBar(
      leading: leading,
      automaticallyImplyLeading: automaticallyImplyLeading,
      title: titleWidget ?? (title != null ? Text(title!) : null),
      actions: actions,
      pinned: pinned,
      floating: floating,
      snap: snap,
      expandedHeight: expandedHeight,
      flexibleSpace: flexibleSpace,
      elevation: 0,
      scrolledUnderElevation: KiraDimens.elevationLow,
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: theme.textTheme.titleLarge?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
