// Kira - The Receipt Saver
// Receipt card widget with soft shadows, rounded corners, icon-forward layout.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/kira_icons.dart';
import '../theme/kira_theme.dart';

// ---------------------------------------------------------------------------
// Receipt card data model (presentation-only)
// ---------------------------------------------------------------------------

/// Lightweight data object that drives a [KiraReceiptCard].
///
/// This is a UI model, not a domain entity. Feature-layer code should map its
/// own receipt model into this before passing to the card.
class ReceiptCardData {
  final String id;
  final DateTime date;
  final double amount;
  final String currencyCode; // "CAD" or "USD"
  final String categoryKey; // matches l10n keys like "meals", "travel" etc.
  final String? merchantName;
  final String? notes;

  /// One of: "synced", "pending", "failed", "offline".
  final String syncStatus;

  /// Whether this receipt has an integrity alert.
  final bool hasIntegrityAlert;

  const ReceiptCardData({
    required this.id,
    required this.date,
    required this.amount,
    this.currencyCode = 'CAD',
    this.categoryKey = 'other',
    this.merchantName,
    this.notes,
    this.syncStatus = 'pending',
    this.hasIntegrityAlert = false,
  });
}

// ---------------------------------------------------------------------------
// KiraReceiptCard
// ---------------------------------------------------------------------------

/// An icon-forward receipt card that shows date, amount, category, and sync
/// status at a glance.
///
/// Designed for list views with soft shadows and rounded corners following
/// the Kira pastel aesthetic.
class KiraReceiptCard extends StatelessWidget {
  /// The data to display.
  final ReceiptCardData data;

  /// Called when the card is tapped.
  final VoidCallback? onTap;

  /// Called when the card is long-pressed (e.g. to show a context menu).
  final VoidCallback? onLongPress;

  /// Whether to show the sync status badge.
  final bool showSyncStatus;

  /// Optional trailing widget (overrides the default sync-status chip).
  final Widget? trailing;

  const KiraReceiptCard({
    super.key,
    required this.data,
    this.onTap,
    this.onLongPress,
    this.showSyncStatus = true,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final isLight = theme.brightness == Brightness.light;

    return Semantics(
      label: 'Receipt ${data.merchantName ?? data.categoryKey}, '
          '${_formatAmount(data.amount, data.currencyCode)}, '
          '${_formatDate(data.date)}',
      button: onTap != null,
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: KiraDimens.spacingLg,
          vertical: KiraDimens.spacingSm,
        ),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(KiraDimens.radiusMd),
          boxShadow: KiraShadows.soft(),
          border: data.hasIntegrityAlert
              ? Border.all(color: KiraColors.failedRed.withAlpha(128), width: 1.5)
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(KiraDimens.radiusMd),
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            borderRadius: BorderRadius.circular(KiraDimens.radiusMd),
            child: Padding(
              padding: const EdgeInsets.all(KiraDimens.spacingLg),
              child: Row(
                children: [
                  // ---- Category icon ----
                  _buildCategoryIcon(colorScheme, isLight),

                  const SizedBox(width: KiraDimens.spacingMd),

                  // ---- Content ----
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Top row: merchant/category + amount
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                data.merchantName ??
                                    _categoryLabel(data.categoryKey),
                                style: textTheme.titleSmall,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                            const SizedBox(width: KiraDimens.spacingSm),
                            Text(
                              _formatAmount(data.amount, data.currencyCode),
                              style: textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: colorScheme.primary,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: KiraDimens.spacingXs),

                        // Bottom row: date + sync/integrity status
                        Row(
                          children: [
                            Icon(
                              KiraIcons.calendar,
                              size: KiraDimens.iconSm - 4,
                              color: colorScheme.onSurface.withAlpha(128),
                            ),
                            const SizedBox(width: KiraDimens.spacingXs),
                            Text(
                              _formatDate(data.date),
                              style: textTheme.bodySmall,
                            ),
                            if (data.notes != null &&
                                data.notes!.isNotEmpty) ...[
                              const SizedBox(width: KiraDimens.spacingSm),
                              Icon(
                                KiraIcons.textFields,
                                size: KiraDimens.iconSm - 4,
                                color: colorScheme.onSurface.withAlpha(102),
                              ),
                            ],
                            const Spacer(),
                            if (trailing != null)
                              trailing!
                            else if (showSyncStatus)
                              _buildSyncBadge(context),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------- Category icon ----------

  Widget _buildCategoryIcon(ColorScheme colorScheme, bool isLight) {
    final categoryColor = _categoryColor(data.categoryKey);
    return Container(
      width: KiraDimens.iconXl,
      height: KiraDimens.iconXl,
      decoration: BoxDecoration(
        color: categoryColor.withAlpha(isLight ? 31 : 46),
        borderRadius: BorderRadius.circular(KiraDimens.radiusSm),
      ),
      child: Center(
        child: Icon(
          KiraIcons.categoryIcon(data.categoryKey),
          size: KiraDimens.iconMd,
          color: categoryColor,
        ),
      ),
    );
  }

  // ---------- Sync badge ----------

  Widget _buildSyncBadge(BuildContext context) {
    final theme = Theme.of(context);

    if (data.hasIntegrityAlert) {
      return _StatusChip(
        icon: KiraIcons.warning,
        color: KiraColors.failedRed,
        textTheme: theme.textTheme,
      );
    }

    final Color statusColor;
    switch (data.syncStatus) {
      case 'synced':
        statusColor = KiraColors.syncedGreen;
        break;
      case 'pending':
        statusColor = KiraColors.pendingAmber;
        break;
      case 'failed':
        statusColor = KiraColors.failedRed;
        break;
      default:
        statusColor = KiraColors.mediumGrey;
    }

    return _StatusChip(
      icon: KiraIcons.syncStatusIcon(data.syncStatus),
      color: statusColor,
      textTheme: theme.textTheme,
    );
  }

  // ---------- Helpers ----------

  static String _formatAmount(double amount, String currency) {
    final format = NumberFormat.currency(
      symbol: currency == 'USD' ? '\$' : '\$',
      decimalDigits: 2,
    );
    final suffix = currency == 'USD' ? ' USD' : ' CAD';
    return '${format.format(amount)}$suffix';
  }

  static String _formatDate(DateTime date) {
    return DateFormat.yMMMd().format(date);
  }

  static String _categoryLabel(String key) {
    // Capitalise first letter as fallback when localisation is unavailable.
    if (key.isEmpty) return 'Other';
    return key[0].toUpperCase() + key.substring(1);
  }

  static Color _categoryColor(String key) {
    switch (key.toLowerCase()) {
      case 'meals':
        return KiraColors.categoryMeals;
      case 'travel':
        return KiraColors.categoryTravel;
      case 'office':
        return KiraColors.categoryOffice;
      case 'supplies':
        return KiraColors.categorySupplies;
      case 'fuel':
        return KiraColors.categoryFuel;
      case 'lodging':
        return KiraColors.categoryLodging;
      default:
        return KiraColors.categoryOther;
    }
  }
}

// ---------------------------------------------------------------------------
// _StatusChip (private)
// ---------------------------------------------------------------------------

class _StatusChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final TextTheme textTheme;

  const _StatusChip({
    required this.icon,
    required this.color,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(KiraDimens.spacingXs),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(KiraDimens.radiusSm),
      ),
      child: Icon(
        icon,
        size: KiraDimens.iconSm,
        color: color,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// KiraCard – generic card wrapper
// ---------------------------------------------------------------------------

/// A simple card container using Kira design tokens.
///
/// For receipt-specific layouts, use [KiraReceiptCard] instead.
class KiraCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? backgroundColor;
  final List<BoxShadow>? boxShadow;
  final Border? border;

  const KiraCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.margin,
    this.backgroundColor,
    this.boxShadow,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: margin ??
          const EdgeInsets.symmetric(
            horizontal: KiraDimens.spacingLg,
            vertical: KiraDimens.spacingSm,
          ),
      decoration: BoxDecoration(
        color: backgroundColor ?? colorScheme.surface,
        borderRadius: BorderRadius.circular(KiraDimens.radiusMd),
        boxShadow: boxShadow ?? KiraShadows.soft(),
        border: border,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(KiraDimens.radiusMd),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(KiraDimens.radiusMd),
          child: Padding(
            padding: padding ?? const EdgeInsets.all(KiraDimens.spacingLg),
            child: child,
          ),
        ),
      ),
    );
  }
}
