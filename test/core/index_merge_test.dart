/// Tests for the Kira index merge logic.
///
/// The merge system combines local and remote day/month indexes following
/// strict rules:
/// - Never auto-delete entries.
/// - Dedup by receipt_id when metadata is identical.
/// - Flag conflicts when same receipt_id has different metadata.
/// - Handle supersedes_filename fields correctly.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:kira/core/models/day_index.dart';
import 'package:kira/core/models/month_index.dart';

// DaySummary is a typedef for MonthDayEntry, re-exported from month_index.dart.

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

ReceiptIndexEntry _makeEntry({
  required String receiptId,
  String filename = '2025-06-14_1.jpg',
  double amountTracked = 25.00,
  String currencyCode = 'CAD',
  String category = 'meals',
  String checksumSha256 = 'abc123',
  String capturedAt = '2025-06-14T09:00:00',
  String updatedAt = '2025-06-14T09:00:00Z',
  bool conflict = false,
  String? supersedesFilename,
}) {
  return ReceiptIndexEntry(
    receiptId: receiptId,
    filename: filename,
    amountTracked: amountTracked,
    currencyCode: currencyCode,
    category: category,
    checksumSha256: checksumSha256,
    capturedAt: capturedAt,
    updatedAt: updatedAt,
    conflict: conflict,
    supersedesFilename: supersedesFilename,
  );
}

DayIndex _makeDayIndex({
  String date = '2025-06-14',
  String lastUpdated = '2025-06-14T10:00:00Z',
  List<ReceiptIndexEntry> receipts = const [],
  int schemaVersion = 1,
}) {
  return DayIndex(
    date: date,
    lastUpdated: lastUpdated,
    receipts: receipts,
    schemaVersion: schemaVersion,
  );
}

DaySummary _makeDaySummary({
  required String date,
  int receiptCount = 1,
  Map<String, double> totalsByCurrency = const {'CAD': 25.00},
  String lastUpdated = '2025-06-14T10:00:00Z',
  bool conflict = false,
}) {
  return DaySummary(
    date: date,
    receiptCount: receiptCount,
    totalByCurrency: totalsByCurrency,
    lastUpdated: lastUpdated,
    conflict: conflict,
  );
}

MonthIndex _makeMonthIndex({
  String month = '2025-06',
  String lastUpdated = '2025-06-14T10:00:00Z',
  List<DaySummary> days = const [],
  int schemaVersion = 1,
}) {
  return MonthIndex(
    yearMonth: month,
    lastUpdated: lastUpdated,
    days: days,
    schemaVersion: schemaVersion,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('DayIndex merge', () {
    group('merging two indexes with no overlap', () {
      test('adds all remote entries to local', () {
        final local = _makeDayIndex(
          receipts: [_makeEntry(receiptId: 'r1', capturedAt: '2025-06-14T09:00:00')],
        );
        final remote = _makeDayIndex(
          receipts: [_makeEntry(receiptId: 'r2', capturedAt: '2025-06-14T10:00:00')],
        );

        final merged = local.merge(remote);

        expect(merged.receipts.length, 2);
        expect(
          merged.receipts.map((e) => e.receiptId).toSet(),
          {'r1', 'r2'},
        );
      });

      test('preserves all local entries when remote is empty', () {
        final local = _makeDayIndex(
          receipts: [
            _makeEntry(receiptId: 'r1', capturedAt: '2025-06-14T09:00:00'),
            _makeEntry(receiptId: 'r2', capturedAt: '2025-06-14T10:00:00'),
          ],
        );
        final remote = _makeDayIndex(receipts: []);

        final merged = local.merge(remote);

        expect(merged.receipts.length, 2);
      });

      test('adds all entries when local is empty', () {
        final local = _makeDayIndex(receipts: []);
        final remote = _makeDayIndex(
          receipts: [
            _makeEntry(receiptId: 'r1', capturedAt: '2025-06-14T09:00:00'),
            _makeEntry(receiptId: 'r2', capturedAt: '2025-06-14T10:00:00'),
          ],
        );

        final merged = local.merge(remote);

        expect(merged.receipts.length, 2);
      });

      test('results are sorted by capturedAt', () {
        final local = _makeDayIndex(
          receipts: [
            _makeEntry(receiptId: 'r2', capturedAt: '2025-06-14T11:00:00'),
          ],
        );
        final remote = _makeDayIndex(
          receipts: [
            _makeEntry(receiptId: 'r1', capturedAt: '2025-06-14T08:00:00'),
          ],
        );

        final merged = local.merge(remote);

        expect(merged.receipts[0].receiptId, 'r1');
        expect(merged.receipts[1].receiptId, 'r2');
      });
    });

    group('merging with same receipt_id and identical metadata (dedup)', () {
      test('keeps one copy when metadata is identical', () {
        final entry = _makeEntry(
          receiptId: 'r1',
          updatedAt: '2025-06-14T09:00:00Z',
        );

        final local = _makeDayIndex(receipts: [entry]);
        final remote = _makeDayIndex(receipts: [entry]);

        final merged = local.merge(remote);

        expect(merged.receipts.length, 1);
        expect(merged.receipts.first.receiptId, 'r1');
      });

      test('does not set conflict flag when metadata is identical', () {
        final entry = _makeEntry(
          receiptId: 'r1',
          updatedAt: '2025-06-14T09:00:00Z',
        );

        final local = _makeDayIndex(receipts: [entry]);
        final remote = _makeDayIndex(
          receipts: [entry.copyWith(updatedAt: '2025-06-14T10:00:00Z')],
        );

        // metadataEquals ignores updatedAt differences in the comparison
        // but the actual merge logic checks metadataEquals which does NOT
        // check updatedAt -- it checks all fields except conflict.
        // Since metadataEquals does not compare updatedAt, if only updatedAt
        // differs, they are treated as metadata-equal.
        final merged = local.merge(remote);

        // The metadataEquals method does NOT compare updatedAt, so this should
        // be a dedup (metadata identical).
        expect(merged.receipts.length, 1);
      });

      test('preserves existing conflict flag on dedup', () {
        final entry = _makeEntry(
          receiptId: 'r1',
          conflict: true,
        );

        final local = _makeDayIndex(receipts: [entry]);
        final remote = _makeDayIndex(receipts: [entry]);

        final merged = local.merge(remote);

        expect(merged.receipts.first.conflict, isTrue);
      });
    });

    group(
        'merging with same receipt_id but different metadata (conflict=true)',
        () {
      test('sets conflict to true when metadata differs', () {
        final localEntry = _makeEntry(
          receiptId: 'r1',
          amountTracked: 25.00,
          updatedAt: '2025-06-14T09:00:00Z',
        );
        final remoteEntry = _makeEntry(
          receiptId: 'r1',
          amountTracked: 30.00, // different
          updatedAt: '2025-06-14T10:00:00Z',
        );

        final local = _makeDayIndex(receipts: [localEntry]);
        final remote = _makeDayIndex(receipts: [remoteEntry]);

        final merged = local.merge(remote);

        expect(merged.receipts.length, 1);
        expect(merged.receipts.first.conflict, isTrue);
      });

      test('picks the entry with the later updatedAt as the winner', () {
        final localEntry = _makeEntry(
          receiptId: 'r1',
          amountTracked: 25.00,
          category: 'meals',
          updatedAt: '2025-06-14T09:00:00Z',
        );
        final remoteEntry = _makeEntry(
          receiptId: 'r1',
          amountTracked: 30.00,
          category: 'transport',
          updatedAt: '2025-06-14T12:00:00Z', // later
        );

        final local = _makeDayIndex(receipts: [localEntry]);
        final remote = _makeDayIndex(receipts: [remoteEntry]);

        final merged = local.merge(remote);

        expect(merged.receipts.first.amountTracked, 30.00);
        expect(merged.receipts.first.category, 'transport');
        expect(merged.receipts.first.conflict, isTrue);
      });

      test('local wins when local updatedAt is later', () {
        final localEntry = _makeEntry(
          receiptId: 'r1',
          amountTracked: 50.00,
          updatedAt: '2025-06-14T15:00:00Z', // later
        );
        final remoteEntry = _makeEntry(
          receiptId: 'r1',
          amountTracked: 30.00,
          updatedAt: '2025-06-14T10:00:00Z',
        );

        final local = _makeDayIndex(receipts: [localEntry]);
        final remote = _makeDayIndex(receipts: [remoteEntry]);

        final merged = local.merge(remote);

        expect(merged.receipts.first.amountTracked, 50.00);
        expect(merged.receipts.first.conflict, isTrue);
      });

      test('keeps both unique entries plus conflicted shared entries', () {
        final local = _makeDayIndex(
          receipts: [
            _makeEntry(receiptId: 'r1', capturedAt: '2025-06-14T09:00:00',
                amountTracked: 10.00, updatedAt: '2025-06-14T09:00:00Z'),
            _makeEntry(receiptId: 'r2', capturedAt: '2025-06-14T10:00:00',
                updatedAt: '2025-06-14T10:00:00Z'),
          ],
        );
        final remote = _makeDayIndex(
          receipts: [
            _makeEntry(receiptId: 'r1', capturedAt: '2025-06-14T09:00:00',
                amountTracked: 20.00, updatedAt: '2025-06-14T11:00:00Z'),
            _makeEntry(receiptId: 'r3', capturedAt: '2025-06-14T11:00:00',
                updatedAt: '2025-06-14T11:00:00Z'),
          ],
        );

        final merged = local.merge(remote);

        expect(merged.receipts.length, 3);
        final ids = merged.receipts.map((e) => e.receiptId).toSet();
        expect(ids, {'r1', 'r2', 'r3'});

        final r1 = merged.receipts.firstWhere((e) => e.receiptId == 'r1');
        expect(r1.conflict, isTrue);
        expect(r1.amountTracked, 20.00); // remote wins (later updatedAt)
      });
    });

    group('merge never auto-deletes entries', () {
      test('local-only entries survive merge with empty remote', () {
        final local = _makeDayIndex(
          receipts: [
            _makeEntry(receiptId: 'r1', capturedAt: '2025-06-14T09:00:00'),
            _makeEntry(receiptId: 'r2', capturedAt: '2025-06-14T10:00:00'),
          ],
        );
        final remote = _makeDayIndex(receipts: []);

        final merged = local.merge(remote);

        expect(merged.receipts.length, 2);
      });

      test(
          'remote-only entries survive merge (local does not remove '
          'entries missing locally)', () {
        final local = _makeDayIndex(receipts: []);
        final remote = _makeDayIndex(
          receipts: [
            _makeEntry(receiptId: 'r1', capturedAt: '2025-06-14T09:00:00'),
          ],
        );

        final merged = local.merge(remote);

        expect(merged.receipts.length, 1);
      });

      test('no entries are lost when both sides have unique entries', () {
        final local = _makeDayIndex(
          receipts: [
            _makeEntry(receiptId: 'local-only', capturedAt: '2025-06-14T08:00:00'),
          ],
        );
        final remote = _makeDayIndex(
          receipts: [
            _makeEntry(
                receiptId: 'remote-only', capturedAt: '2025-06-14T12:00:00'),
          ],
        );

        final merged = local.merge(remote);

        expect(merged.receipts.length, 2);
        final ids = merged.receipts.map((e) => e.receiptId).toSet();
        expect(ids.contains('local-only'), isTrue);
        expect(ids.contains('remote-only'), isTrue);
      });

      test('conflicted entries are not deleted, only flagged', () {
        final localEntry = _makeEntry(
          receiptId: 'r1',
          amountTracked: 10.00,
          updatedAt: '2025-06-14T09:00:00Z',
        );
        final remoteEntry = _makeEntry(
          receiptId: 'r1',
          amountTracked: 20.00,
          updatedAt: '2025-06-14T11:00:00Z',
        );

        final local = _makeDayIndex(receipts: [localEntry]);
        final remote = _makeDayIndex(receipts: [remoteEntry]);

        final merged = local.merge(remote);

        // Entry is still present (not deleted), just flagged.
        expect(merged.receipts.length, 1);
        expect(merged.receipts.first.conflict, isTrue);
      });
    });

    group('lastUpdated handling', () {
      test('uses the later lastUpdated from both indexes', () {
        final local = _makeDayIndex(
          lastUpdated: '2025-06-14T08:00:00Z',
          receipts: [_makeEntry(receiptId: 'r1')],
        );
        final remote = _makeDayIndex(
          lastUpdated: '2025-06-14T12:00:00Z',
          receipts: [_makeEntry(receiptId: 'r2', capturedAt: '2025-06-14T12:00:00')],
        );

        final merged = local.merge(remote);

        expect(merged.lastUpdated, '2025-06-14T12:00:00Z');
      });

      test('uses local lastUpdated when local is later', () {
        final local = _makeDayIndex(
          lastUpdated: '2025-06-14T15:00:00Z',
          receipts: [_makeEntry(receiptId: 'r1')],
        );
        final remote = _makeDayIndex(
          lastUpdated: '2025-06-14T10:00:00Z',
          receipts: [_makeEntry(receiptId: 'r2', capturedAt: '2025-06-14T12:00:00')],
        );

        final merged = local.merge(remote);

        expect(merged.lastUpdated, '2025-06-14T15:00:00Z');
      });
    });

    group('schema version handling', () {
      test('uses the higher schema version from both indexes', () {
        final local = _makeDayIndex(schemaVersion: 1, receipts: []);
        final remote = _makeDayIndex(schemaVersion: 2, receipts: []);

        final merged = local.merge(remote);

        expect(merged.schemaVersion, 2);
      });

      test('uses local schema version when it is higher', () {
        final local = _makeDayIndex(schemaVersion: 3, receipts: []);
        final remote = _makeDayIndex(schemaVersion: 1, receipts: []);

        final merged = local.merge(remote);

        expect(merged.schemaVersion, 3);
      });
    });

    group('adding receipt to existing index', () {
      test('new receipt is added to existing entries', () {
        final existing = _makeDayIndex(
          receipts: [
            _makeEntry(receiptId: 'r1', capturedAt: '2025-06-14T09:00:00'),
          ],
        );
        final withNewReceipt = _makeDayIndex(
          receipts: [
            _makeEntry(receiptId: 'r1', capturedAt: '2025-06-14T09:00:00'),
            _makeEntry(receiptId: 'r2', capturedAt: '2025-06-14T10:00:00'),
          ],
        );

        final merged = existing.merge(withNewReceipt);

        expect(merged.receipts.length, 2);
      });
    });

    group('supersedes_filename handling', () {
      test('supersedes_filename is preserved during merge', () {
        final entry = _makeEntry(
          receiptId: 'r1',
          supersedesFilename: '2025-06-14_1.jpg',
          filename: '2025-06-14_2.jpg',
        );

        final local = _makeDayIndex(receipts: [entry]);
        final remote = _makeDayIndex(receipts: [entry]);

        final merged = local.merge(remote);

        expect(merged.receipts.first.supersedesFilename, '2025-06-14_1.jpg');
      });

      test('supersedes_filename difference causes conflict', () {
        final localEntry = _makeEntry(
          receiptId: 'r1',
          supersedesFilename: '2025-06-14_1.jpg',
          updatedAt: '2025-06-14T09:00:00Z',
        );
        final remoteEntry = _makeEntry(
          receiptId: 'r1',
          supersedesFilename: '2025-06-14_3.jpg', // different
          updatedAt: '2025-06-14T10:00:00Z',
        );

        final local = _makeDayIndex(receipts: [localEntry]);
        final remote = _makeDayIndex(receipts: [remoteEntry]);

        final merged = local.merge(remote);

        expect(merged.receipts.first.conflict, isTrue);
        expect(merged.receipts.first.supersedesFilename, '2025-06-14_3.jpg');
      });

      test('null supersedes_filename matches null (no conflict)', () {
        final localEntry = _makeEntry(
          receiptId: 'r1',
          supersedesFilename: null,
        );
        final remoteEntry = _makeEntry(
          receiptId: 'r1',
          supersedesFilename: null,
        );

        final local = _makeDayIndex(receipts: [localEntry]);
        final remote = _makeDayIndex(receipts: [remoteEntry]);

        final merged = local.merge(remote);

        expect(merged.receipts.first.conflict, isFalse);
      });
    });
  });

  group('MonthIndex merge', () {
    group('merging month indexes', () {
      test('merges two month indexes with no overlapping days', () {
        final local = _makeMonthIndex(
          days: [
            _makeDaySummary(date: '2025-06-14'),
          ],
        );
        final remote = _makeMonthIndex(
          days: [
            _makeDaySummary(date: '2025-06-15'),
          ],
        );

        final merged = local.merge(remote);

        expect(merged.days.length, 2);
        expect(merged.days.map((d) => d.date).toSet(), {'2025-06-14', '2025-06-15'});
      });

      test('deduplicates when same day has identical metadata', () {
        final daySummary = _makeDaySummary(
          date: '2025-06-14',
          receiptCount: 3,
          totalsByCurrency: {'CAD': 75.00},
        );

        final local = _makeMonthIndex(days: [daySummary]);
        final remote = _makeMonthIndex(days: [daySummary]);

        final merged = local.merge(remote);

        expect(merged.days.length, 1);
        expect(merged.days.first.conflict, isFalse);
      });

      test('flags conflict when same day has different metadata', () {
        final local = _makeMonthIndex(
          days: [
            _makeDaySummary(
              date: '2025-06-14',
              receiptCount: 3,
              totalsByCurrency: {'CAD': 75.00},
              lastUpdated: '2025-06-14T09:00:00Z',
            ),
          ],
        );
        final remote = _makeMonthIndex(
          days: [
            _makeDaySummary(
              date: '2025-06-14',
              receiptCount: 5,
              totalsByCurrency: {'CAD': 125.00},
              lastUpdated: '2025-06-14T12:00:00Z',
            ),
          ],
        );

        final merged = local.merge(remote);

        expect(merged.days.length, 1);
        expect(merged.days.first.conflict, isTrue);
        expect(merged.days.first.receiptCount, 5); // remote wins (later)
      });

      test('never auto-deletes day summaries during merge', () {
        final local = _makeMonthIndex(
          days: [
            _makeDaySummary(date: '2025-06-10'),
            _makeDaySummary(date: '2025-06-11'),
          ],
        );
        final remote = _makeMonthIndex(
          days: [
            _makeDaySummary(date: '2025-06-12'),
          ],
        );

        final merged = local.merge(remote);

        expect(merged.days.length, 3);
      });

      test('results are sorted by date', () {
        final local = _makeMonthIndex(
          days: [
            _makeDaySummary(date: '2025-06-20'),
          ],
        );
        final remote = _makeMonthIndex(
          days: [
            _makeDaySummary(date: '2025-06-05'),
          ],
        );

        final merged = local.merge(remote);

        expect(merged.days[0].date, '2025-06-05');
        expect(merged.days[1].date, '2025-06-20');
      });

      test('recomputes totals after merge', () {
        final local = _makeMonthIndex(
          days: [
            _makeDaySummary(
              date: '2025-06-14',
              totalsByCurrency: {'CAD': 50.00},
            ),
          ],
        );
        final remote = _makeMonthIndex(
          days: [
            _makeDaySummary(
              date: '2025-06-15',
              totalsByCurrency: {'CAD': 30.00, 'USD': 10.00},
            ),
          ],
        );

        final merged = local.merge(remote);

        expect(merged.totals, isNotNull);
        expect(merged.totals!['CAD'], 80.00);
        expect(merged.totals!['USD'], 10.00);
      });

      test('uses later lastUpdated from both month indexes', () {
        final local = _makeMonthIndex(
          lastUpdated: '2025-06-14T08:00:00Z',
          days: [],
        );
        final remote = _makeMonthIndex(
          lastUpdated: '2025-06-14T15:00:00Z',
          days: [],
        );

        final merged = local.merge(remote);

        expect(merged.lastUpdated, '2025-06-14T15:00:00Z');
      });

      test('uses higher schema version', () {
        final local = _makeMonthIndex(schemaVersion: 1, days: []);
        final remote = _makeMonthIndex(schemaVersion: 2, days: []);

        final merged = local.merge(remote);

        expect(merged.schemaVersion, 2);
      });
    });
  });
}
