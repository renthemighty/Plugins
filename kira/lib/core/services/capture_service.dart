/// Camera capture service for the Kira receipt app.
///
/// This is the top-level orchestrator for taking a receipt photo. It
/// coordinates the camera hardware, timestamp stamping, checksum computation,
/// filename allocation, local mirror persistence, and metadata assembly.
///
/// **Hard rule:** Only the device camera is allowed as an image source. Any
/// attempt to inject images from the gallery, file picker, or any other
/// non-camera source is blocked by design -- there is no API surface for it.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'checksum_service.dart';
import 'filename_allocator.dart';
import 'folder_service.dart';
import 'timestamp_stamper.dart';

// ---------------------------------------------------------------------------
// CaptureResult
// ---------------------------------------------------------------------------

/// All metadata produced by a single capture operation.
///
/// The caller uses this to populate a [Receipt] and to enqueue the image for
/// cloud upload.
class CaptureResult {
  /// Unique identifier for this receipt (UUID v4).
  final String receiptId;

  /// Groups all captures taken during one camera session.
  final String captureSessionId;

  /// ISO-8601 local date-time of capture.
  final String capturedAt;

  /// IANA timezone identifier at capture time.
  final String timezone;

  /// The allocated filename (e.g. `2025-06-14_3.jpg`).
  final String filename;

  /// SHA-256 hex digest of the stamped image bytes.
  final String checksumSha256;

  /// Absolute local path where the stamped image was saved.
  final String localPath;

  /// Stable device identifier.
  final String deviceId;

  /// The stamped image bytes (kept in memory for immediate upload).
  final Uint8List stampedImageBytes;

  /// Hard-coded source indicator -- always `camera`.
  final String source = 'camera';

  CaptureResult({
    required this.receiptId,
    required this.captureSessionId,
    required this.capturedAt,
    required this.timezone,
    required this.filename,
    required this.checksumSha256,
    required this.localPath,
    required this.deviceId,
    required this.stampedImageBytes,
  });

  @override
  String toString() =>
      'CaptureResult(receiptId: $receiptId, filename: $filename, '
      'checksum: ${checksumSha256.substring(0, 12)}...)';
}

// ---------------------------------------------------------------------------
// CaptureService
// ---------------------------------------------------------------------------

/// Manages camera initialisation and the full capture-stamp-save pipeline.
///
/// Usage:
/// ```dart
/// final service = CaptureService(...);
/// await service.initialize();
/// final result = await service.capturePhoto(
///   country: KiraCountry.canada,
///   timezoneId: 'America/Toronto',
///   timezoneAbbr: 'EDT',
/// );
/// // result.stampedImageBytes is ready for upload.
/// await service.dispose();
/// ```
class CaptureService {
  // Dependencies -- injected at construction time.
  final TimestampStamper _stamper;
  final ChecksumService _checksumService;
  final FolderService _folderService;
  final FilenameAllocator _filenameAllocator;
  final FlutterSecureStorage _secureStorage;

  // Camera state.
  CameraController? _controller;
  List<CameraDescription>? _cameras;

  // Session state.
  /// A new session ID is generated each time [initialize] is called (i.e.
  /// each time the camera screen is opened).
  String _captureSessionId = '';

  // Device identity.
  String? _deviceIdCache;

  /// Key under which the stable device ID is persisted in secure storage.
  static const String _deviceIdKey = 'kira_device_id';

  /// UUID generator (stateless, safe to share).
  static const Uuid _uuid = Uuid();

  CaptureService({
    TimestampStamper? stamper,
    ChecksumService? checksumService,
    required FolderService folderService,
    required FilenameAllocator filenameAllocator,
    FlutterSecureStorage? secureStorage,
  })  : _stamper = stamper ?? const TimestampStamper(),
        _checksumService = checksumService ?? const ChecksumService(),
        _folderService = folderService,
        _filenameAllocator = filenameAllocator,
        _secureStorage = secureStorage ?? const FlutterSecureStorage();

  /// The live camera controller, or `null` if [initialize] has not been
  /// called yet.
  CameraController? get controller => _controller;

  /// Whether the camera is initialised and ready to take photos.
  bool get isReady => _controller?.value.isInitialized ?? false;

  /// The current capture session ID.
  String get captureSessionId => _captureSessionId;

  // ---------------------------------------------------------------------------
  // Initialisation / teardown
  // ---------------------------------------------------------------------------

  /// Discovers available cameras, selects the back-facing camera (falling
  /// back to the first available), initialises the controller, and generates
  /// a fresh capture session ID.
  ///
  /// Must be called (and awaited) before [capturePhoto].
  Future<void> initialize({
    ResolutionPreset resolution = ResolutionPreset.high,
  }) async {
    _cameras = await availableCameras();

    if (_cameras == null || _cameras!.isEmpty) {
      throw CaptureException('No cameras available on this device.');
    }

    // Prefer the back camera -- fall back to whatever is available.
    final backCamera = _cameras!.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras!.first,
    );

    _controller = CameraController(
      backCamera,
      resolution,
      enableAudio: false, // receipt photos do not need audio
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    await _controller!.initialize();

    // A new session starts every time the camera is opened.
    _captureSessionId = _uuid.v4();
  }

  /// Releases camera resources. Safe to call multiple times.
  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
  }

  // ---------------------------------------------------------------------------
  // Capture
  // ---------------------------------------------------------------------------

  /// Captures a photo from the **camera only**, stamps the current
  /// date/time into the pixels, computes the SHA-256 checksum, allocates a
  /// collision-free filename, and saves the stamped image to the local mirror.
  ///
  /// **This method intentionally has no parameter for importing files from
  /// the gallery or file system. Camera is the only allowed source.**
  ///
  /// [country] determines the folder hierarchy.
  /// [timezoneId] is the IANA identifier (e.g. `America/Toronto`).
  /// [timezoneAbbr] is the short abbreviation burned into the stamp (e.g.
  /// `EDT`).
  /// [workspaceId] (optional) activates business-mode folder layout.
  ///
  /// Throws [CaptureException] if the camera is not initialised or the
  /// capture fails.
  Future<CaptureResult> capturePhoto({
    required KiraCountry country,
    required String timezoneId,
    required String timezoneAbbr,
    String? workspaceId,
  }) async {
    if (_controller == null || !_controller!.value.isInitialized) {
      throw CaptureException(
        'Camera is not initialized. Call initialize() first.',
      );
    }

    // Take picture.
    final XFile xFile = await _controller!.takePicture();
    final Uint8List rawBytes = await xFile.readAsBytes();

    // Capture timestamp (local time).
    final now = DateTime.now();
    final capturedAt = now.toIso8601String();
    final stampText = DateFormat('yyyy-MM-dd HH:mm:ss').format(now) +
        ' $timezoneAbbr';

    // Burn timestamp into pixels.
    final Uint8List stampedBytes = _stamper.stamp(rawBytes, stampText);

    // Compute SHA-256 of the stamped image.
    final checksum = _checksumService.computeBytesChecksum(stampedBytes);

    // Generate receipt ID.
    final receiptId = _uuid.v4();

    // Get stable device ID.
    final deviceId = await getDeviceId();

    // Allocate collision-free filename.
    final allocated = await _filenameAllocator.allocateFilename(
      now,
      country,
      workspaceId: workspaceId,
    );

    // Ensure local folder structure exists and save the stamped image.
    final localDir = await _folderService.createFolderStructure(
      now,
      country,
      workspaceId: workspaceId,
    );
    final localFilePath = p.join(localDir, allocated.filename);
    await File(localFilePath).writeAsBytes(stampedBytes, flush: true);

    // Clean up the temporary XFile.
    try {
      await File(xFile.path).delete();
    } catch (_) {
      // Best-effort cleanup.
    }

    return CaptureResult(
      receiptId: receiptId,
      captureSessionId: _captureSessionId,
      capturedAt: capturedAt,
      timezone: timezoneId,
      filename: allocated.filename,
      checksumSha256: checksum,
      localPath: localFilePath,
      deviceId: deviceId,
      stampedImageBytes: stampedBytes,
    );
  }

  // ---------------------------------------------------------------------------
  // Device identity
  // ---------------------------------------------------------------------------

  /// Returns a stable, per-installation device identifier.
  ///
  /// The ID is a UUID v4 generated on first launch and persisted in
  /// [FlutterSecureStorage]. Subsequent calls return the cached value.
  Future<String> getDeviceId() async {
    if (_deviceIdCache != null) return _deviceIdCache!;

    String? stored = await _secureStorage.read(key: _deviceIdKey);
    if (stored != null && stored.isNotEmpty) {
      _deviceIdCache = stored;
      return stored;
    }

    // First launch -- generate and persist.
    final newId = _uuid.v4();
    await _secureStorage.write(key: _deviceIdKey, value: newId);
    _deviceIdCache = newId;
    return newId;
  }
}

// ---------------------------------------------------------------------------
// Exceptions
// ---------------------------------------------------------------------------

/// Thrown when the capture pipeline encounters an unrecoverable error.
class CaptureException implements Exception {
  final String message;
  const CaptureException(this.message);

  @override
  String toString() => 'CaptureException: $message';
}
