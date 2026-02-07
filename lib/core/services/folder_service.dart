/// Strict folder structure management for the Kira receipt storage system.
///
/// Kira organises receipt images and index files into a deterministic
/// hierarchy based on country and date:
///
/// **Personal mode:**
/// ```
/// <ROOT>/Receipts/<COUNTRY>/<YYYY>/<YYYY-MM>/<YYYY-MM-DD>/
/// ```
///
/// **Business / workspace mode:**
/// ```
/// <ROOT>/KiraWorkspaces/<WORKSPACE_ID>/Receipts/<COUNTRY>/<YYYY>/<YYYY-MM>/<YYYY-MM-DD>/
/// ```
///
/// A parallel **local mirror** lives under the app's local data directory:
/// ```
/// AppLocal/Receipts/<COUNTRY>/<YYYY>/<YYYY-MM>/<YYYY-MM-DD>/
/// ```
///
/// This service creates, resolves, and validates those paths. It never
/// deletes folders and it never renames them -- only creates them when they
/// do not yet exist.
library;

import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Allowed country values used in folder paths.
///
/// The values contain no spaces except for `United_States` which uses an
/// underscore so that every path segment is a single token.
enum KiraCountry {
  canada('Canada'),
  unitedStates('United_States');

  final String folderName;
  const KiraCountry(this.folderName);

  /// Resolves a [KiraCountry] from its folder name (case-insensitive).
  ///
  /// Throws [ArgumentError] if [name] does not match any known country.
  static KiraCountry fromFolderName(String name) {
    final lower = name.toLowerCase();
    for (final country in KiraCountry.values) {
      if (country.folderName.toLowerCase() == lower) return country;
    }
    throw ArgumentError('Unknown Kira country folder name: "$name"');
  }
}

/// Provides deterministic path resolution and folder creation for the Kira
/// receipt folder hierarchy.
class FolderService {
  /// Cached local app data root (resolved once, reused).
  String? _localRootCache;

  // ---------------------------------------------------------------------------
  // Path resolution
  // ---------------------------------------------------------------------------

  /// Returns the **relative** receipt folder suffix shared by both local and
  /// remote paths:
  ///
  /// ```
  /// Receipts/<COUNTRY>/<YYYY>/<YYYY-MM>/<YYYY-MM-DD>
  /// ```
  String _receiptSuffix(DateTime date, KiraCountry country) {
    final yyyy = DateFormat('yyyy').format(date);
    final yyyyMM = DateFormat('yyyy-MM').format(date);
    final yyyyMMdd = DateFormat('yyyy-MM-dd').format(date);

    return p.joinAll([
      'Receipts',
      country.folderName,
      yyyy,
      yyyyMM,
      yyyyMMdd,
    ]);
  }

  /// Returns the **remote** (cloud storage root-relative) path for the given
  /// [date], [country], and optional [workspaceId].
  ///
  /// If [workspaceId] is non-null the path is prefixed with
  /// `KiraWorkspaces/<WORKSPACE_ID>/`.
  String getRemotePath(
    DateTime date,
    KiraCountry country, {
    String? workspaceId,
  }) {
    final suffix = _receiptSuffix(date, country);

    if (workspaceId != null && workspaceId.isNotEmpty) {
      return p.joinAll(['KiraWorkspaces', workspaceId, suffix]);
    }
    return suffix;
  }

  /// Returns the **absolute local** path under the app's private data
  /// directory for the given [date], [country], and optional [workspaceId].
  ///
  /// The local root is resolved lazily via [path_provider] and cached for the
  /// lifetime of this service instance.
  Future<String> getLocalPath(
    DateTime date,
    KiraCountry country, {
    String? workspaceId,
  }) async {
    final root = await _localRoot();
    final suffix = _receiptSuffix(date, country);

    if (workspaceId != null && workspaceId.isNotEmpty) {
      return p.joinAll([root, 'KiraWorkspaces', workspaceId, suffix]);
    }
    return p.join(root, suffix);
  }

  // ---------------------------------------------------------------------------
  // Folder creation
  // ---------------------------------------------------------------------------

  /// Creates the full local folder hierarchy for the given [date] and
  /// [country], returning the absolute path to the leaf (day) directory.
  ///
  /// All intermediate directories are created recursively if they do not
  /// already exist. Existing directories are left untouched.
  Future<String> createFolderStructure(
    DateTime date,
    KiraCountry country, {
    String? workspaceId,
  }) async {
    final path = await getLocalPath(date, country, workspaceId: workspaceId);
    await Directory(path).create(recursive: true);
    return path;
  }

  /// Ensures that every ancestor directory of [localPath] exists on the local
  /// file system. This is a convenience wrapper when you already have a
  /// resolved path and just need to guarantee the directories are present.
  Future<void> ensureLocalFolders(String localPath) async {
    await Directory(localPath).create(recursive: true);
  }

  /// Ensures that the folder structure exists on the given remote
  /// [StorageProvider].
  ///
  /// [storageProvider] is an abstract interface (defined elsewhere in the app)
  /// that knows how to create folders on the configured cloud backend. This
  /// service only computes the path and delegates the actual I/O.
  ///
  /// Returns the remote path that was ensured.
  Future<String> ensureRemoteFolders(
    StorageProvider storageProvider,
    DateTime date,
    KiraCountry country, {
    String? workspaceId,
  }) async {
    final remotePath = getRemotePath(date, country, workspaceId: workspaceId);
    await storageProvider.createFolder(remotePath);
    return remotePath;
  }

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  /// Returns `true` if [country] is one of the recognised [KiraCountry]
  /// folder names (case-insensitive).
  static bool isValidCountry(String country) {
    final lower = country.toLowerCase();
    return KiraCountry.values.any(
      (c) => c.folderName.toLowerCase() == lower,
    );
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// Lazily resolves and caches the app-local data directory root.
  Future<String> _localRoot() async {
    if (_localRootCache != null) return _localRootCache!;
    final dir = await getApplicationDocumentsDirectory();
    _localRootCache = dir.path;
    return _localRootCache!;
  }

  /// Allows tests to inject a custom local root without hitting the platform
  /// channel.
  void setLocalRootForTesting(String root) {
    _localRootCache = root;
  }
}

// ---------------------------------------------------------------------------
// StorageProvider interface
// ---------------------------------------------------------------------------

/// Minimal interface that [FolderService] requires from the cloud storage
/// layer.
///
/// The concrete implementation lives in the `storage` package and is injected
/// at app startup.
abstract class StorageProvider {
  /// Creates the folder (and any missing ancestors) at [remotePath] on the
  /// cloud backend. No-op if the folder already exists.
  Future<void> createFolder(String remotePath);

  /// Lists the filenames (not full paths) present in [remotePath].
  ///
  /// Returns an empty list if the folder does not exist or is empty.
  Future<List<String>> listFiles(String remotePath);

  /// Uploads [data] to [remotePath]/[filename] on the cloud backend.
  Future<void> uploadFile(String remotePath, String filename, List<int> data);

  /// Downloads the file at [remotePath]/[filename] from the cloud backend.
  ///
  /// Returns `null` if the file does not exist.
  Future<List<int>?> downloadFile(String remotePath, String filename);
}
