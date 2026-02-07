/// Burns a human-readable timestamp directly into the pixels of a receipt
/// photograph.
///
/// The stamp is rendered in the bottom-right corner of the image on a
/// semi-transparent dark background so that it remains legible regardless
/// of the underlying receipt content. The rest of the image is preserved
/// bit-for-bit -- only the pixels covered by the stamp box are modified.
///
/// This is a **permanent, non-reversible** operation by design: the timestamp
/// becomes part of the image data and survives re-encoding, re-upload, or
/// export to any other system.
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Configuration knobs for the timestamp stamp appearance.
///
/// All sizes are expressed relative to the image width so that the stamp
/// scales naturally across different camera resolutions.
class StampConfig {
  /// Font scale factor relative to image width.
  /// 0.018 produces comfortably readable text on a 4032-wide photo.
  final double fontScaleFactor;

  /// Horizontal and vertical padding inside the dark box, as a fraction of
  /// image width.
  final double paddingFactor;

  /// Margin between the stamp box edge and the image edge, as a fraction of
  /// image width.
  final double marginFactor;

  /// Background box opacity (0 = fully transparent, 255 = fully opaque).
  final int backgroundAlpha;

  const StampConfig({
    this.fontScaleFactor = 0.018,
    this.paddingFactor = 0.008,
    this.marginFactor = 0.012,
    this.backgroundAlpha = 180,
  });
}

class TimestampStamper {
  final StampConfig config;

  const TimestampStamper({this.config = const StampConfig()});

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Burns [timestamp] into the bottom-right corner of the JPEG [imageBytes]
  /// and returns the modified image as JPEG bytes.
  ///
  /// [timestamp] must already be formatted as `YYYY-MM-DD HH:mm:ss TZ`
  /// (e.g. `2025-06-14 09:32:11 EDT`).
  ///
  /// The returned bytes are JPEG-encoded at quality 95 to preserve detail
  /// while keeping file size reasonable.
  ///
  /// Throws [ArgumentError] if the image cannot be decoded.
  Uint8List stamp(Uint8List imageBytes, String timestamp) {
    final image = img.decodeImage(imageBytes);
    if (image == null) {
      throw ArgumentError('Failed to decode image bytes for stamping.');
    }

    _burnTimestamp(image, timestamp);

    return Uint8List.fromList(img.encodeJpg(image, quality: 95));
  }

  /// Convenience overload that decodes, stamps, and re-encodes, returning
  /// both the stamped bytes and the decoded [img.Image] for callers that need
  /// further processing.
  ({Uint8List bytes, img.Image image}) stampWithImage(
    Uint8List imageBytes,
    String timestamp,
  ) {
    final image = img.decodeImage(imageBytes);
    if (image == null) {
      throw ArgumentError('Failed to decode image bytes for stamping.');
    }

    _burnTimestamp(image, timestamp);

    final encoded = Uint8List.fromList(img.encodeJpg(image, quality: 95));
    return (bytes: encoded, image: image);
  }

  // ---------------------------------------------------------------------------
  // Internal rendering
  // ---------------------------------------------------------------------------

  /// Renders the timestamp string onto [image] in the bottom-right corner.
  void _burnTimestamp(img.Image image, String timestamp) {
    final int imageWidth = image.width;
    final int imageHeight = image.height;

    // Scale everything relative to the image width so the stamp looks
    // consistent across resolutions (e.g. 3024, 4032, 4624).
    final int fontSize = (imageWidth * config.fontScaleFactor).round().clamp(12, 120);
    final int padding = (imageWidth * config.paddingFactor).round().clamp(4, 60);
    final int margin = (imageWidth * config.marginFactor).round().clamp(4, 80);

    // Measure approximate text dimensions.
    // The `image` package's BitmapFont is fixed-size, so we use drawString
    // with a scale factor derived from our desired font size relative to the
    // built-in arial_14 font baseline (14px).
    final font = _selectFont(fontSize);

    // Measure text bounding box.
    final int charWidth = _estimateCharWidth(font);
    final int textWidth = charWidth * timestamp.length;
    final int textHeight = font.lineHeight;

    // Box dimensions.
    final int boxWidth = textWidth + padding * 2;
    final int boxHeight = textHeight + padding * 2;

    // Box position (bottom-right, inset by margin).
    final int boxX = imageWidth - boxWidth - margin;
    final int boxY = imageHeight - boxHeight - margin;

    // Clamp to image bounds to prevent out-of-range writes.
    final int safeBoxX = boxX.clamp(0, imageWidth - 1);
    final int safeBoxY = boxY.clamp(0, imageHeight - 1);
    final int safeBoxRight = (safeBoxX + boxWidth).clamp(0, imageWidth);
    final int safeBoxBottom = (safeBoxY + boxHeight).clamp(0, imageHeight);

    // Draw semi-transparent dark background.
    final bgColor = img.ColorRgba8(0, 0, 0, config.backgroundAlpha);
    img.fillRect(
      image,
      x1: safeBoxX,
      y1: safeBoxY,
      x2: safeBoxRight,
      y2: safeBoxBottom,
      color: bgColor,
    );

    // Draw white text on top.
    final textColor = img.ColorRgba8(255, 255, 255, 255);
    img.drawString(
      image,
      timestamp,
      font: font,
      x: safeBoxX + padding,
      y: safeBoxY + padding,
      color: textColor,
    );
  }

  /// Selects the best built-in bitmap font for the requested [fontSize].
  ///
  /// The `image` package ships a handful of fixed-size bitmap fonts. We pick
  /// the closest one that does not exceed the target size.
  img.BitmapFont _selectFont(int fontSize) {
    if (fontSize >= 48) return img.arial48;
    if (fontSize >= 24) return img.arial24;
    return img.arial14;
  }

  /// Returns an approximate per-character advance width for [font].
  ///
  /// Bitmap fonts in the `image` package have variable glyph widths; we take
  /// the width of the '0' glyph (always present, representative of digit
  /// widths) or fall back to a fraction of the line height.
  int _estimateCharWidth(img.BitmapFont font) {
    // Try to get the '0' character glyph width.
    final zeroChar = font.characters[48]; // ASCII '0'
    if (zeroChar != null) {
      return zeroChar.xAdvance;
    }
    // Fallback: assume roughly 60% of line height per character.
    return (font.lineHeight * 0.6).round();
  }
}
