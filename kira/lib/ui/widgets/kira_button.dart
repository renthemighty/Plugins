// Kira - The Receipt Saver
// Primary / secondary / text button styles with pastel theming and loading states.

import 'package:flutter/material.dart';

import '../theme/kira_theme.dart';

// ---------------------------------------------------------------------------
// Button variant enum
// ---------------------------------------------------------------------------

/// The visual style of a [KiraButton].
enum KiraButtonVariant {
  /// Filled button with the primary colour.
  primary,

  /// Outlined button with the primary colour border.
  secondary,

  /// Text-only button, no background or border.
  text,

  /// Destructive action – uses the error colour.
  danger,
}

/// The size preset for a [KiraButton].
enum KiraButtonSize {
  small,
  medium,
  large,
}

// ---------------------------------------------------------------------------
// KiraButton
// ---------------------------------------------------------------------------

/// A versatile button that follows the Kira design language.
///
/// Supports [KiraButtonVariant] for visual style, an optional loading spinner,
/// leading/trailing icons, and disabled state.
///
/// ```dart
/// KiraButton(
///   label: 'Save Receipt',
///   icon: KiraIcons.save,
///   onPressed: _handleSave,
///   isLoading: _saving,
/// )
/// ```
class KiraButton extends StatelessWidget {
  /// Button label text.
  final String label;

  /// Called when the button is tapped.
  final VoidCallback? onPressed;

  /// Visual variant.
  final KiraButtonVariant variant;

  /// Size preset.
  final KiraButtonSize size;

  /// When true, shows a spinner and disables interaction.
  final bool isLoading;

  /// Leading icon (left of label).
  final IconData? icon;

  /// Trailing icon (right of label).
  final IconData? trailingIcon;

  /// Whether the button stretches to fill the available width.
  final bool expanded;

  /// Optional semantic label for accessibility.
  final String? semanticLabel;

  const KiraButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = KiraButtonVariant.primary,
    this.size = KiraButtonSize.medium,
    this.isLoading = false,
    this.icon,
    this.trailingIcon,
    this.expanded = false,
    this.semanticLabel,
  });

  // Convenience named constructors

  const KiraButton.primary({
    super.key,
    required this.label,
    this.onPressed,
    this.size = KiraButtonSize.medium,
    this.isLoading = false,
    this.icon,
    this.trailingIcon,
    this.expanded = false,
    this.semanticLabel,
  }) : variant = KiraButtonVariant.primary;

  const KiraButton.secondary({
    super.key,
    required this.label,
    this.onPressed,
    this.size = KiraButtonSize.medium,
    this.isLoading = false,
    this.icon,
    this.trailingIcon,
    this.expanded = false,
    this.semanticLabel,
  }) : variant = KiraButtonVariant.secondary;

  const KiraButton.text({
    super.key,
    required this.label,
    this.onPressed,
    this.size = KiraButtonSize.medium,
    this.isLoading = false,
    this.icon,
    this.trailingIcon,
    this.expanded = false,
    this.semanticLabel,
  }) : variant = KiraButtonVariant.text;

  const KiraButton.danger({
    super.key,
    required this.label,
    this.onPressed,
    this.size = KiraButtonSize.medium,
    this.isLoading = false,
    this.icon,
    this.trailingIcon,
    this.expanded = false,
    this.semanticLabel,
  }) : variant = KiraButtonVariant.danger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final effectiveOnPressed = isLoading ? null : onPressed;
    final child = _buildChild(context);

    Widget button;

    switch (variant) {
      case KiraButtonVariant.primary:
        button = ElevatedButton(
          onPressed: effectiveOnPressed,
          style: _primaryStyle(colorScheme),
          child: child,
        );
        break;

      case KiraButtonVariant.secondary:
        button = OutlinedButton(
          onPressed: effectiveOnPressed,
          style: _secondaryStyle(colorScheme),
          child: child,
        );
        break;

      case KiraButtonVariant.text:
        button = TextButton(
          onPressed: effectiveOnPressed,
          style: _textStyle(colorScheme),
          child: child,
        );
        break;

      case KiraButtonVariant.danger:
        button = ElevatedButton(
          onPressed: effectiveOnPressed,
          style: _dangerStyle(colorScheme),
          child: child,
        );
        break;
    }

    if (expanded) {
      button = SizedBox(width: double.infinity, child: button);
    }

    return Semantics(
      label: semanticLabel ?? label,
      button: true,
      enabled: onPressed != null && !isLoading,
      child: button,
    );
  }

  // ---------- Child (label + icons + spinner) ----------

  Widget _buildChild(BuildContext context) {
    final spinnerSize = _iconSize;

    if (isLoading) {
      return SizedBox(
        width: spinnerSize,
        height: spinnerSize,
        child: CircularProgressIndicator(
          strokeWidth: 2.0,
          valueColor: AlwaysStoppedAnimation<Color>(
            _spinnerColor(Theme.of(context).colorScheme),
          ),
        ),
      );
    }

    final children = <Widget>[];

    if (icon != null) {
      children.add(Icon(icon, size: _iconSize));
      children.add(const SizedBox(width: KiraDimens.spacingSm));
    }

    children.add(
      Flexible(
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
    );

    if (trailingIcon != null) {
      children.add(const SizedBox(width: KiraDimens.spacingSm));
      children.add(Icon(trailingIcon, size: _iconSize));
    }

    return Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: children,
    );
  }

  // ---------- Size tokens ----------

  EdgeInsets get _padding {
    switch (size) {
      case KiraButtonSize.small:
        return const EdgeInsets.symmetric(
          horizontal: KiraDimens.spacingLg,
          vertical: KiraDimens.spacingSm,
        );
      case KiraButtonSize.medium:
        return const EdgeInsets.symmetric(
          horizontal: KiraDimens.spacingXl,
          vertical: KiraDimens.spacingMd,
        );
      case KiraButtonSize.large:
        return const EdgeInsets.symmetric(
          horizontal: KiraDimens.spacingXxl,
          vertical: KiraDimens.spacingLg,
        );
    }
  }

  double get _iconSize {
    switch (size) {
      case KiraButtonSize.small:
        return KiraDimens.iconSm;
      case KiraButtonSize.medium:
        return KiraDimens.iconMd - 4;
      case KiraButtonSize.large:
        return KiraDimens.iconMd;
    }
  }

  double get _fontSize {
    switch (size) {
      case KiraButtonSize.small:
        return 12;
      case KiraButtonSize.medium:
        return 14;
      case KiraButtonSize.large:
        return 16;
    }
  }

  double get _borderRadius {
    switch (size) {
      case KiraButtonSize.small:
        return KiraDimens.radiusSm;
      case KiraButtonSize.medium:
        return KiraDimens.radiusMd;
      case KiraButtonSize.large:
        return KiraDimens.radiusMd;
    }
  }

  // ---------- Variant styles ----------

  ButtonStyle _primaryStyle(ColorScheme cs) {
    return ElevatedButton.styleFrom(
      backgroundColor: cs.primary,
      foregroundColor: cs.onPrimary,
      disabledBackgroundColor: cs.primary.withAlpha(97),
      disabledForegroundColor: cs.onPrimary.withAlpha(97),
      elevation: KiraDimens.elevationLow,
      padding: _padding,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_borderRadius),
      ),
      textStyle: TextStyle(
        fontSize: _fontSize,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  ButtonStyle _secondaryStyle(ColorScheme cs) {
    return OutlinedButton.styleFrom(
      foregroundColor: cs.primary,
      disabledForegroundColor: cs.primary.withAlpha(97),
      padding: _padding,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_borderRadius),
      ),
      side: BorderSide(
        color: onPressed != null ? cs.outline : cs.outline.withAlpha(97),
      ),
      textStyle: TextStyle(
        fontSize: _fontSize,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  ButtonStyle _textStyle(ColorScheme cs) {
    return TextButton.styleFrom(
      foregroundColor: cs.primary,
      disabledForegroundColor: cs.primary.withAlpha(97),
      padding: _padding,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_borderRadius),
      ),
      textStyle: TextStyle(
        fontSize: _fontSize,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  ButtonStyle _dangerStyle(ColorScheme cs) {
    return ElevatedButton.styleFrom(
      backgroundColor: cs.error,
      foregroundColor: cs.onError,
      disabledBackgroundColor: cs.error.withAlpha(97),
      disabledForegroundColor: cs.onError.withAlpha(97),
      elevation: KiraDimens.elevationLow,
      padding: _padding,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_borderRadius),
      ),
      textStyle: TextStyle(
        fontSize: _fontSize,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Color _spinnerColor(ColorScheme cs) {
    switch (variant) {
      case KiraButtonVariant.primary:
        return cs.onPrimary;
      case KiraButtonVariant.secondary:
      case KiraButtonVariant.text:
        return cs.primary;
      case KiraButtonVariant.danger:
        return cs.onError;
    }
  }
}

// ---------------------------------------------------------------------------
// KiraIconButton – a themed icon button
// ---------------------------------------------------------------------------

/// An icon-only button styled with the Kira design language.
class KiraIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final Color? backgroundColor;
  final double? size;
  final bool isLoading;

  const KiraIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.color,
    this.backgroundColor,
    this.size,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveSize = size ?? KiraDimens.iconMd;

    if (isLoading) {
      return SizedBox(
        width: effectiveSize + KiraDimens.spacingLg,
        height: effectiveSize + KiraDimens.spacingLg,
        child: Center(
          child: SizedBox(
            width: effectiveSize - 4,
            height: effectiveSize - 4,
            child: CircularProgressIndicator(
              strokeWidth: 2.0,
              valueColor: AlwaysStoppedAnimation<Color>(
                color ?? colorScheme.primary,
              ),
            ),
          ),
        ),
      );
    }

    final iconButton = IconButton(
      icon: Icon(icon, size: effectiveSize),
      onPressed: onPressed,
      color: color ?? colorScheme.onSurface,
      tooltip: tooltip,
      style: backgroundColor != null
          ? IconButton.styleFrom(
              backgroundColor: backgroundColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(KiraDimens.radiusSm),
              ),
            )
          : null,
    );

    return iconButton;
  }
}
