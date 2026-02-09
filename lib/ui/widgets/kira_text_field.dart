// Kira - The Receipt Saver
// Styled text input with validation support and amount input with currency prefix.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/kira_theme.dart';

// ---------------------------------------------------------------------------
// KiraTextField – general-purpose styled text field
// ---------------------------------------------------------------------------

/// A styled [TextFormField] that follows the Kira design language.
///
/// Provides a consistent look with rounded borders, soft fill colours, and
/// integrated validation error display.
class KiraTextField extends StatelessWidget {
  /// Text editing controller.
  final TextEditingController? controller;

  /// Label text shown inside the border.
  final String? label;

  /// Hint text shown when the field is empty.
  final String? hint;

  /// Helper text shown below the field.
  final String? helperText;

  /// Error text override. When non-null, the field displays in an error state.
  final String? errorText;

  /// Leading icon inside the field.
  final IconData? prefixIcon;

  /// Trailing widget (e.g. a clear button or visibility toggle).
  final Widget? suffix;

  /// A fixed prefix text (e.g. "$" for currency fields).
  final String? prefixText;

  /// Form validation function.
  final String? Function(String?)? validator;

  /// Called on every text change.
  final ValueChanged<String>? onChanged;

  /// Called when the user submits (e.g. presses enter).
  final ValueChanged<String>? onSubmitted;

  /// Called when the field gains or loses focus.
  final ValueChanged<bool>? onFocusChange;

  /// Keyboard type.
  final TextInputType? keyboardType;

  /// Input formatters.
  final List<TextInputFormatter>? inputFormatters;

  /// Whether this is a password / obscured field.
  final bool obscureText;

  /// Whether the field is read-only.
  final bool readOnly;

  /// Whether the field is enabled.
  final bool enabled;

  /// Whether to auto-focus this field.
  final bool autofocus;

  /// Maximum number of lines.
  final int? maxLines;

  /// Minimum number of lines.
  final int? minLines;

  /// Maximum character count. Shows a counter when set.
  final int? maxLength;

  /// Text input action (e.g. next, done).
  final TextInputAction? textInputAction;

  /// Focus node.
  final FocusNode? focusNode;

  /// Text capitalization.
  final TextCapitalization textCapitalization;

  /// Auto-validate mode.
  final AutovalidateMode? autovalidateMode;

  const KiraTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.helperText,
    this.errorText,
    this.prefixIcon,
    this.suffix,
    this.prefixText,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.onFocusChange,
    this.keyboardType,
    this.inputFormatters,
    this.obscureText = false,
    this.readOnly = false,
    this.enabled = true,
    this.autofocus = false,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.textInputAction,
    this.focusNode,
    this.textCapitalization = TextCapitalization.none,
    this.autovalidateMode,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Widget field = TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helperText,
        errorText: errorText,
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, size: KiraDimens.iconMd)
            : null,
        prefixText: prefixText,
        prefixStyle: theme.textTheme.bodyLarge?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        suffixIcon: suffix,
        counterText: maxLength != null ? null : '',
      ),
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      obscureText: obscureText,
      readOnly: readOnly,
      enabled: enabled,
      autofocus: autofocus,
      maxLines: maxLines,
      minLines: minLines,
      maxLength: maxLength,
      textInputAction: textInputAction,
      focusNode: focusNode,
      textCapitalization: textCapitalization,
      autovalidateMode: autovalidateMode,
      style: theme.textTheme.bodyLarge,
    );

    if (onFocusChange != null) {
      field = Focus(
        onFocusChange: onFocusChange,
        child: field,
      );
    }

    return field;
  }
}

// ---------------------------------------------------------------------------
// KiraSearchField – pre-configured search input
// ---------------------------------------------------------------------------

/// A search-optimised text field with a search icon and clear button.
class KiraSearchField extends StatefulWidget {
  final TextEditingController? controller;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  const KiraSearchField({
    super.key,
    this.controller,
    this.hint,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
  });

  @override
  State<KiraSearchField> createState() => _KiraSearchFieldState();
}

class _KiraSearchFieldState extends State<KiraSearchField> {
  late final TextEditingController _controller;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _controller.addListener(_onTextChanged);
    _hasText = _controller.text.isNotEmpty;
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    } else {
      _controller.removeListener(_onTextChanged);
    }
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = _controller.text.isNotEmpty;
    if (_hasText != hasText) {
      setState(() => _hasText = hasText);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;

    return KiraTextField(
      controller: _controller,
      hint: widget.hint ?? 'Search...',
      prefixIcon: Icons.search_rounded,
      suffix: _hasText
          ? IconButton(
              icon: const Icon(Icons.close_rounded, size: KiraDimens.iconSm),
              onPressed: () {
                _controller.clear();
                widget.onChanged?.call('');
              },
              color: colorScheme.onSurface.withAlpha(153),
            )
          : null,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      autofocus: widget.autofocus,
      textInputAction: TextInputAction.search,
      keyboardType: TextInputType.text,
    );
  }
}

// ---------------------------------------------------------------------------
// KiraPasswordField – password input with visibility toggle
// ---------------------------------------------------------------------------

/// A password field with an eye-toggle for visibility.
class KiraPasswordField extends StatefulWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? errorText;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;
  final FocusNode? focusNode;
  final AutovalidateMode? autovalidateMode;

  const KiraPasswordField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.errorText,
    this.validator,
    this.onChanged,
    this.textInputAction,
    this.focusNode,
    this.autovalidateMode,
  });

  @override
  State<KiraPasswordField> createState() => _KiraPasswordFieldState();
}

class _KiraPasswordFieldState extends State<KiraPasswordField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    return KiraTextField(
      controller: widget.controller,
      label: widget.label,
      hint: widget.hint,
      errorText: widget.errorText,
      prefixIcon: Icons.lock_rounded,
      obscureText: _obscured,
      validator: widget.validator,
      onChanged: widget.onChanged,
      textInputAction: widget.textInputAction,
      focusNode: widget.focusNode,
      autovalidateMode: widget.autovalidateMode,
      suffix: IconButton(
        icon: Icon(
          _obscured ? Icons.visibility_rounded : Icons.visibility_off_rounded,
          size: KiraDimens.iconMd,
        ),
        onPressed: () => setState(() => _obscured = !_obscured),
      ),
    );
  }
}
