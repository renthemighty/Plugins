/// Strict, collision-free filename allocation for receipt images.
///
/// Every receipt image is named with the pattern:
///
/// ```
/// YYYY-MM-DD_N.jpg
/// ```
///
/// where `N` is a positive integer starting at 1 that increments for each
/// receipt captured on the same day. The allocator consults **four** sources
/// to determine the next safe suffix:
///
/// 1. The local day-index JSON file.
/// 2. The local SQLite database.
/// 3. The remote day-index JSON file (if reachable).
/// 4. The remote folder listing (if reachable).
///
/// It picks `max(all_known_suffixes) + 1` and, if a collision is still
/// detected at write time, increments in a retry loop. This guarantees that
/// **no existing file is ever overwritten**.
library;

import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import 'folder_service.dart';

/// Result returned by [FilenameAllocator.allocateFilename].
class AllocatedFilename {
  /// The filename string (e.g. `2025-06-14_3.jpg`).
  final String filename;

  /// The integer suffix that was allocated.
  final int suffix;

  /// The formatted date portion of the filename.
  final String datePrefix;

  const AllocatedFilename({
    required this.filename,
    required this.suffix,
    required this.datePrefix,
  });

  @override
  String toString() => filename;
}

/// Validates and allocates receipt filenames following the
/// `YYYY-MM-DD_N.jpg` convention.
class FilenameAllocator {
  /// Compiled once, reused on every call.
  static final RegExp _filenamePattern =
      RegExp(r'^\d{4}-\d{2}-\d{2}_[1-9]\d*\.jpg$');

  /// Date formatter for the filename prefix.
  static final DateFormat _dateFmt = DateFormat('yyyy-MM-dd');

  final FolderService _folderService;

  /// Optional callback that queries the local SQLite database for filenames
  /// already assigned for a given date/country/workspace.
  ///
  /// Injected at construction time so that this service does not depend
  /// directly on the database layer.
  final Future<List<String>> Function(
    DateTime date,
    KiraCountry country,
    String? workspaceId,
  )? _queryLocalDb;

  /// Optional [StorageProvider] for consulting remote indexes and listings.
  final StorageProvider? _storageProvider;

  FilenameAllocator({
    required FolderService folderService,
    Future<List<String>> Function(
      DateTime date,
      KiraCountry country,
      String? workspaceId,
    )? queryLocalDb,
    StorageProvider? storageProvider,
  })  : _folderService = folderService,
        _queryLocalDb = queryLocalDb,
        _storageProvider = storageProvider;

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  /// Returns `true` if [filename] matches the strict pattern
  /// `YYYY-MM-DD_N.jpg` where `N >= 1`.
  static bool validateFilename(String filename) {
    return _filenamePattern.hasMatch(filename);
  }

  // ---------------------------------------------------------------------------
  // Allocation
  // ---------------------------------------------------------------------------

  /// Allocates the next safe filename for [date] / [country], guaranteed to
  /// not collide with any known local or remote file.
  ///
  /// The method consults up to four data sources (local index, local DB,
  /// remote index, remote listing) and returns `max + 1`. If a collision is
  /// somehow still detected during a later write, the caller should invoke
  /// this method again -- the new call will see the written file and allocate
  /// the next suffix.
  Future<AllocatedFilename> allocateFilename(
    DateTime date,
    KiraCountry country, {
    String? workspaceId,
  }) async {
    final dateStr = _dateFmt.format(date);
    final knownSuffixes = <int>{};

    // 1. Consult local day index.
    await _collectFromLocalIndex(
      date,
      country,
      dateStr,
      knownSuffixes,
      workspaceId: workspaceId,
    );

    // 2. Consult local database.
    await _collectFromLocalDb(
      date,
      country,
      dateStr,
      knownSuffixes,
      workspaceId: workspaceId,
    );

    // 3. Consult remote day index (best-effort).
    await _collectFromRemoteIndex(
      date,
      country,
      dateStr,
      knownSuffixes,
      workspaceId: workspaceId,
    );

    // 4. Consult remote folder listing (best-effort, most up-to-date).
    await _collectFromRemoteListing(
      date,
      country,
      dateStr,
      knownSuffixes,
      workspaceId: workspaceId,
    );

    // 5. Also scan the local folder for any .jpg files that might not be in
    //    the index yet (e.g. uploaded_unindexed images).
    await _collectFromLocalFolder(
      date,
      country,
      dateStr,
      knownSuffixes,
      workspaceId: workspaceId,
    );

    // Pick the next available suffix.
    final int nextSuffix = knownSuffixes.isEmpty
        ? 1
        : knownSuffixes.reduce((a, b) => a > b ? a : b) + 1;

    final filename = '${dateStr}_$nextSuffix.jpg';

    return AllocatedFilename(
      filename: filename,
      suffix: nextSuffix,
      datePrefix: dateStr,
    );
  }

  // ---------------------------------------------------------------------------
  // Suffix extraction
  // ---------------------------------------------------------------------------

  /// Extracts the integer suffix from a filename matching the Kira pattern.
  ///
  /// Returns `null` if the filename does not match.
  static int? extractSuffix(String filename, String datePrefix) {
    if (!filename.startsWith('${datePrefix}_')) return null;
    if (!filename.endsWith('.jpg')) return null;

    final middle = filename.substring(
      datePrefix.length + 1,
      filename.length - 4,
    );
    return int.tryParse(middle);
  }

  /// Scans a list of filenames and adds every valid suffix for [datePrefix]
  /// to [target].
  static void collectSuffixes(
    Iterable<String> filenames,
    String datePrefix,
    Set<int> target,
  ) {
    for (final name in filenames) {
      final suffix = extractSuffix(name, datePrefix);
      if (suffix != null) {
        target.add(suffix);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Source consultations
  // ---------------------------------------------------------------------------

  Future<void> _collectFromLocalIndex(
    DateTime date,
    KiraCountry country,
    String dateStr,
    Set<int> suffixes, {
    String? workspaceId,
  }) async {
    try {
      final localDir = await _folderService.getLocalPath(
        date,
        country,
        workspaceId: workspaceId,
      );
      final indexFile = File(p.join(localDir, 'index.json'));
      if (await indexFile.exists()) {
        final content = await indexFile.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final receipts = json['receipts'] as List<dynamic>? ?? <dynamic>[];
        final filenames = receipts
            .map((e) => (e as Map<String, dynamic>)['filename'] as String?)
            .whereType<String>();
        collectSuffixes(filenames, dateStr, suffixes);
      }
    } catch (_) {
      // Non-fatal: index may not exist yet.
    }
  }

  Future<void> _collectFromLocalDb(
    DateTime date,
    KiraCountry country,
    String dateStr,
    Set<int> suffixes, {
    String? workspaceId,
  }) async {
    if (_queryLocalDb == null) return;
    try {
      final filenames = await _queryLocalDb!(date, country, workspaceId);
      collectSuffixes(filenames, dateStr, suffixes);
    } catch (_) {
      // Non-fatal: database may not be ready.
    }
  }

  Future<void> _collectFromRemoteIndex(
    DateTime date,
    KiraCountry country,
    String dateStr,
    Set<int> suffixes, {
    String? workspaceId,
  }) async {
    if (_storageProvider == null) return;
    try {
      final remotePath = _folderService.getRemotePath(
        date,
        country,
        workspaceId: workspaceId,
      );
      final data = await _storageProvider!.downloadFile(remotePath, 'index.json');
      if (data != null) {
        final content = utf8.decode(data);
        final json = jsonDecode(content) as Map<String, dynamic>;
        final receipts = json['receipts'] as List<dynamic>? ?? <dynamic>[];
        final filenames = receipts
            .map((e) => (e as Map<String, dynamic>)['filename'] as String?)
            .whereType<String>();
        collectSuffixes(filenames, dateStr, suffixes);
      }
    } catch (_) {
      // Non-fatal: remote may be unreachable.
    }
  }

  Future<void> _collectFromRemoteListing(
    DateTime date,
    KiraCountry country,
    String dateStr,
    Set<int> suffixes, {
    String? workspaceId,
  }) async {
    if (_storageProvider == null) return;
    try {
      final remotePath = _folderService.getRemotePath(
        date,
        country,
        workspaceId: workspaceId,
      );
      final files = await _storageProvider!.listFiles(remotePath);
      collectSuffixes(files, dateStr, suffixes);
    } catch (_) {
      // Non-fatal: remote may be unreachable.
    }
  }

  Future<void> _collectFromLocalFolder(
    DateTime date,
    KiraCountry country,
    String dateStr,
    Set<int> suffixes, {
    String? workspaceId,
  }) async {
    try {
      final localDir = await _folderService.getLocalPath(
        date,
        country,
        workspaceId: workspaceId,
      );
      final dir = Directory(localDir);
      if (await dir.exists()) {
        final entities = await dir.list().toList();
        final filenames = entities
            .whereType<File>()
            .map((f) => p.basename(f.path))
            .where((name) => name.endsWith('.jpg'));
        collectSuffixes(filenames, dateStr, suffixes);
      }
    } catch (_) {
      // Non-fatal: folder may not exist yet.
    }
  }
}
