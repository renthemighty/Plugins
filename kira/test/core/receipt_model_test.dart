/// Tests for the Kira Receipt model.
///
/// Validates JSON and SQLite map serialisation round-trips, copyWith semantics,
/// default values, nullable field handling, and value-based equality.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:kira/core/models/receipt.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Creates a fully populated [Receipt] with sensible defaults that can be
/// selectively overridden via the named parameters.
Receipt _makeReceipt({
  String receiptId = 'r-0001',
  String capturedAt = '2025-06-14T09:32:11',
  String timezone = 'America/Toronto',
  String filename = '20250614_093211_r0001.jpg',
  double amountTracked = 42.50,
  String currencyCode = 'CAD',
  String country = 'canada',
  String region = 'ON',
  String category = 'meals',
  String? notes = 'Business lunch with client',
  bool? taxApplicable = true,
  String checksumSha256 = 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2',
  String deviceId = 'device-abc',
  String captureSessionId = 'session-001',
  String source = kReceiptSourceCamera,
  String createdAt = '2025-06-14T09:32:11Z',
  String updatedAt = '2025-06-14T09:32:11Z',
  bool conflict = false,
  String? supersedesFilename,
}) {
  return Receipt(
    receiptId: receiptId,
    capturedAt: capturedAt,
    timezone: timezone,
    filename: filename,
    amountTracked: amountTracked,
    currencyCode: currencyCode,
    country: country,
    region: region,
    category: category,
    notes: notes,
    taxApplicable: taxApplicable,
    checksumSha256: checksumSha256,
    deviceId: deviceId,
    captureSessionId: captureSessionId,
    source: source,
    createdAt: createdAt,
    updatedAt: updatedAt,
    conflict: conflict,
    supersedesFilename: supersedesFilename,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Receipt', () {
    // -----------------------------------------------------------------------
    // JSON serialisation
    // -----------------------------------------------------------------------

    group('JSON serialisation', () {
      test('toJson produces a map with all expected keys', () {
        final receipt = _makeReceipt();
        final json = receipt.toJson();

        expect(json['receipt_id'], receipt.receiptId);
        expect(json['captured_at'], receipt.capturedAt);
        expect(json['timezone'], receipt.timezone);
        expect(json['filename'], receipt.filename);
        expect(json['amount_tracked'], receipt.amountTracked);
        expect(json['currency_code'], receipt.currencyCode);
        expect(json['country'], receipt.country);
        expect(json['region'], receipt.region);
        expect(json['category'], receipt.category);
        expect(json['notes'], receipt.notes);
        expect(json['tax_applicable'], receipt.taxApplicable);
        expect(json['checksum_sha256'], receipt.checksumSha256);
        expect(json['device_id'], receipt.deviceId);
        expect(json['capture_session_id'], receipt.captureSessionId);
        expect(json['source'], receipt.source);
        expect(json['created_at'], receipt.createdAt);
        expect(json['updated_at'], receipt.updatedAt);
        expect(json['conflict'], receipt.conflict);
        expect(json['supersedes_filename'], receipt.supersedesFilename);
      });

      test('fromJson reconstructs an identical receipt from a JSON map', () {
        final original = _makeReceipt();
        final json = original.toJson();
        final restored = Receipt.fromJson(json);

        expect(restored, equals(original));
      });

      test('all fields round-trip through JSON correctly', () {
        final original = _makeReceipt(
          notes: 'Round-trip test with special chars: "quotes" & commas,',
          taxApplicable: false,
          conflict: true,
          supersedesFilename: 'old_receipt.jpg',
        );

        final json = original.toJson();
        final restored = Receipt.fromJson(json);

        expect(restored.receiptId, original.receiptId);
        expect(restored.capturedAt, original.capturedAt);
        expect(restored.timezone, original.timezone);
        expect(restored.filename, original.filename);
        expect(restored.amountTracked, original.amountTracked);
        expect(restored.currencyCode, original.currencyCode);
        expect(restored.country, original.country);
        expect(restored.region, original.region);
        expect(restored.category, original.category);
        expect(restored.notes, original.notes);
        expect(restored.taxApplicable, original.taxApplicable);
        expect(restored.checksumSha256, original.checksumSha256);
        expect(restored.deviceId, original.deviceId);
        expect(restored.captureSessionId, original.captureSessionId);
        expect(restored.source, original.source);
        expect(restored.createdAt, original.createdAt);
        expect(restored.updatedAt, original.updatedAt);
        expect(restored.conflict, original.conflict);
        expect(restored.supersedesFilename, original.supersedesFilename);
      });

      test('fromJson uses default source when key is absent', () {
        final json = _makeReceipt().toJson();
        json.remove('source');

        final restored = Receipt.fromJson(json);
        expect(restored.source, kReceiptSourceCamera);
      });

      test('fromJson uses default conflict=false when key is absent', () {
        final json = _makeReceipt().toJson();
        json.remove('conflict');

        final restored = Receipt.fromJson(json);
        expect(restored.conflict, isFalse);
      });

      test('fromJson handles integer amount_tracked by converting to double', () {
        final json = _makeReceipt().toJson();
        json['amount_tracked'] = 100; // int, not double

        final restored = Receipt.fromJson(json);
        expect(restored.amountTracked, 100.0);
        expect(restored.amountTracked, isA<double>());
      });
    });

    // -----------------------------------------------------------------------
    // SQLite map serialisation
    // -----------------------------------------------------------------------

    group('SQLite map serialisation', () {
      test('toMap converts booleans to integer representation', () {
        final receipt = _makeReceipt(taxApplicable: true, conflict: true);
        final map = receipt.toMap();

        expect(map['tax_applicable'], 1);
        expect(map['conflict'], 1);
      });

      test('toMap stores false booleans as 0', () {
        final receipt = _makeReceipt(taxApplicable: false, conflict: false);
        final map = receipt.toMap();

        expect(map['tax_applicable'], 0);
        expect(map['conflict'], 0);
      });

      test('toMap stores null taxApplicable as null', () {
        final receipt = _makeReceipt(taxApplicable: null);
        final map = receipt.toMap();

        expect(map['tax_applicable'], isNull);
      });

      test('all fields round-trip through SQLite map correctly', () {
        final original = _makeReceipt(
          taxApplicable: true,
          conflict: true,
          supersedesFilename: 'old_file.jpg',
          notes: 'SQLite round-trip test',
        );

        final map = original.toMap();
        final restored = Receipt.fromMap(map);

        expect(restored.receiptId, original.receiptId);
        expect(restored.capturedAt, original.capturedAt);
        expect(restored.timezone, original.timezone);
        expect(restored.filename, original.filename);
        expect(restored.amountTracked, original.amountTracked);
        expect(restored.currencyCode, original.currencyCode);
        expect(restored.country, original.country);
        expect(restored.region, original.region);
        expect(restored.category, original.category);
        expect(restored.notes, original.notes);
        expect(restored.taxApplicable, original.taxApplicable);
        expect(restored.checksumSha256, original.checksumSha256);
        expect(restored.deviceId, original.deviceId);
        expect(restored.captureSessionId, original.captureSessionId);
        expect(restored.source, original.source);
        expect(restored.createdAt, original.createdAt);
        expect(restored.updatedAt, original.updatedAt);
        expect(restored.conflict, original.conflict);
        expect(restored.supersedesFilename, original.supersedesFilename);
      });

      test('fromMap handles null tax_applicable from SQLite', () {
        final map = _makeReceipt(taxApplicable: null).toMap();
        expect(map['tax_applicable'], isNull);

        final restored = Receipt.fromMap(map);
        expect(restored.taxApplicable, isNull);
      });

      test('fromMap interprets 0 as false and 1 as true for conflict', () {
        final mapWithZero = _makeReceipt(conflict: false).toMap();
        expect(Receipt.fromMap(mapWithZero).conflict, isFalse);

        final mapWithOne = _makeReceipt(conflict: true).toMap();
        expect(Receipt.fromMap(mapWithOne).conflict, isTrue);
      });

      test('fromMap defaults conflict to false when key is absent', () {
        final map = _makeReceipt().toMap();
        map.remove('conflict');

        final restored = Receipt.fromMap(map);
        expect(restored.conflict, isFalse);
      });

      test('fromMap defaults source to camera when key is absent', () {
        final map = _makeReceipt().toMap();
        map.remove('source');

        final restored = Receipt.fromMap(map);
        expect(restored.source, kReceiptSourceCamera);
      });
    });

    // -----------------------------------------------------------------------
    // copyWith
    // -----------------------------------------------------------------------

    group('copyWith', () {
      test('creates new instance with a single changed field', () {
        final original = _makeReceipt();
        final modified = original.copyWith(amountTracked: 99.99);

        expect(modified.amountTracked, 99.99);
        expect(modified.receiptId, original.receiptId);
        expect(modified.filename, original.filename);
        expect(modified.category, original.category);
      });

      test('creates new instance with changed fields while preserving others', () {
        final original = _makeReceipt();
        final modified = original.copyWith(
          category: 'transport',
          region: 'BC',
          conflict: true,
        );

        expect(modified.category, 'transport');
        expect(modified.region, 'BC');
        expect(modified.conflict, isTrue);
        // Unchanged fields should be preserved.
        expect(modified.receiptId, original.receiptId);
        expect(modified.amountTracked, original.amountTracked);
        expect(modified.notes, original.notes);
      });

      test('copyWith with no arguments returns an identical copy', () {
        final original = _makeReceipt();
        final copy = original.copyWith();

        expect(copy, equals(original));
        // But it should be a different object.
        expect(identical(copy, original), isFalse);
      });

      test('copyWith can set nullable notes to null', () {
        final original = _makeReceipt(notes: 'some notes');
        final modified = original.copyWith(notes: () => null);

        expect(modified.notes, isNull);
        expect(original.notes, 'some notes');
      });

      test('copyWith can set nullable taxApplicable to null', () {
        final original = _makeReceipt(taxApplicable: true);
        final modified = original.copyWith(taxApplicable: () => null);

        expect(modified.taxApplicable, isNull);
        expect(original.taxApplicable, isTrue);
      });

      test('copyWith can set nullable supersedesFilename to null', () {
        final original = _makeReceipt(supersedesFilename: 'old.jpg');
        final modified = original.copyWith(supersedesFilename: () => null);

        expect(modified.supersedesFilename, isNull);
        expect(original.supersedesFilename, 'old.jpg');
      });

      test('copyWith can set supersedesFilename to a new value', () {
        final original = _makeReceipt(supersedesFilename: null);
        final modified = original.copyWith(
          supersedesFilename: () => 'previous_file.jpg',
        );

        expect(modified.supersedesFilename, 'previous_file.jpg');
        expect(original.supersedesFilename, isNull);
      });
    });

    // -----------------------------------------------------------------------
    // Default values
    // -----------------------------------------------------------------------

    group('default values', () {
      test('source defaults to camera', () {
        final receipt = _makeReceipt();
        expect(receipt.source, kReceiptSourceCamera);
        expect(receipt.source, 'camera');
      });

      test('conflict defaults to false', () {
        final receipt = _makeReceipt();
        expect(receipt.conflict, isFalse);
      });

      test('kReceiptSourceCamera constant is "camera"', () {
        expect(kReceiptSourceCamera, 'camera');
      });
    });

    // -----------------------------------------------------------------------
    // Nullable fields
    // -----------------------------------------------------------------------

    group('nullable fields', () {
      test('notes can be null', () {
        final receipt = _makeReceipt(notes: null);
        expect(receipt.notes, isNull);
      });

      test('notes can have a value', () {
        final receipt = _makeReceipt(notes: 'test note');
        expect(receipt.notes, 'test note');
      });

      test('taxApplicable can be null', () {
        final receipt = _makeReceipt(taxApplicable: null);
        expect(receipt.taxApplicable, isNull);
      });

      test('taxApplicable can be true', () {
        final receipt = _makeReceipt(taxApplicable: true);
        expect(receipt.taxApplicable, isTrue);
      });

      test('taxApplicable can be false', () {
        final receipt = _makeReceipt(taxApplicable: false);
        expect(receipt.taxApplicable, isFalse);
      });

      test('supersedesFilename can be null', () {
        final receipt = _makeReceipt(supersedesFilename: null);
        expect(receipt.supersedesFilename, isNull);
      });

      test('supersedesFilename can have a value', () {
        final receipt = _makeReceipt(supersedesFilename: 'old_file.jpg');
        expect(receipt.supersedesFilename, 'old_file.jpg');
      });

      test('nullable fields survive JSON round-trip when null', () {
        final original = _makeReceipt(
          notes: null,
          taxApplicable: null,
          supersedesFilename: null,
        );
        final restored = Receipt.fromJson(original.toJson());

        expect(restored.notes, isNull);
        expect(restored.taxApplicable, isNull);
        expect(restored.supersedesFilename, isNull);
      });

      test('nullable fields survive SQLite map round-trip when null', () {
        final original = _makeReceipt(
          notes: null,
          taxApplicable: null,
          supersedesFilename: null,
        );
        final restored = Receipt.fromMap(original.toMap());

        expect(restored.notes, isNull);
        expect(restored.taxApplicable, isNull);
        expect(restored.supersedesFilename, isNull);
      });
    });

    // -----------------------------------------------------------------------
    // Equality & hashCode
    // -----------------------------------------------------------------------

    group('equality and hashCode', () {
      test('two receipts with identical fields are equal', () {
        final a = _makeReceipt();
        final b = _makeReceipt();

        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('two receipts with different receiptId are not equal', () {
        final a = _makeReceipt(receiptId: 'id-1');
        final b = _makeReceipt(receiptId: 'id-2');

        expect(a, isNot(equals(b)));
      });

      test('two receipts with different amounts are not equal', () {
        final a = _makeReceipt(amountTracked: 10.00);
        final b = _makeReceipt(amountTracked: 20.00);

        expect(a, isNot(equals(b)));
      });

      test('identical receipt is equal to itself', () {
        final receipt = _makeReceipt();
        expect(receipt == receipt, isTrue);
      });

      test('receipt is not equal to non-Receipt object', () {
        final receipt = _makeReceipt();
        // ignore: unrelated_type_equality_checks
        expect(receipt == 'not a receipt', isFalse);
      });
    });

    // -----------------------------------------------------------------------
    // toString
    // -----------------------------------------------------------------------

    group('toString', () {
      test('toString includes receiptId, filename, amount, and conflict', () {
        final receipt = _makeReceipt(
          receiptId: 'r-test',
          filename: 'test.jpg',
          amountTracked: 55.00,
          currencyCode: 'USD',
          conflict: true,
        );
        final str = receipt.toString();

        expect(str, contains('r-test'));
        expect(str, contains('test.jpg'));
        expect(str, contains('55.0'));
        expect(str, contains('USD'));
        expect(str, contains('true'));
      });
    });
  });
}
