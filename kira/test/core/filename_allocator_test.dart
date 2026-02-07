/// Tests for the Kira filename allocator.
///
/// The filename allocator is responsible for generating unique, collision-free
/// filenames in the format `YYYY-MM-DD_N.jpg` where N is a positive integer
/// suffix starting at 1. It must check both local and remote file lists to
/// avoid collisions.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

// ---------------------------------------------------------------------------
// Filename allocator specification (under test)
// ---------------------------------------------------------------------------

/// Regex that every allocated filename must match.
///
/// Format: `YYYY-MM-DD_N.jpg` where N >= 1 (no leading zeros, no _0).
final RegExp kFilenamePattern = RegExp(r'^\d{4}-\d{2}-\d{2}_[1-9]\d*\.jpg$');

/// Validates that [filename] conforms to the Kira filename convention.
bool isValidFilename(String filename) => kFilenamePattern.hasMatch(filename);

/// Parses the integer suffix from a valid filename.
///
/// Returns `null` when [filename] does not match the expected pattern.
int? parseSuffix(String filename) {
  final match = kFilenamePattern.firstMatch(filename);
  if (match == null) return null;
  final withoutExt = filename.replaceAll('.jpg', '');
  final parts = withoutExt.split('_');
  if (parts.length != 2) return null;
  return int.tryParse(parts[1]);
}

/// Abstract interface that the filename allocator depends on.
abstract class FileListProvider {
  /// Returns filenames present in the local day folder.
  Future<List<String>> listLocalFiles(String dayFolder);

  /// Returns filenames present in the remote day folder.
  Future<List<String>> listRemoteFiles(String dayFolder);
}

/// Mock implementation of [FileListProvider].
class MockFileListProvider extends Mock implements FileListProvider {}

/// Allocates a collision-free filename for a given date.
///
/// The allocator examines both local and remote file lists, finds the maximum
/// existing suffix for the target date, and returns `date_(max+1).jpg`.
///
/// Throws [ArgumentError] if [date] is not in `YYYY-MM-DD` format.
class FilenameAllocator {
  final FileListProvider _fileListProvider;

  const FilenameAllocator(this._fileListProvider);

  /// Allocates the next available filename for [date].
  ///
  /// [date] must be in `YYYY-MM-DD` format (e.g. `2025-06-14`).
  Future<String> allocate(String date) async {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) {
      throw ArgumentError('Invalid date format: $date');
    }

    final localFiles = await _fileListProvider.listLocalFiles(date);
    final remoteFiles = await _fileListProvider.listRemoteFiles(date);

    final allFiles = <String>{...localFiles, ...remoteFiles};

    int maxSuffix = 0;
    for (final file in allFiles) {
      final suffix = parseSuffix(file);
      if (suffix != null && suffix > maxSuffix) {
        maxSuffix = suffix;
      }
    }

    final newSuffix = maxSuffix + 1;
    final filename = '${date}_$newSuffix.jpg';

    // Safety check: the allocated filename must not already exist.
    assert(!allFiles.contains(filename),
        'FilenameAllocator produced a collision: $filename');

    return filename;
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockFileListProvider mockProvider;
  late FilenameAllocator allocator;

  setUp(() {
    mockProvider = MockFileListProvider();
    allocator = FilenameAllocator(mockProvider);
  });

  group('FilenameAllocator', () {
    group('basic allocation', () {
      test('first file for empty day folder gets suffix _1', () async {
        when(mockProvider.listLocalFiles('2025-06-14'))
            .thenAnswer((_) async => []);
        when(mockProvider.listRemoteFiles('2025-06-14'))
            .thenAnswer((_) async => []);

        final filename = await allocator.allocate('2025-06-14');

        expect(filename, '2025-06-14_1.jpg');
        expect(isValidFilename(filename), isTrue);
      });

      test('second file gets suffix _2 when _1 exists locally', () async {
        when(mockProvider.listLocalFiles('2025-06-14'))
            .thenAnswer((_) async => ['2025-06-14_1.jpg']);
        when(mockProvider.listRemoteFiles('2025-06-14'))
            .thenAnswer((_) async => []);

        final filename = await allocator.allocate('2025-06-14');

        expect(filename, '2025-06-14_2.jpg');
        expect(isValidFilename(filename), isTrue);
      });

      test('third file gets suffix _3 when _1 and _2 exist', () async {
        when(mockProvider.listLocalFiles('2025-06-14'))
            .thenAnswer((_) async => [
                  '2025-06-14_1.jpg',
                  '2025-06-14_2.jpg',
                ]);
        when(mockProvider.listRemoteFiles('2025-06-14'))
            .thenAnswer((_) async => []);

        final filename = await allocator.allocate('2025-06-14');

        expect(filename, '2025-06-14_3.jpg');
      });

      test('sequential allocation produces monotonically increasing suffixes',
          () async {
        // Simulate repeated allocations by changing the file list each time.
        var localFiles = <String>[];

        when(mockProvider.listRemoteFiles(any))
            .thenAnswer((_) async => []);
        when(mockProvider.listLocalFiles('2025-06-14'))
            .thenAnswer((_) async => List.from(localFiles));

        for (var i = 1; i <= 5; i++) {
          final filename = await allocator.allocate('2025-06-14');
          expect(filename, '2025-06-14_$i.jpg');
          localFiles.add(filename);

          // Re-stub with the updated list.
          when(mockProvider.listLocalFiles('2025-06-14'))
              .thenAnswer((_) async => List.from(localFiles));
        }
      });
    });

    group('collision detection with existing local files', () {
      test('skips past existing local filenames', () async {
        when(mockProvider.listLocalFiles('2025-06-14')).thenAnswer(
          (_) async => [
            '2025-06-14_1.jpg',
            '2025-06-14_2.jpg',
            '2025-06-14_3.jpg',
          ],
        );
        when(mockProvider.listRemoteFiles('2025-06-14'))
            .thenAnswer((_) async => []);

        final filename = await allocator.allocate('2025-06-14');

        expect(filename, '2025-06-14_4.jpg');
      });

      test('handles gap in local suffixes by using max + 1', () async {
        // Files 1, 3, 5 exist -- allocator should return 6, not 2 or 4.
        when(mockProvider.listLocalFiles('2025-06-14')).thenAnswer(
          (_) async => [
            '2025-06-14_1.jpg',
            '2025-06-14_3.jpg',
            '2025-06-14_5.jpg',
          ],
        );
        when(mockProvider.listRemoteFiles('2025-06-14'))
            .thenAnswer((_) async => []);

        final filename = await allocator.allocate('2025-06-14');

        expect(filename, '2025-06-14_6.jpg');
      });
    });

    group('collision detection with existing remote files', () {
      test('skips past existing remote filenames', () async {
        when(mockProvider.listLocalFiles('2025-06-14'))
            .thenAnswer((_) async => []);
        when(mockProvider.listRemoteFiles('2025-06-14')).thenAnswer(
          (_) async => [
            '2025-06-14_1.jpg',
            '2025-06-14_2.jpg',
          ],
        );

        final filename = await allocator.allocate('2025-06-14');

        expect(filename, '2025-06-14_3.jpg');
      });

      test('handles gap in remote suffixes by using max + 1', () async {
        when(mockProvider.listLocalFiles('2025-06-14'))
            .thenAnswer((_) async => []);
        when(mockProvider.listRemoteFiles('2025-06-14')).thenAnswer(
          (_) async => [
            '2025-06-14_1.jpg',
            '2025-06-14_10.jpg',
          ],
        );

        final filename = await allocator.allocate('2025-06-14');

        expect(filename, '2025-06-14_11.jpg');
      });
    });

    group('collision when both local and remote have different max suffixes',
        () {
      test('uses max of both + 1 when local max > remote max', () async {
        when(mockProvider.listLocalFiles('2025-06-14')).thenAnswer(
          (_) async => ['2025-06-14_5.jpg'],
        );
        when(mockProvider.listRemoteFiles('2025-06-14')).thenAnswer(
          (_) async => ['2025-06-14_3.jpg'],
        );

        final filename = await allocator.allocate('2025-06-14');

        expect(filename, '2025-06-14_6.jpg');
      });

      test('uses max of both + 1 when remote max > local max', () async {
        when(mockProvider.listLocalFiles('2025-06-14')).thenAnswer(
          (_) async => ['2025-06-14_2.jpg'],
        );
        when(mockProvider.listRemoteFiles('2025-06-14')).thenAnswer(
          (_) async => ['2025-06-14_7.jpg'],
        );

        final filename = await allocator.allocate('2025-06-14');

        expect(filename, '2025-06-14_8.jpg');
      });

      test('handles overlapping files in local and remote', () async {
        when(mockProvider.listLocalFiles('2025-06-14')).thenAnswer(
          (_) async => [
            '2025-06-14_1.jpg',
            '2025-06-14_3.jpg',
          ],
        );
        when(mockProvider.listRemoteFiles('2025-06-14')).thenAnswer(
          (_) async => [
            '2025-06-14_2.jpg',
            '2025-06-14_4.jpg',
          ],
        );

        final filename = await allocator.allocate('2025-06-14');

        expect(filename, '2025-06-14_5.jpg');
      });

      test('handles duplicate filenames present in both local and remote',
          () async {
        when(mockProvider.listLocalFiles('2025-06-14')).thenAnswer(
          (_) async => ['2025-06-14_3.jpg'],
        );
        when(mockProvider.listRemoteFiles('2025-06-14')).thenAnswer(
          (_) async => ['2025-06-14_3.jpg'],
        );

        final filename = await allocator.allocate('2025-06-14');

        expect(filename, '2025-06-14_4.jpg');
      });
    });

    group('concurrent allocation attempts', () {
      test(
          'two allocations against the same snapshot produce the same filename',
          () async {
        // Without external locking, two allocations that see the same file
        // list will compute the same next filename. This tests that the
        // allocator is deterministic given the same inputs.
        when(mockProvider.listLocalFiles('2025-06-14'))
            .thenAnswer((_) async => ['2025-06-14_1.jpg']);
        when(mockProvider.listRemoteFiles('2025-06-14'))
            .thenAnswer((_) async => []);

        final results = await Future.wait([
          allocator.allocate('2025-06-14'),
          allocator.allocate('2025-06-14'),
        ]);

        // Both see the same snapshot, so both compute _2.
        expect(results[0], '2025-06-14_2.jpg');
        expect(results[1], '2025-06-14_2.jpg');
      });

      test(
          'sequential allocations with updated file lists produce unique names',
          () async {
        // First allocation.
        when(mockProvider.listLocalFiles('2025-06-14'))
            .thenAnswer((_) async => []);
        when(mockProvider.listRemoteFiles('2025-06-14'))
            .thenAnswer((_) async => []);

        final first = await allocator.allocate('2025-06-14');
        expect(first, '2025-06-14_1.jpg');

        // Second allocation after first file is "written".
        when(mockProvider.listLocalFiles('2025-06-14'))
            .thenAnswer((_) async => ['2025-06-14_1.jpg']);

        final second = await allocator.allocate('2025-06-14');
        expect(second, '2025-06-14_2.jpg');

        expect(first, isNot(equals(second)));
      });
    });

    group('invalid filename rejection', () {
      test('wrong format without date prefix is rejected', () {
        expect(isValidFilename('receipt_1.jpg'), isFalse);
      });

      test('wrong format with wrong extension is rejected', () {
        expect(isValidFilename('2025-06-14_1.png'), isFalse);
      });

      test('suffix _0 is rejected', () {
        expect(isValidFilename('2025-06-14_0.jpg'), isFalse);
      });

      test('negative suffix is rejected', () {
        // Negative numbers won't match [1-9]\\d* pattern.
        expect(isValidFilename('2025-06-14_-1.jpg'), isFalse);
      });

      test('no extension is rejected', () {
        expect(isValidFilename('2025-06-14_1'), isFalse);
      });

      test('missing suffix is rejected', () {
        expect(isValidFilename('2025-06-14.jpg'), isFalse);
      });

      test('leading zero in suffix is rejected', () {
        expect(isValidFilename('2025-06-14_01.jpg'), isFalse);
      });

      test('non-numeric suffix is rejected', () {
        expect(isValidFilename('2025-06-14_abc.jpg'), isFalse);
      });

      test('extra underscore segments are rejected', () {
        expect(isValidFilename('2025-06-14_1_2.jpg'), isFalse);
      });

      test('empty string is rejected', () {
        expect(isValidFilename(''), isFalse);
      });
    });

    group('regex validation', () {
      test('pattern matches valid filenames', () {
        final validFilenames = [
          '2025-06-14_1.jpg',
          '2025-01-01_1.jpg',
          '2025-12-31_99.jpg',
          '2025-06-14_100.jpg',
          '2025-06-14_9999.jpg',
          '1999-01-01_1.jpg',
          '2030-12-31_12345.jpg',
        ];

        for (final name in validFilenames) {
          expect(isValidFilename(name), isTrue,
              reason: 'Expected $name to be valid');
        }
      });

      test('pattern rejects invalid filenames', () {
        final invalidFilenames = [
          '',
          'foo.jpg',
          '2025-06-14_0.jpg', // _0 not allowed
          '2025-06-14_-1.jpg', // negative
          '2025-06-14_01.jpg', // leading zero
          '2025-06-14.jpg', // no suffix
          '2025-06-14_1.png', // wrong extension
          '2025-06-14_1', // no extension
          '20250614_1.jpg', // no dashes in date
          'abcd-ef-gh_1.jpg', // non-numeric date
          '2025-06-14_1.jpg.bak', // extra extension
          '2025-06-14_ 1.jpg', // space in suffix
        ];

        for (final name in invalidFilenames) {
          expect(isValidFilename(name), isFalse,
              reason: 'Expected $name to be invalid');
        }
      });
    });

    group('allocator never returns an existing filename', () {
      test('allocated filename is not in local file list', () async {
        final existingLocal = [
          '2025-06-14_1.jpg',
          '2025-06-14_2.jpg',
          '2025-06-14_3.jpg',
        ];

        when(mockProvider.listLocalFiles('2025-06-14'))
            .thenAnswer((_) async => existingLocal);
        when(mockProvider.listRemoteFiles('2025-06-14'))
            .thenAnswer((_) async => []);

        final filename = await allocator.allocate('2025-06-14');

        expect(existingLocal.contains(filename), isFalse);
      });

      test('allocated filename is not in remote file list', () async {
        final existingRemote = [
          '2025-06-14_1.jpg',
          '2025-06-14_2.jpg',
        ];

        when(mockProvider.listLocalFiles('2025-06-14'))
            .thenAnswer((_) async => []);
        when(mockProvider.listRemoteFiles('2025-06-14'))
            .thenAnswer((_) async => existingRemote);

        final filename = await allocator.allocate('2025-06-14');

        expect(existingRemote.contains(filename), isFalse);
      });

      test('allocated filename is not in either file list combined', () async {
        final existingLocal = ['2025-06-14_1.jpg', '2025-06-14_3.jpg'];
        final existingRemote = ['2025-06-14_2.jpg', '2025-06-14_4.jpg'];

        when(mockProvider.listLocalFiles('2025-06-14'))
            .thenAnswer((_) async => existingLocal);
        when(mockProvider.listRemoteFiles('2025-06-14'))
            .thenAnswer((_) async => existingRemote);

        final filename = await allocator.allocate('2025-06-14');
        final allExisting = {...existingLocal, ...existingRemote};

        expect(allExisting.contains(filename), isFalse);
        expect(isValidFilename(filename), isTrue);
      });

      test('allocated filename is always valid per regex', () async {
        when(mockProvider.listLocalFiles('2025-01-01'))
            .thenAnswer((_) async => []);
        when(mockProvider.listRemoteFiles('2025-01-01'))
            .thenAnswer((_) async => []);

        final filename = await allocator.allocate('2025-01-01');

        expect(isValidFilename(filename), isTrue);
      });

      test('stress test: 100 sequential allocations produce unique filenames',
          () async {
        var files = <String>[];

        when(mockProvider.listRemoteFiles('2025-06-14'))
            .thenAnswer((_) async => []);

        for (var i = 0; i < 100; i++) {
          when(mockProvider.listLocalFiles('2025-06-14'))
              .thenAnswer((_) async => List.from(files));

          final filename = await allocator.allocate('2025-06-14');
          expect(files.contains(filename), isFalse,
              reason: 'Collision at iteration $i: $filename');
          expect(isValidFilename(filename), isTrue);
          files.add(filename);
        }

        // All 100 filenames should be unique.
        expect(files.toSet().length, 100);
      });
    });

    group('invalid date rejection', () {
      test('throws ArgumentError for invalid date format', () async {
        expect(
          () => allocator.allocate('20250614'),
          throwsArgumentError,
        );
      });

      test('throws ArgumentError for empty date', () async {
        expect(
          () => allocator.allocate(''),
          throwsArgumentError,
        );
      });

      test('throws ArgumentError for date with slashes', () async {
        expect(
          () => allocator.allocate('2025/06/14'),
          throwsArgumentError,
        );
      });
    });

    group('parseSuffix', () {
      test('parses suffix from valid filename', () {
        expect(parseSuffix('2025-06-14_1.jpg'), 1);
        expect(parseSuffix('2025-06-14_42.jpg'), 42);
        expect(parseSuffix('2025-06-14_999.jpg'), 999);
      });

      test('returns null for invalid filename', () {
        expect(parseSuffix('invalid.jpg'), isNull);
        expect(parseSuffix('2025-06-14_0.jpg'), isNull);
        expect(parseSuffix(''), isNull);
      });
    });
  });
}
