// Kira - The Receipt Saver
// Specialized amount input that handles CAD/USD formatting, decimal validation,
// and partial amounts.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../theme/kira_icons.dart';
import '../theme/kira_theme.dart';

// ---------------------------------------------------------------------------
// Supported currencies
// ---------------------------------------------------------------------------

/// The currencies supported by Kira.
enum KiraCurrency {
  cad,
  usd;

  String get code {
    switch (this) {
      case KiraCurrency.cad:
        return 'CAD';
      case KiraCurrency.usd:
        return 'USD';
    }
  }

  String get symbol => '\$';

  String get displayLabel {
    switch (this) {
      case KiraCurrency.cad:
        return '\$ CAD';
      case KiraCurrency.usd:
        return '\$ USD';
    }
  }

  /// Returns a [NumberFormat] appropriate for this currency.
  NumberFormat get formatter => NumberFormat.currency(
        symbol: symbol,
        decimalDigits: 2,
        locale: this == KiraCurrency.cad ? 'en_CA' : 'en_US',
      );
}

// ---------------------------------------------------------------------------
// AmountInput
// ---------------------------------------------------------------------------

/// A text field specialized for entering monetary amounts.
///
/// Features:
/// - Currency prefix ($) with selectable CAD/USD
/// - Decimal validation (max 2 decimal places)
/// - Partial amounts allowed (user can type "12" without ".00")
/// - Formatted display on blur
/// - Validation callback
/// - Accessible labels
///
/// ```dart
/// AmountInput(
///   controller: _amountController,
///   currency: KiraCurrency.cad,
///   onChanged: (value) => setState(() => _amount = value),
///   label: l10n.amountTracked,
///   hint: l10n.amountHint,
///   helperText: l10n.partialAmountAllowed,
/// )
/// ```
class AmountInput extends StatefulWidget {
  /// Controller for the amount text field.
  final TextEditingController? controller;

  /// The active currency.
  final KiraCurrency currency;

  /// Called when the currency selector is changed. If null, currency is fixed.
  final ValueChanged<KiraCurrency>? onCurrencyChanged;

  /// Called with the parsed double value whenever the input changes.
  /// Returns null if the input is empty or invalid.
  final ValueChanged<double?>? onChanged;

  /// Form validation function.
  final String? Function(String?)? validator;

  /// Label text.
  final String? label;

  /// Hint text shown when the field is empty.
  final String? hint;

  /// Helper text shown below the field.
  final String? helperText;

  /// Error text override.
  final String? errorText;

  /// Whether the field is enabled.
  final bool enabled;

  /// Whether the field is read-only.
  final bool readOnly;

  /// Whether to auto-focus the field.
  final bool autofocus;

  /// Maximum allowed amount. Defaults to 999999.99.
  final double maxAmount;

  /// Minimum allowed amount (inclusive). Defaults to 0.
  final double minAmount;

  /// Whether zero is a valid amount.
  final bool allowZero;

  /// Text input action.
  final TextInputAction? textInputAction;

  /// Focus node.
  final FocusNode? focusNode;

  /// Whether to format the value on blur (add trailing zeros, etc.).
  final bool formatOnBlur;

  const AmountInput({
    super.key,
    this.controller,
    this.currency = KiraCurrency.cad,
    this.onCurrencyChanged,
    this.onChanged,
    this.validator,
    this.label,
    this.hint,
    this.helperText,
    this.errorText,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.maxAmount = 999999.99,
    this.minAmount = 0.0,
    this.allowZero = true,
    this.textInputAction,
    this.focusNode,
    this.formatOnBlur = true,
  });

  @override
  State<AmountInput> createState() => _AmountInputState();
}

class _AmountInputState extends State<AmountInput> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = TextEditingController();
      _ownsController = true;
    }

    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
    } else {
      _focusNode = FocusNode();
      _ownsFocusNode = true;
    }

    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    if (_ownsController) _controller.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus && widget.formatOnBlur) {
      _formatValue();
    }
  }

  /// Formats the current value to two decimal places on blur.
  void _formatValue() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final parsed = double.tryParse(text);
    if (parsed == null) return;

    final formatted = parsed.toStringAsFixed(2);
    if (formatted != text) {
      _controller.text = formatted;
      _controller.selection = TextSelection.collapsed(
        offset: formatted.length,
      );
    }
  }

  void _onChanged(String value) {
    final parsed = double.tryParse(value.trim());
    widget.onChanged?.call(parsed);
  }

  String? _defaultValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null; // Empty is allowed – caller decides if required.
    }

    final parsed = double.tryParse(value.trim());
    if (parsed == null) {
      return 'Enter a valid amount';
    }

    if (parsed < widget.minAmount) {
      return 'Amount must be at least ${widget.minAmount.toStringAsFixed(2)}';
    }

    if (!widget.allowZero && parsed == 0) {
      return 'Amount must be greater than zero';
    }

    if (parsed > widget.maxAmount) {
      return 'Amount cannot exceed ${widget.maxAmount.toStringAsFixed(2)}';
    }

    // Check decimal places (max 2).
    if (value.contains('.')) {
      final decimals = value.split('.').last;
      if (decimals.length > 2) {
        return 'Maximum 2 decimal places';
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Semantics(
      label: widget.label ?? 'Amount',
      textField: true,
      child: TextFormField(
        controller: _controller,
        focusNode: _focusNode,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint ?? '0.00',
          helperText: widget.helperText,
          errorText: widget.errorText,
          prefixIcon: _buildCurrencyPrefix(colorScheme, textTheme),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 0,
            minHeight: 0,
          ),
          suffixIcon: widget.onCurrencyChanged != null
              ? _buildCurrencySelector(colorScheme, textTheme)
              : null,
        ),
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: false,
        ),
        inputFormatters: [
          _AmountInputFormatter(maxAmount: widget.maxAmount),
        ],
        validator: widget.validator ?? _defaultValidator,
        onChanged: _onChanged,
        enabled: widget.enabled,
        readOnly: widget.readOnly,
        autofocus: widget.autofocus,
        textInputAction: widget.textInputAction,
        textAlign: TextAlign.left,
        style: textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
      ),
    );
  }

  Widget _buildCurrencyPrefix(ColorScheme colorScheme, TextTheme textTheme) {
    return Padding(
      padding: const EdgeInsets.only(
        left: KiraDimens.spacingLg,
        right: KiraDimens.spacingSm,
      ),
      child: Text(
        widget.currency.symbol,
        style: textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildCurrencySelector(
      ColorScheme colorScheme, TextTheme textTheme) {
    return Padding(
      padding: const EdgeInsets.only(right: KiraDimens.spacingSm),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<KiraCurrency>(
          value: widget.currency,
          onChanged: widget.enabled
              ? (value) {
                  if (value != null) {
                    widget.onCurrencyChanged?.call(value);
                  }
                }
              : null,
          items: KiraCurrency.values.map((currency) {
            return DropdownMenuItem(
              value: currency,
              child: Text(
                currency.code,
                style: textTheme.labelLarge?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }).toList(),
          icon: Icon(
            KiraIcons.expandMore,
            size: KiraDimens.iconSm,
            color: colorScheme.primary,
          ),
          isDense: true,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _AmountInputFormatter (private)
// ---------------------------------------------------------------------------

/// A [TextInputFormatter] that restricts input to valid monetary amounts.
///
/// - Only digits and a single decimal point.
/// - Maximum 2 decimal places.
/// - No leading zeros (except "0." prefix).
/// - Caps at [maxAmount].
class _AmountInputFormatter extends TextInputFormatter {
  final double maxAmount;

  _AmountInputFormatter({this.maxAmount = 999999.99});

  // Pattern: optional digits, optional decimal, optional 1-2 digits after.
  static final RegExp _amountPattern = RegExp(r'^\d*\.?\d{0,2}$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final newText = newValue.text;

    // Allow empty field.
    if (newText.isEmpty) return newValue;

    // Reject if the pattern does not match.
    if (!_amountPattern.hasMatch(newText)) {
      return oldValue;
    }

    // Reject leading zeros like "007" but allow "0" and "0.xx".
    if (newText.length > 1 &&
        newText.startsWith('0') &&
        !newText.startsWith('0.')) {
      return oldValue;
    }

    // Reject if the value exceeds maxAmount.
    final parsed = double.tryParse(newText);
    if (parsed != null && parsed > maxAmount) {
      return oldValue;
    }

    return newValue;
  }
}

// ---------------------------------------------------------------------------
// AmountDisplay – read-only formatted amount
// ---------------------------------------------------------------------------

/// A read-only display widget for a formatted monetary amount.
///
/// Useful in receipt detail views and report summaries.
class AmountDisplay extends StatelessWidget {
  final double amount;
  final KiraCurrency currency;
  final TextStyle? style;
  final bool showCurrencyCode;

  const AmountDisplay({
    super.key,
    required this.amount,
    this.currency = KiraCurrency.cad,
    this.style,
    this.showCurrencyCode = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formatted = currency.formatter.format(amount);
    final suffix = showCurrencyCode ? ' ${currency.code}' : '';

    return Semantics(
      label: '$formatted ${currency.code}',
      child: Text(
        '$formatted$suffix',
        style: style ??
            theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
      ),
    );
  }
}
