// Kira - The Receipt Saver
// Empty state widget with illustration placeholder and message.

import 'package:flutter/material.dart';

import '../theme/kira_icons.dart';
import '../theme/kira_theme.dart';
import 'kira_button.dart';

// ---------------------------------------------------------------------------
// KiraEmptyState
// ---------------------------------------------------------------------------

/// A full-area empty state widget shown when a list or section has no content.
///
/// Displays a large icon (or custom illustration), a title, a description, and
/// an optional call-to-action button.
///
/// ```dart
/// KiraEmptyState(
///   icon: KiraIcons.receipt,
///   title: l10n.noReceipts,
///   description: l10n.noReceiptsDescription,
///   actionLabel: l10n.captureReceipt,
///   onAction: _openCamera,
/// )
/// ```
class KiraEmptyState extends StatelessWidget {
  /// Large icon displayed as a placeholder illustration.
  final IconData? icon;

  /// Custom illustration widget. Takes precedence over [icon].
  final Widget? illustration;

  /// Title text (e.g. "No receipts yet").
  final String title;

  /// Description text (e.g. "Tap the camera button to capture your first receipt.").
  final String? description;

  /// Optional call-to-action button label.
  final String? actionLabel;

  /// Called when the action button is tapped.
  final VoidCallback? onAction;

  /// Icon on the action button.
  final IconData? actionIcon;

  /// Whether to compact the layout (useful inside smaller containers).
  final bool compact;

  const KiraEmptyState({
    super.key,
    this.icon,
    this.illustration,
    required this.title,
    this.description,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
    this.compact = false,
  });

  // ---- Convenience constructors ----

  /// Empty state for the receipts list.
  const KiraEmptyState.noReceipts({
    super.key,
    required this.title,
    this.description,
    this.actionLabel,
    this.onAction,
  })  : icon = KiraIcons.receipt,
        illustration = null,
        actionIcon = KiraIcons.camera,
        compact = false;

  /// Empty state for search results.
  const KiraEmptyState.noResults({
    super.key,
    required this.title,
    this.description,
  })  : icon = KiraIcons.search,
        illustration = null,
        actionLabel = null,
        onAction = null,
        actionIcon = null,
        compact = false;

  /// Empty state for alerts.
  const KiraEmptyState.noAlerts({
    super.key,
    required this.title,
    this.description,
  })  : icon = KiraIcons.alerts,
        illustration = null,
        actionLabel = null,
        onAction = null,
        actionIcon = null,
        compact = false;

  /// Empty state for reports.
  const KiraEmptyState.noReports({
    super.key,
    required this.title,
    this.description,
    this.actionLabel,
    this.onAction,
  })  : icon = KiraIcons.reports,
        illustration = null,
        actionIcon = null,
        compact = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final isLight = theme.brightness == Brightness.light;

    final iconSize = compact ? KiraDimens.iconXl : KiraDimens.iconXl * 1.5;
    final verticalSpacing = compact ? KiraDimens.spacingMd : KiraDimens.spacingXl;

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: KiraDimens.spacingXxl,
          vertical: compact ? KiraDimens.spacingLg : KiraDimens.spacingXxxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Illustration / icon
            illustration ??
                _buildIconPlaceholder(
                  colorScheme: colorScheme,
                  isLight: isLight,
                  iconSize: iconSize,
                ),

            SizedBox(height: verticalSpacing),

            // Title
            Text(
              title,
              style: (compact ? textTheme.titleMedium : textTheme.titleLarge)
                  ?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),

            // Description
            if (description != null) ...[
              const SizedBox(height: KiraDimens.spacingSm),
              Text(
                description!,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withAlpha(153),
                ),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            // Action button
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: verticalSpacing),
              KiraButton.primary(
                label: actionLabel!,
                icon: actionIcon,
                onPressed: onAction,
                size: compact ? KiraButtonSize.small : KiraButtonSize.medium,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildIconPlaceholder({
    required ColorScheme colorScheme,
    required bool isLight,
    required double iconSize,
  }) {
    final effectiveIcon = icon ?? KiraIcons.receipt;

    return Container(
      width: iconSize + KiraDimens.spacingXxl,
      height: iconSize + KiraDimens.spacingXxl,
      decoration: BoxDecoration(
        color: isLight
            ? colorScheme.primary.withAlpha(20)
            : colorScheme.primary.withAlpha(26),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Icon(
          effectiveIcon,
          size: iconSize,
          color: colorScheme.primary.withAlpha(128),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// KiraEmptyStateSliver – sliver-compatible variant
// ---------------------------------------------------------------------------

/// A sliver wrapper around [KiraEmptyState] for use inside
/// [CustomScrollView] / slivers.
class KiraEmptyStateSliver extends StatelessWidget {
  final KiraEmptyState child;

  const KiraEmptyStateSliver({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: child,
    );
  }
}
