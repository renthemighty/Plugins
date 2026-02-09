/// On-device OCR service for the Kira app.
///
/// Uses [google_mlkit_text_recognition] to extract text from receipt images
/// entirely on-device. No image data is sent to any external server.
///
/// **Important:** OCR results are **suggestions only**. They are presented to
/// the user as pre-filled hints that can be accepted, edited, or discarded.
/// OCR never replaces manual entry -- the user always has the final say.
///
/// The service provides:
///   - Full receipt analysis (merchant, amount, date) with confidence scores
///   - Raw text extraction for custom processing
///   - Individual parsers for amounts, dates, and merchant names
library;

import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

// ---------------------------------------------------------------------------
// OcrResult
// ---------------------------------------------------------------------------

/// The result of analysing a receipt image with on-device OCR.
///
/// All fields are nullable because OCR is inherently unreliable -- any
/// individual piece of data may fail to parse or may be parsed incorrectly.
/// Each extracted value comes with a confidence score (0.0 to 1.0) that the
/// UI can use to decide whether to show the suggestion prominently or dimmed.
class OcrResult {
  /// The merchant / store name extracted from the receipt.
  /// Typically found in the first few lines of text.
  final String? merchantName;

  /// Confidence score for [merchantName], from 0.0 (no confidence) to 1.0.
  final double merchantConfidence;

  /// The total amount detected on the receipt.
  final double? totalAmount;

  /// Confidence score for [totalAmount].
  final double totalAmountConfidence;

  /// A date parsed from the receipt text.
  final DateTime? dateCandidate;

  /// Confidence score for [dateCandidate].
  final double dateConfidence;

  /// The complete raw text recognized from the image.
  final String rawText;

  /// All individual amounts found in the receipt, ordered by magnitude
  /// (largest first). Useful when the "total" heuristic picks the wrong one.
  final List<double> allAmountsFound;

  const OcrResult({
    this.merchantName,
    this.merchantConfidence = 0.0,
    this.totalAmount,
    this.totalAmountConfidence = 0.0,
    this.dateCandidate,
    this.dateConfidence = 0.0,
    this.rawText = '',
    this.allAmountsFound = const [],
  });

  /// An empty result indicating OCR returned nothing useful.
  static const empty = OcrResult();

  /// Whether any usable data was extracted.
  bool get hasData =>
      merchantName != null || totalAmount != null || dateCandidate != null;

  @override
  String toString() =>
      'OcrResult(merchant: $merchantName [$merchantConfidence], '
      'total: $totalAmount [$totalAmountConfidence], '
      'date: $dateCandidate [$dateConfidence])';
}

// ---------------------------------------------------------------------------
// OcrService
// ---------------------------------------------------------------------------

/// Performs on-device text recognition and receipt parsing.
///
/// Usage:
/// ```dart
/// final ocr = OcrService();
/// final result = await ocr.analyzeReceipt('/path/to/receipt.jpg');
/// if (result.totalAmount != null) {
///   print('Suggested amount: ${result.totalAmount}');
/// }
/// ocr.dispose(); // Release ML Kit resources when done.
/// ```
class OcrService {
  OcrService({TextRecognizer? textRecognizer})
      : _textRecognizer = textRecognizer ??
            TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _textRecognizer;

  // =========================================================================
  // Public API
  // =========================================================================

  /// Analyses a receipt image and returns structured suggestions.
  ///
  /// This is the primary entry point. It runs text recognition and then
  /// applies heuristics to extract the merchant name, total amount, and date.
  ///
  /// Returns [OcrResult.empty] if the image cannot be read or contains no
  /// recognizable text.
  Future<OcrResult> analyzeReceipt(String imagePath) async {
    final rawText = await extractText(imagePath);
    if (rawText.isEmpty) return OcrResult.empty;

    final lines = rawText.split('\n').where((l) => l.trim().isNotEmpty).toList();

    final merchantResult = _parseMerchantFromLines(lines);
    final amountResult = _parseAmountFromText(rawText);
    final dateResult = _parseDateFromText(rawText);

    return OcrResult(
      merchantName: merchantResult.value,
      merchantConfidence: merchantResult.confidence,
      totalAmount: amountResult.value,
      totalAmountConfidence: amountResult.confidence,
      dateCandidate: dateResult.value,
      dateConfidence: dateResult.confidence,
      rawText: rawText,
      allAmountsFound: _findAllAmounts(rawText),
    );
  }

  /// Extracts raw text from the image at [imagePath].
  ///
  /// Returns an empty string if the image does not exist, cannot be decoded,
  /// or contains no recognizable text.
  Future<String> extractText(String imagePath) async {
    final file = File(imagePath);
    if (!await file.exists()) return '';

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognized = await _textRecognizer.processImage(inputImage);
      return recognized.text;
    } catch (_) {
      // ML Kit can throw on corrupt / unsupported images.
      return '';
    }
  }

  /// Finds dollar/currency amounts in [text].
  ///
  /// Returns the most likely "total" amount, or `null` if none found.
  double? parseAmount(String text) => _parseAmountFromText(text).value;

  /// Finds date patterns in [text].
  ///
  /// Returns the first plausible date, or `null` if none found.
  DateTime? parseDate(String text) => _parseDateFromText(text).value;

  /// Applies merchant-name heuristics to [text].
  ///
  /// Returns the best-guess merchant name, or `null`.
  String? parseMerchant(String text) {
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
    return _parseMerchantFromLines(lines).value;
  }

  /// Releases ML Kit resources. Call this when the service is no longer needed
  /// (e.g. when the capture screen is disposed).
  Future<void> dispose() async {
    await _textRecognizer.close();
  }

  // =========================================================================
  // Amount parsing
  // =========================================================================

  /// Regex for currency amounts: optional `$`, digits with optional commas,
  /// a decimal point, and exactly two decimal digits.
  static final RegExp _amountPattern = RegExp(
    r'[\$]?\s*(\d{1,3}(?:,\d{3})*(?:\.\d{2}))',
  );

  /// Keywords that typically precede the receipt total.
  static final RegExp _totalKeywordPattern = RegExp(
    r'(?:total|amount\s*due|balance\s*due|grand\s*total|payment|'
    r'amount\s*paid|net\s*amount|charged|debit)',
    caseSensitive: false,
  );

  /// Keywords indicating a value is a subtotal, tax, or tip (not the total).
  static final RegExp _subtotalPattern = RegExp(
    r'(?:subtotal|sub\s*total|tax|hst|gst|pst|qst|tip|gratuity|discount|'
    r'change\s*due|savings)',
    caseSensitive: false,
  );

  _Parsed<double> _parseAmountFromText(String text) {
    final amounts = _findAllAmounts(text);
    if (amounts.isEmpty) return const _Parsed(null, 0.0);

    final lines = text.split('\n');

    // Strategy 1: Look for an amount on a line containing a "total" keyword.
    for (final line in lines) {
      if (_subtotalPattern.hasMatch(line)) continue;
      if (_totalKeywordPattern.hasMatch(line)) {
        final match = _amountPattern.firstMatch(line);
        if (match != null) {
          final parsed = _parseAmountString(match.group(1)!);
          if (parsed != null && parsed > 0) {
            return _Parsed(parsed, 0.85);
          }
        }
      }
    }

    // Strategy 2: The largest amount is often the total.
    if (amounts.length == 1) {
      return _Parsed(amounts.first, 0.6);
    }

    // With multiple amounts, the largest is likely the total, but with lower
    // confidence.
    return _Parsed(amounts.first, 0.45);
  }

  /// Extracts all dollar amounts from [text], sorted largest first.
  List<double> _findAllAmounts(String text) {
    final matches = _amountPattern.allMatches(text);
    final amounts = <double>{};

    for (final match in matches) {
      final parsed = _parseAmountString(match.group(1)!);
      if (parsed != null && parsed > 0) {
        amounts.add(parsed);
      }
    }

    final sorted = amounts.toList()..sort((a, b) => b.compareTo(a));
    return sorted;
  }

  /// Parses a numeric string like `"1,234.56"` into a double.
  double? _parseAmountString(String s) {
    final cleaned = s.replaceAll(',', '').trim();
    return double.tryParse(cleaned);
  }

  // =========================================================================
  // Date parsing
  // =========================================================================

  /// Common date patterns found on Canadian and US receipts.
  static final List<_DatePattern> _datePatterns = [
    // MM/DD/YYYY or MM-DD-YYYY
    _DatePattern(
      RegExp(r'(\d{1,2})[/\-](\d{1,2})[/\-](\d{4})'),
      (m) => _tryBuildDate(
        int.parse(m.group(3)!),
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
      ),
    ),
    // YYYY/MM/DD or YYYY-MM-DD
    _DatePattern(
      RegExp(r'(\d{4})[/\-](\d{1,2})[/\-](\d{1,2})'),
      (m) => _tryBuildDate(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
      ),
    ),
    // DD/MM/YYYY (less common in NA but possible on imports)
    // We try this last since MM/DD/YYYY is more common in NA.
    _DatePattern(
      RegExp(r'(\d{1,2})[/\-](\d{1,2})[/\-](\d{2})(?!\d)'),
      (m) {
        final year2 = int.parse(m.group(3)!);
        final year = year2 + (year2 < 50 ? 2000 : 1900);
        return _tryBuildDate(year, int.parse(m.group(1)!), int.parse(m.group(2)!));
      },
    ),
    // Month name: "Jun 14, 2025" or "June 14 2025"
    _DatePattern(
      RegExp(
        r'(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|'
        r'Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|'
        r'Nov(?:ember)?|Dec(?:ember)?)\s+(\d{1,2}),?\s+(\d{4})',
        caseSensitive: false,
      ),
      (m) => _tryBuildDate(
        int.parse(m.group(3)!),
        _monthNumber(m.group(1)!),
        int.parse(m.group(2)!),
      ),
    ),
  ];

  _Parsed<DateTime> _parseDateFromText(String text) {
    for (final pattern in _datePatterns) {
      final match = pattern.regex.firstMatch(text);
      if (match != null) {
        final date = pattern.builder(match);
        if (date != null) {
          // Higher confidence for full-year patterns.
          final confidence = pattern.regex.pattern.contains(r'(\d{4})')
              ? 0.80
              : 0.55;
          return _Parsed(date, confidence);
        }
      }
    }
    return const _Parsed(null, 0.0);
  }

  /// Validates and constructs a DateTime, returning null for invalid dates.
  static DateTime? _tryBuildDate(int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    if (year < 2000 || year > 2100) return null;
    try {
      final dt = DateTime(year, month, day);
      // Verify the date components round-trip (catches e.g. Feb 30).
      if (dt.year != year || dt.month != month || dt.day != day) return null;
      return dt;
    } catch (_) {
      return null;
    }
  }

  /// Converts a month name or abbreviation to its 1-based number.
  static int _monthNumber(String name) {
    switch (name.substring(0, 3).toLowerCase()) {
      case 'jan': return 1;
      case 'feb': return 2;
      case 'mar': return 3;
      case 'apr': return 4;
      case 'may': return 5;
      case 'jun': return 6;
      case 'jul': return 7;
      case 'aug': return 8;
      case 'sep': return 9;
      case 'oct': return 10;
      case 'nov': return 11;
      case 'dec': return 12;
      default: return 1;
    }
  }

  // =========================================================================
  // Merchant parsing
  // =========================================================================

  /// Lines that are typically header noise rather than the merchant name.
  static final RegExp _noisePattern = RegExp(
    r'^(?:\*+|[-=]+|#{2,}|tel[:\s]|phone|fax|www\.|http|receipt|'
    r'order\s*#|invoice|transaction|terminal|cashier|server|table|'
    r'date|time|\d{1,2}[:/]\d{2})',
    caseSensitive: false,
  );

  /// Heuristic: the merchant name is usually one of the first non-noise,
  /// non-numeric lines at the top of the receipt.
  _Parsed<String> _parseMerchantFromLines(List<String> lines) {
    // Look at the first ~5 lines for the merchant name.
    final candidateLines = lines.take(7).toList();
    String? bestCandidate;

    for (final line in candidateLines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.length < 3) continue; // Too short to be meaningful.
      if (_noisePattern.hasMatch(trimmed)) continue;

      // Skip lines that are purely numeric (phone numbers, dates, etc.).
      if (RegExp(r'^\d[\d\s\-().]+$').hasMatch(trimmed)) continue;

      // Skip lines that look like addresses (contain postal/zip codes).
      if (RegExp(r'[A-Z]\d[A-Z]\s*\d[A-Z]\d', caseSensitive: false)
          .hasMatch(trimmed)) {
        continue;
      }
      if (RegExp(r'\d{5}(?:-\d{4})?').hasMatch(trimmed)) continue;

      // The first qualifying line is our best candidate.
      bestCandidate = _cleanMerchantName(trimmed);
      break;
    }

    if (bestCandidate == null) return const _Parsed(null, 0.0);

    // Confidence is higher for shorter, all-caps names (typical receipt style).
    final isAllCaps = bestCandidate == bestCandidate.toUpperCase();
    final isReasonableLength =
        bestCandidate.length >= 3 && bestCandidate.length <= 40;
    double confidence = 0.5;
    if (isAllCaps) confidence += 0.15;
    if (isReasonableLength) confidence += 0.1;

    return _Parsed(bestCandidate, confidence.clamp(0.0, 1.0));
  }

  /// Cleans up a raw merchant name string.
  String _cleanMerchantName(String raw) {
    // Remove leading/trailing punctuation and whitespace.
    var cleaned = raw.replaceAll(RegExp(r'^[\s*#\-=]+|[\s*#\-=]+$'), '');

    // Collapse multiple spaces.
    cleaned = cleaned.replaceAll(RegExp(r'\s{2,}'), ' ');

    // Title-case if the string is all-caps and reasonably short.
    if (cleaned.length <= 40 && cleaned == cleaned.toUpperCase()) {
      cleaned = _titleCase(cleaned);
    }

    return cleaned.trim();
  }

  /// Converts a string to Title Case.
  String _titleCase(String input) {
    return input.split(' ').map((word) {
      if (word.isEmpty) return word;
      return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
    }).join(' ');
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// A parsed value paired with a confidence score.
class _Parsed<T> {
  final T? value;
  final double confidence;

  const _Parsed(this.value, this.confidence);
}

/// Associates a regex with a builder function that produces a DateTime.
class _DatePattern {
  final RegExp regex;
  final DateTime? Function(RegExpMatch match) builder;

  const _DatePattern(this.regex, this.builder);
}
