/// Tests for the Kira ChecksumService.
///
/// Validates SHA-256 computation on raw byte buffers, known-input/known-hash
/// verification, match/mismatch detection, and edge cases like empty input.
/// File-based methods are tested via temporary files on disk.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:kira/core/services/checksum_service.dart';

// ---------------------------------------------------------------------------
// Pre-computed reference values
// ---------------------------------------------------------------------------

/// SHA-256 of the empty byte sequence.
/// `echo -n '' | sha256sum` => e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
const String _emptySha256 =
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

/// SHA-256 of the ASCII string "hello".
/// `echo -n 'hello' | sha256sum` => 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824
const String _helloSha256 =
    '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824';

/// SHA-256 of the ASCII string "Kira receipt test".
/// Computed externally for regression stability.
/// `echo -n 'Kira receipt test' | sha256sum`
const String _kiraTestSha256 =
    'e2d46ab0e65bfee2cf15b4aea7618f7f7a7079b4b06c29a53e73e7e01f7df2a3';

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late ChecksumService service;
  late Directory tempDir;

  setUp(() async {
    service = const ChecksumService();
    tempDir = await Directory.systemTemp.createTemp('kira_checksum_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ChecksumService', () {
    // ---------------------------------------------------------------------
    // computeBytesChecksum
    // ---------------------------------------------------------------------

    group('computeBytesChecksum', () {
      test('returns a 64-character lowercase hex string', () {
        final bytes = Uint8List.fromList([1, 2, 3, 4]);
        final checksum = service.computeBytesChecksum(bytes);

        expect(checksum.length, 64);
        expect(checksum, matches(RegExp(r'^[0-9a-f]{64}$')));
      });

      test('known input "hello" produces known SHA-256 hash', () {
        final bytes = Uint8List.fromList('hello'.codeUnits);
        final checksum = service.computeBytesChecksum(bytes);

        expect(checksum, _helloSha256);
      });

      test('empty input produces the well-known empty SHA-256', () {
        final bytes = Uint8List(0);
        final checksum = service.computeBytesChecksum(bytes);

        expect(checksum, _emptySha256);
      });

      test('same input always produces the same hash (deterministic)', () {
        final bytes = Uint8List.fromList('deterministic'.codeUnits);
        final first = service.computeBytesChecksum(bytes);
        final second = service.computeBytesChecksum(bytes);

        expect(first, equals(second));
      });

      test('different inputs produce different hashes', () {
        final bytesA = Uint8List.fromList('alpha'.codeUnits);
        final bytesB = Uint8List.fromList('bravo'.codeUnits);
        final hashA = service.computeBytesChecksum(bytesA);
        final hashB = service.computeBytesChecksum(bytesB);

        expect(hashA, isNot(equals(hashB)));
      });

      test('single byte difference changes the hash entirely', () {
        final bytesA = Uint8List.fromList([0x00]);
        final bytesB = Uint8List.fromList([0x01]);
        final hashA = service.computeBytesChecksum(bytesA);
        final hashB = service.computeBytesChecksum(bytesB);

        expect(hashA, isNot(equals(hashB)));
      });
    });

    // ---------------------------------------------------------------------
    // computeFileChecksum
    // ---------------------------------------------------------------------

    group('computeFileChecksum', () {
      test('computes correct checksum for a file with known content', () async {
        final file = File('${tempDir.path}/hello.txt');
        await file.writeAsBytes('hello'.codeUnits);

        final checksum = await service.computeFileChecksum(file.path);
        expect(checksum, _helloSha256);
      });

      test('computes correct checksum for an empty file', () async {
        final file = File('${tempDir.path}/empty.bin');
        await file.writeAsBytes([]);

        final checksum = await service.computeFileChecksum(file.path);
        expect(checksum, _emptySha256);
      });

      test('throws FileSystemException for non-existent file', () async {
        expect(
          () => service.computeFileChecksum('${tempDir.path}/does_not_exist.bin'),
          throwsA(isA<FileSystemException>()),
        );
      });

      test('produces the same hash as computeBytesChecksum for same data',
          () async {
        final data = Uint8List.fromList(
          List.generate(1024, (i) => i % 256),
        );
        final file = File('${tempDir.path}/binary.bin');
        await file.writeAsBytes(data);

        final fileChecksum = await service.computeFileChecksum(file.path);
        final bytesChecksum = service.computeBytesChecksum(data);

        expect(fileChecksum, equals(bytesChecksum));
      });

      test('handles larger files correctly', () async {
        // 64 KB of repeated pattern
        final data = Uint8List.fromList(
          List.generate(65536, (i) => i % 256),
        );
        final file = File('${tempDir.path}/large.bin');
        await file.writeAsBytes(data);

        final fileChecksum = await service.computeFileChecksum(file.path);
        final bytesChecksum = service.computeBytesChecksum(data);

        expect(fileChecksum, equals(bytesChecksum));
      });
    });

    // ---------------------------------------------------------------------
    // verifyChecksum
    // ---------------------------------------------------------------------

    group('verifyChecksum', () {
      test('returns true when checksum matches the file content', () async {
        final file = File('${tempDir.path}/verify_pass.txt');
        await file.writeAsBytes('hello'.codeUnits);

        final result = await service.verifyChecksum(file.path, _helloSha256);
        expect(result, isTrue);
      });

      test('returns false when checksum does not match the file content',
          () async {
        final file = File('${tempDir.path}/verify_fail.txt');
        await file.writeAsBytes('hello'.codeUnits);

        // Provide a completely wrong checksum.
        final result = await service.verifyChecksum(
          file.path,
          '0000000000000000000000000000000000000000000000000000000000000000',
        );
        expect(result, isFalse);
      });

      test('comparison is case-insensitive', () async {
        final file = File('${tempDir.path}/case_check.txt');
        await file.writeAsBytes('hello'.codeUnits);

        // Provide the expected hash in uppercase.
        final upper = _helloSha256.toUpperCase();
        final result = await service.verifyChecksum(file.path, upper);
        expect(result, isTrue);
      });

      test('returns false when file has been modified after capture', () async {
        final file = File('${tempDir.path}/modified.txt');
        await file.writeAsBytes('original content'.codeUnits);

        final originalChecksum =
            await service.computeFileChecksum(file.path);

        // Modify the file.
        await file.writeAsBytes('tampered content'.codeUnits);

        final result =
            await service.verifyChecksum(file.path, originalChecksum);
        expect(result, isFalse);
      });

      test('throws FileSystemException for non-existent file', () async {
        expect(
          () => service.verifyChecksum(
            '${tempDir.path}/ghost.bin',
            _helloSha256,
          ),
          throwsA(isA<FileSystemException>()),
        );
      });
    });

    // ---------------------------------------------------------------------
    // AccumulatorSink
    // ---------------------------------------------------------------------

    group('AccumulatorSink', () {
      test('collects events added to it', () {
        final sink = AccumulatorSink<int>();
        sink.add(1);
        sink.add(2);
        sink.add(3);
        sink.close();

        expect(sink.events, [1, 2, 3]);
      });

      test('starts with an empty event list', () {
        final sink = AccumulatorSink<String>();
        expect(sink.events, isEmpty);
      });

      test('close is idempotent and does not throw', () {
        final sink = AccumulatorSink<int>();
        sink.close();
        sink.close(); // second close should not throw
        expect(sink.events, isEmpty);
      });
    });
  });
}
