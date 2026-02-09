// Kira - The Receipt Saver
// Bottom navigation bar with 4 tabs: Home, Reports, Alerts, Settings.
// Icon-forward design with pastel active states.

import 'package:flutter/material.dart';

import '../theme/kira_icons.dart';
import '../theme/kira_theme.dart';

// ---------------------------------------------------------------------------
// Tab definition
// ---------------------------------------------------------------------------

/// Describes a single tab in the [KiraBottomNav].
class KiraNavTab {
  /// The icon shown when the tab is inactive.
  final IconData icon;

  /// The icon shown when the tab is active. Falls back to [icon].
  final IconData? activeIcon;

  /// The label displayed below the icon.
  final String label;

  /// Optional badge count. Shows a small badge when > 0.
  final int badgeCount;

  const KiraNavTab({
    required this.icon,
    this.activeIcon,
    required this.label,
    this.badgeCount = 0,
  });
}

// ---------------------------------------------------------------------------
// Default tabs
// ---------------------------------------------------------------------------

/// The four default navigation tabs for Kira.
///
/// Label strings are intentionally plain English here; screens should override
/// with localised values via [KiraBottomNav.tabs] or use the helper
/// [KiraBottomNav.defaultLocalised].
class KiraDefaultTabs {
  KiraDefaultTabs._();

  static const List<KiraNavTab> tabs = [
    KiraNavTab(
      icon: KiraIcons.home,
      label: 'Home',
    ),
    KiraNavTab(
      icon: KiraIcons.reports,
      label: 'Reports',
    ),
    KiraNavTab(
      icon: KiraIcons.alerts,
      label: 'Alerts',
    ),
    KiraNavTab(
      icon: KiraIcons.settings,
      label: 'Settings',
    ),
  ];
}

// ---------------------------------------------------------------------------
// KiraBottomNav
// ---------------------------------------------------------------------------

/// A bottom navigation bar styled with the Kira pastel palette.
///
/// Features:
/// - Icon-forward layout with optional active-icon variants
/// - Pastel tinted active indicator
/// - Badge support for the Alerts tab (or any tab)
/// - Accessible labels and semantics
///
/// ```dart
/// KiraBottomNav(
///   currentIndex: _selectedIndex,
///   onTap: (i) => setState(() => _selectedIndex = i),
/// )
/// ```
class KiraBottomNav extends StatelessWidget {
  /// The currently selected tab index.
  final int currentIndex;

  /// Called when a tab is tapped.
  final ValueChanged<int> onTap;

  /// The tabs to display. Defaults to [KiraDefaultTabs.tabs].
  final List<KiraNavTab>? tabs;

  const KiraBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.tabs,
  });

  /// Creates a [KiraBottomNav] with localised tab labels.
  ///
  /// Pass the four localised strings directly:
  /// ```dart
  /// KiraBottomNav.defaultLocalised(
  ///   currentIndex: _index,
  ///   onTap: (i) => setState(() => _index = i),
  ///   homeLabel: l10n.home,
  ///   reportsLabel: l10n.reports,
  ///   alertsLabel: l10n.alerts,
  ///   settingsLabel: l10n.settings,
  ///   alertsBadgeCount: _unreadAlerts,
  /// )
  /// ```
  factory KiraBottomNav.defaultLocalised({
    Key? key,
    required int currentIndex,
    required ValueChanged<int> onTap,
    required String homeLabel,
    required String reportsLabel,
    required String alertsLabel,
    required String settingsLabel,
    int alertsBadgeCount = 0,
  }) {
    return KiraBottomNav(
      key: key,
      currentIndex: currentIndex,
      onTap: onTap,
      tabs: [
        KiraNavTab(icon: KiraIcons.home, label: homeLabel),
        KiraNavTab(icon: KiraIcons.reports, label: reportsLabel),
        KiraNavTab(
          icon: KiraIcons.alerts,
          label: alertsLabel,
          badgeCount: alertsBadgeCount,
        ),
        KiraNavTab(icon: KiraIcons.settings, label: settingsLabel),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveTabs = tabs ?? KiraDefaultTabs.tabs;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isLight = theme.brightness == Brightness.light;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isLight ? 13 : 31),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: KiraDimens.bottomNavHeight,
          child: Row(
            children: List.generate(effectiveTabs.length, (index) {
              return Expanded(
                child: _NavItem(
                  tab: effectiveTabs[index],
                  isSelected: index == currentIndex,
                  onTap: () => onTap(index),
                  colorScheme: colorScheme,
                  textTheme: theme.textTheme,
                  isLight: isLight,
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _NavItem (private)
// ---------------------------------------------------------------------------

class _NavItem extends StatelessWidget {
  final KiraNavTab tab;
  final bool isSelected;
  final VoidCallback onTap;
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final bool isLight;

  const _NavItem({
    required this.tab,
    required this.isSelected,
    required this.onTap,
    required this.colorScheme,
    required this.textTheme,
    required this.isLight,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = colorScheme.primary;
    final inactiveColor = colorScheme.onSurface.withAlpha(128);
    final color = isSelected ? activeColor : inactiveColor;

    return Semantics(
      label: tab.label,
      selected: isSelected,
      button: true,
      child: InkResponse(
        onTap: onTap,
        highlightShape: BoxShape.rectangle,
        containedInkWell: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Active indicator pill
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              height: 3,
              width: isSelected ? 24 : 0,
              margin: const EdgeInsets.only(bottom: KiraDimens.spacingXs),
              decoration: BoxDecoration(
                color: isSelected ? activeColor : Colors.transparent,
                borderRadius: BorderRadius.circular(KiraDimens.radiusFull),
              ),
            ),

            // Icon with optional badge
            _buildIcon(color),

            const SizedBox(height: KiraDimens.spacingXxs),

            // Label
            Text(
              tab.label,
              style: textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 10,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIcon(Color color) {
    final iconData = isSelected ? (tab.activeIcon ?? tab.icon) : tab.icon;
    final icon = Icon(iconData, size: KiraDimens.iconMd, color: color);

    if (tab.badgeCount <= 0) return icon;

    return Badge(
      label: Text(
        tab.badgeCount > 99 ? '99+' : tab.badgeCount.toString(),
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: KiraColors.white,
        ),
      ),
      backgroundColor: KiraColors.failedRed,
      child: icon,
    );
  }
}
