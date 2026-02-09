// Kira - The Receipt Saver
// Persistent banner widget for integrity alerts, trial status, and sync status.

import 'package:flutter/material.dart';

import '../theme/kira_icons.dart';
import '../theme/kira_theme.dart';

// ---------------------------------------------------------------------------
// Banner severity
// ---------------------------------------------------------------------------

/// The visual severity / intent of a [KiraBanner].
enum KiraBannerSeverity {
  /// Informational – uses the soft blue palette.
  info,

  /// Success confirmation – uses the green palette.
  success,

  /// Non-blocking warning – uses amber.
  warning,

  /// Error / integrity alert – uses red.
  error,

  /// Trial / promotional – uses lavender.
  trial,
}

// ---------------------------------------------------------------------------
// KiraBanner
// ---------------------------------------------------------------------------

/// A persistent banner displayed at the top of a screen to communicate
/// ongoing states such as integrity alerts, trial countdown, or sync status.
///
/// ```dart
/// KiraBanner(
///   severity: KiraBannerSeverity.warning,
///   message: l10n.integrityChecksumMismatch,
///   actionLabel: l10n.integrityQuarantine,
///   onAction: _quarantine,
///   onDismiss: _dismiss,
/// )
/// ```
class KiraBanner extends StatelessWidget {
  /// The banner message.
  final String message;

  /// Visual severity.
  final KiraBannerSeverity severity;

  /// Optional leading icon override. A default is chosen per [severity].
  final IconData? icon;

  /// Optional primary action label (e.g. "Upgrade Now", "Quarantine").
  final String? actionLabel;

  /// Called when the action button is tapped.
  final VoidCallback? onAction;

  /// Called when the dismiss button is tapped. If null, the banner is not
  /// dismissible.
  final VoidCallback? onDismiss;

  /// Optional secondary line of text below the message.
  final String? subtitle;

  /// Whether to show a progress indicator (e.g. for sync in progress).
  final bool showProgress;

  /// Progress value between 0.0 and 1.0. If null, an indeterminate indicator
  /// is shown when [showProgress] is true.
  final double? progressValue;

  const KiraBanner({
    super.key,
    required this.message,
    this.severity = KiraBannerSeverity.info,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
    this.subtitle,
    this.showProgress = false,
    this.progressValue,
  });

  // ---- Convenience constructors ----

  /// An integrity-alert banner.
  const KiraBanner.integrity({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
    this.subtitle,
  })  : severity = KiraBannerSeverity.error,
        icon = KiraIcons.integrity,
        showProgress = false,
        progressValue = null;

  /// A trial-status banner.
  const KiraBanner.trial({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
    this.subtitle,
  })  : severity = KiraBannerSeverity.trial,
        icon = KiraIcons.info,
        showProgress = false,
        progressValue = null;

  /// A sync-status banner with optional progress.
  const KiraBanner.sync({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
    this.subtitle,
    this.showProgress = true,
    this.progressValue,
  })  : severity = KiraBannerSeverity.info,
        icon = KiraIcons.sync;

  /// A success banner.
  const KiraBanner.success({
    super.key,
    required this.message,
    this.onDismiss,
    this.subtitle,
  })  : severity = KiraBannerSeverity.success,
        icon = KiraIcons.success,
        actionLabel = null,
        onAction = null,
        showProgress = false,
        progressValue = null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final isLight = theme.brightness == Brightness.light;

    final palette = _palette(isLight);

    return Semantics(
      label: message,
      liveRegion: true,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(
          horizontal: KiraDimens.spacingLg,
          vertical: KiraDimens.spacingSm,
        ),
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: BorderRadius.circular(KiraDimens.radiusMd),
          border: Border.all(color: palette.border, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Main content row
            Padding(
              padding: const EdgeInsets.fromLTRB(
                KiraDimens.spacingLg,
                KiraDimens.spacingMd,
                KiraDimens.spacingSm,
                showProgress ? KiraDimens.spacingSm : KiraDimens.spacingMd,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Leading icon
                  Icon(
                    icon ?? _defaultIcon,
                    color: palette.foreground,
                    size: KiraDimens.iconMd,
                  ),
                  const SizedBox(width: KiraDimens.spacingMd),

                  // Text content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message,
                          style: textTheme.bodyMedium?.copyWith(
                            color: palette.foreground,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: KiraDimens.spacingXs),
                          Text(
                            subtitle!,
                            style: textTheme.bodySmall?.copyWith(
                              color: palette.foreground.withAlpha(179),
                            ),
                          ),
                        ],
                        if (actionLabel != null) ...[
                          const SizedBox(height: KiraDimens.spacingSm),
                          _buildAction(palette, textTheme),
                        ],
                      ],
                    ),
                  ),

                  // Dismiss button
                  if (onDismiss != null)
                    IconButton(
                      icon: Icon(
                        KiraIcons.close,
                        size: KiraDimens.iconSm,
                        color: palette.foreground.withAlpha(153),
                      ),
                      onPressed: onDismiss,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      padding: EdgeInsets.zero,
                      tooltip: 'Dismiss',
                    ),
                ],
              ),
            ),

            // Progress bar
            if (showProgress)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  KiraDimens.spacingLg,
                  0,
                  KiraDimens.spacingLg,
                  KiraDimens.spacingMd,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(KiraDimens.radiusFull),
                  child: LinearProgressIndicator(
                    value: progressValue,
                    backgroundColor: palette.foreground.withAlpha(31),
                    valueColor: AlwaysStoppedAnimation<Color>(palette.foreground),
                    minHeight: 4,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAction(_BannerPalette palette, TextTheme textTheme) {
    return GestureDetector(
      onTap: onAction,
      child: Text(
        actionLabel!,
        style: textTheme.labelMedium?.copyWith(
          color: palette.foreground,
          fontWeight: FontWeight.w700,
          decoration: TextDecoration.underline,
          decorationColor: palette.foreground,
        ),
      ),
    );
  }

  // ---------- Palette resolution ----------

  IconData get _defaultIcon {
    switch (severity) {
      case KiraBannerSeverity.info:
        return KiraIcons.info;
      case KiraBannerSeverity.success:
        return KiraIcons.success;
      case KiraBannerSeverity.warning:
        return KiraIcons.warning;
      case KiraBannerSeverity.error:
        return KiraIcons.error;
      case KiraBannerSeverity.trial:
        return KiraIcons.info;
    }
  }

  _BannerPalette _palette(bool isLight) {
    switch (severity) {
      case KiraBannerSeverity.info:
        return _BannerPalette(
          background: isLight
              ? KiraColors.softBlue.withAlpha(51)
              : KiraColors.softBlue.withAlpha(26),
          foreground: isLight ? const Color(0xFF1B5E7A) : KiraColors.softBlue,
          border: isLight
              ? KiraColors.softBlue.withAlpha(77)
              : KiraColors.softBlue.withAlpha(46),
        );
      case KiraBannerSeverity.success:
        return _BannerPalette(
          background: isLight
              ? KiraColors.mintGreen.withAlpha(51)
              : KiraColors.mintGreen.withAlpha(26),
          foreground:
              isLight ? const Color(0xFF2E7D32) : KiraColors.syncedGreen,
          border: isLight
              ? KiraColors.mintGreen.withAlpha(77)
              : KiraColors.mintGreen.withAlpha(46),
        );
      case KiraBannerSeverity.warning:
        return _BannerPalette(
          background: isLight
              ? KiraColors.pendingAmber.withAlpha(38)
              : KiraColors.pendingAmber.withAlpha(26),
          foreground:
              isLight ? const Color(0xFF8D6E00) : KiraColors.pendingAmber,
          border: isLight
              ? KiraColors.pendingAmber.withAlpha(77)
              : KiraColors.pendingAmber.withAlpha(46),
        );
      case KiraBannerSeverity.error:
        return _BannerPalette(
          background: isLight
              ? KiraColors.failedRed.withAlpha(31)
              : KiraColors.failedRed.withAlpha(26),
          foreground:
              isLight ? const Color(0xFFB3261E) : KiraColors.failedRed,
          border: isLight
              ? KiraColors.failedRed.withAlpha(77)
              : KiraColors.failedRed.withAlpha(46),
        );
      case KiraBannerSeverity.trial:
        return _BannerPalette(
          background: isLight
              ? KiraColors.lavender.withAlpha(128)
              : KiraColors.lavender.withAlpha(26),
          foreground:
              isLight ? const Color(0xFF5C4D8A) : KiraColors.lavender,
          border: isLight
              ? KiraColors.lavender.withAlpha(179)
              : KiraColors.lavender.withAlpha(46),
        );
    }
  }
}

// ---------------------------------------------------------------------------
// _BannerPalette (private)
// ---------------------------------------------------------------------------

class _BannerPalette {
  final Color background;
  final Color foreground;
  final Color border;

  const _BannerPalette({
    required this.background,
    required this.foreground,
    required this.border,
  });
}
