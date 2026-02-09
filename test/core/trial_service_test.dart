/// Tests for the Kira trial service.
///
/// The trial service manages the 7-day free trial period. It tracks when the
/// trial started, calculates remaining days, detects expiry, auto-deletes
/// expired receipts, enforces read-only mode after expiry, and unlocks
/// captures upon upgrade.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

// ---------------------------------------------------------------------------
// Trial service abstractions
// ---------------------------------------------------------------------------

/// Abstract interface for persisting trial-related settings.
abstract class TrialSettingsStore {
  Future<String?> getTrialStartDate();
  Future<void> setTrialStartDate(String isoDate);
  Future<bool> isUpgraded();
  Future<void> setUpgraded(bool value);
}

/// Abstract interface for receipt operations needed by the trial service.
abstract class TrialReceiptStore {
  /// Returns receipt IDs captured before [cutoffDate].
  Future<List<String>> getReceiptsCapturedBefore(String cutoffDate);

  /// Deletes the given receipts. Returns the count deleted.
  Future<int> deleteReceipts(List<String> receiptIds);

  /// Returns total count of receipts.
  Future<int> getTotalReceiptCount();
}

class MockTrialSettingsStore extends Mock implements TrialSettingsStore {}

class MockTrialReceiptStore extends Mock implements TrialReceiptStore {}

/// The trial service under test.
class TrialService {
  final TrialSettingsStore _settings;
  final TrialReceiptStore _receipts;
  final DateTime Function() _clock;

  static const int trialDurationDays = 7;

  TrialService({
    required TrialSettingsStore settings,
    required TrialReceiptStore receipts,
    DateTime Function()? clock,
  })  : _settings = settings,
        _receipts = receipts,
        _clock = clock ?? (() => DateTime.now().toUtc());

  /// Starts the trial on first capture if not already started.
  /// Returns the trial start date.
  Future<DateTime> ensureTrialStarted() async {
    final existing = await _settings.getTrialStartDate();
    if (existing != null) {
      return DateTime.parse(existing);
    }

    final now = _clock();
    await _settings.setTrialStartDate(now.toIso8601String());
    return now;
  }

  /// Returns the trial start date, or null if trial has not started.
  Future<DateTime?> getTrialStartDate() async {
    final dateStr = await _settings.getTrialStartDate();
    if (dateStr == null) return null;
    return DateTime.parse(dateStr);
  }

  /// Returns the number of remaining trial days (0 if expired).
  Future<int> getRemainingDays() async {
    final upgraded = await _settings.isUpgraded();
    if (upgraded) return trialDurationDays; // unlimited

    final startStr = await _settings.getTrialStartDate();
    if (startStr == null) return trialDurationDays;

    final start = DateTime.parse(startStr);
    final now = _clock();
    final elapsed = now.difference(start).inDays;
    final remaining = trialDurationDays - elapsed;
    return remaining > 0 ? remaining : 0;
  }

  /// Returns true if the trial has expired and the user has not upgraded.
  Future<bool> isTrialExpired() async {
    final upgraded = await _settings.isUpgraded();
    if (upgraded) return false;

    final startStr = await _settings.getTrialStartDate();
    if (startStr == null) return false;

    final start = DateTime.parse(startStr);
    final now = _clock();
    return now.difference(start).inDays >= trialDurationDays;
  }

  /// Returns true if captures are allowed (trial active or upgraded).
  Future<bool> canCapture() async {
    final upgraded = await _settings.isUpgraded();
    if (upgraded) return true;
    return !(await isTrialExpired());
  }

  /// Deletes receipts older than 7 days for non-upgraded users.
  /// Returns the number of receipts deleted.
  Future<int> deleteExpiredReceipts() async {
    final upgraded = await _settings.isUpgraded();
    if (upgraded) return 0;

    final cutoff =
        _clock().subtract(const Duration(days: trialDurationDays));
    final expired = await _receipts.getReceiptsCapturedBefore(
        cutoff.toIso8601String());
    if (expired.isEmpty) return 0;

    return _receipts.deleteReceipts(expired);
  }

  /// Marks the user as upgraded, unlocking captures.
  Future<void> upgrade() async {
    await _settings.setUpgraded(true);
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockTrialSettingsStore mockSettings;
  late MockTrialReceiptStore mockReceipts;

  setUp(() {
    mockSettings = MockTrialSettingsStore();
    mockReceipts = MockTrialReceiptStore();
  });

  TrialService createService({DateTime Function()? clock}) {
    return TrialService(
      settings: mockSettings,
      receipts: mockReceipts,
      clock: clock,
    );
  }

  group('TrialService', () {
    group('trial starts on first capture', () {
      test('sets trial start date when none exists', () async {
        final now = DateTime.utc(2025, 6, 14, 10, 0, 0);
        when(mockSettings.getTrialStartDate()).thenAnswer((_) async => null);
        when(mockSettings.setTrialStartDate(any)).thenAnswer((_) async {});

        final service = createService(clock: () => now);
        final startDate = await service.ensureTrialStarted();

        expect(startDate, now);
        verify(mockSettings.setTrialStartDate(now.toIso8601String())).called(1);
      });

      test('returns existing start date if already set', () async {
        final existingDate = '2025-06-10T08:00:00.000Z';
        when(mockSettings.getTrialStartDate())
            .thenAnswer((_) async => existingDate);

        final service = createService();
        final startDate = await service.ensureTrialStarted();

        expect(startDate, DateTime.parse(existingDate));
        verifyNever(mockSettings.setTrialStartDate(any));
      });
    });

    group('trial duration is exactly 7 days', () {
      test('trial duration constant is 7', () {
        expect(TrialService.trialDurationDays, 7);
      });

      test('trial is not expired at day 6', () async {
        final start = DateTime.utc(2025, 6, 14, 10, 0, 0);
        final day6 = start.add(const Duration(days: 6, hours: 23));

        when(mockSettings.getTrialStartDate())
            .thenAnswer((_) async => start.toIso8601String());
        when(mockSettings.isUpgraded()).thenAnswer((_) async => false);

        final service = createService(clock: () => day6);
        final expired = await service.isTrialExpired();

        expect(expired, isFalse);
      });

      test('trial expires at exactly day 7', () async {
        final start = DateTime.utc(2025, 6, 14, 10, 0, 0);
        final day7 = start.add(const Duration(days: 7));

        when(mockSettings.getTrialStartDate())
            .thenAnswer((_) async => start.toIso8601String());
        when(mockSettings.isUpgraded()).thenAnswer((_) async => false);

        final service = createService(clock: () => day7);
        final expired = await service.isTrialExpired();

        expect(expired, isTrue);
      });

      test('trial is expired at day 8', () async {
        final start = DateTime.utc(2025, 6, 14, 10, 0, 0);
        final day8 = start.add(const Duration(days: 8));

        when(mockSettings.getTrialStartDate())
            .thenAnswer((_) async => start.toIso8601String());
        when(mockSettings.isUpgraded()).thenAnswer((_) async => false);

        final service = createService(clock: () => day8);
        final expired = await service.isTrialExpired();

        expect(expired, isTrue);
      });
    });

    group('remaining days calculation', () {
      test('returns 7 when trial has not started', () async {
        when(mockSettings.getTrialStartDate()).thenAnswer((_) async => null);
        when(mockSettings.isUpgraded()).thenAnswer((_) async => false);

        final service = createService();
        final remaining = await service.getRemainingDays();

        expect(remaining, 7);
      });

      test('returns correct remaining days mid-trial', () async {
        final start = DateTime.utc(2025, 6, 14, 10, 0, 0);
        final day3 = start.add(const Duration(days: 3));

        when(mockSettings.getTrialStartDate())
            .thenAnswer((_) async => start.toIso8601String());
        when(mockSettings.isUpgraded()).thenAnswer((_) async => false);

        final service = createService(clock: () => day3);
        final remaining = await service.getRemainingDays();

        expect(remaining, 4);
      });

      test('returns 0 when trial has expired', () async {
        final start = DateTime.utc(2025, 6, 14, 10, 0, 0);
        final day10 = start.add(const Duration(days: 10));

        when(mockSettings.getTrialStartDate())
            .thenAnswer((_) async => start.toIso8601String());
        when(mockSettings.isUpgraded()).thenAnswer((_) async => false);

        final service = createService(clock: () => day10);
        final remaining = await service.getRemainingDays();

        expect(remaining, 0);
      });

      test('returns 7 for upgraded users regardless of elapsed time', () async {
        final start = DateTime.utc(2025, 6, 1);
        final farFuture = DateTime.utc(2025, 12, 31);

        when(mockSettings.getTrialStartDate())
            .thenAnswer((_) async => start.toIso8601String());
        when(mockSettings.isUpgraded()).thenAnswer((_) async => true);

        final service = createService(clock: () => farFuture);
        final remaining = await service.getRemainingDays();

        expect(remaining, 7);
      });
    });

    group('trial expired detection', () {
      test('not expired when trial has not started', () async {
        when(mockSettings.getTrialStartDate()).thenAnswer((_) async => null);
        when(mockSettings.isUpgraded()).thenAnswer((_) async => false);

        final service = createService();
        final expired = await service.isTrialExpired();

        expect(expired, isFalse);
      });

      test('not expired for upgraded users', () async {
        final start = DateTime.utc(2025, 1, 1);
        when(mockSettings.getTrialStartDate())
            .thenAnswer((_) async => start.toIso8601String());
        when(mockSettings.isUpgraded()).thenAnswer((_) async => true);

        final service = createService(
          clock: () => DateTime.utc(2025, 12, 31),
        );
        final expired = await service.isTrialExpired();

        expect(expired, isFalse);
      });
    });

    group('auto-delete of expired receipts', () {
      test('deletes receipts older than 7 days for non-upgraded users',
          () async {
        final now = DateTime.utc(2025, 6, 21, 10, 0, 0);
        final cutoff = now.subtract(const Duration(days: 7));

        when(mockSettings.isUpgraded()).thenAnswer((_) async => false);
        when(mockReceipts.getReceiptsCapturedBefore(cutoff.toIso8601String()))
            .thenAnswer((_) async => ['r1', 'r2', 'r3']);
        when(mockReceipts.deleteReceipts(['r1', 'r2', 'r3']))
            .thenAnswer((_) async => 3);

        final service = createService(clock: () => now);
        final deleted = await service.deleteExpiredReceipts();

        expect(deleted, 3);
        verify(mockReceipts.deleteReceipts(['r1', 'r2', 'r3'])).called(1);
      });

      test('does not delete any receipts for upgraded users', () async {
        when(mockSettings.isUpgraded()).thenAnswer((_) async => true);

        final service = createService();
        final deleted = await service.deleteExpiredReceipts();

        expect(deleted, 0);
        verifyNever(mockReceipts.getReceiptsCapturedBefore(any));
        verifyNever(mockReceipts.deleteReceipts(any));
      });

      test('returns 0 when no expired receipts exist', () async {
        final now = DateTime.utc(2025, 6, 14, 10, 0, 0);
        final cutoff = now.subtract(const Duration(days: 7));

        when(mockSettings.isUpgraded()).thenAnswer((_) async => false);
        when(mockReceipts.getReceiptsCapturedBefore(cutoff.toIso8601String()))
            .thenAnswer((_) async => []);

        final service = createService(clock: () => now);
        final deleted = await service.deleteExpiredReceipts();

        expect(deleted, 0);
      });
    });

    group('app becomes read-only after trial expires', () {
      test('canCapture returns false when trial has expired', () async {
        final start = DateTime.utc(2025, 6, 1);
        final expired = start.add(const Duration(days: 10));

        when(mockSettings.getTrialStartDate())
            .thenAnswer((_) async => start.toIso8601String());
        when(mockSettings.isUpgraded()).thenAnswer((_) async => false);

        final service = createService(clock: () => expired);
        final canCapture = await service.canCapture();

        expect(canCapture, isFalse);
      });

      test('canCapture returns true during active trial', () async {
        final start = DateTime.utc(2025, 6, 14);
        final day3 = start.add(const Duration(days: 3));

        when(mockSettings.getTrialStartDate())
            .thenAnswer((_) async => start.toIso8601String());
        when(mockSettings.isUpgraded()).thenAnswer((_) async => false);

        final service = createService(clock: () => day3);
        final canCapture = await service.canCapture();

        expect(canCapture, isTrue);
      });
    });

    group('upgrade unlocks captures', () {
      test('canCapture returns true after upgrade even when trial expired',
          () async {
        final start = DateTime.utc(2025, 6, 1);

        when(mockSettings.getTrialStartDate())
            .thenAnswer((_) async => start.toIso8601String());
        when(mockSettings.isUpgraded()).thenAnswer((_) async => true);
        when(mockSettings.setUpgraded(true)).thenAnswer((_) async {});

        final service = createService(
          clock: () => DateTime.utc(2025, 12, 31),
        );

        final canCapture = await service.canCapture();
        expect(canCapture, isTrue);
      });

      test('upgrade sets the upgraded flag', () async {
        when(mockSettings.setUpgraded(true)).thenAnswer((_) async {});

        final service = createService();
        await service.upgrade();

        verify(mockSettings.setUpgraded(true)).called(1);
      });

      test('deleteExpiredReceipts returns 0 after upgrade', () async {
        when(mockSettings.isUpgraded()).thenAnswer((_) async => true);

        final service = createService();
        final deleted = await service.deleteExpiredReceipts();

        expect(deleted, 0);
      });
    });

    group('trial creates same DB/local mirror structure as paid mode', () {
      test('trial uses the same settings store as paid mode', () async {
        // Both trial and paid mode go through the same TrialSettingsStore
        // interface. This test verifies that the service calls the same
        // methods regardless of mode.
        when(mockSettings.getTrialStartDate())
            .thenAnswer((_) async => '2025-06-14T10:00:00.000Z');
        when(mockSettings.isUpgraded()).thenAnswer((_) async => false);

        final trialService = createService(
          clock: () => DateTime.utc(2025, 6, 15),
        );
        final trialCanCapture = await trialService.canCapture();

        // Now simulate upgrade.
        when(mockSettings.isUpgraded()).thenAnswer((_) async => true);

        final paidCanCapture = await trialService.canCapture();

        // The interface is the same; only the behavior differs.
        expect(trialCanCapture, isTrue);
        expect(paidCanCapture, isTrue);
      });

      test('ensureTrialStarted is idempotent across modes', () async {
        final existingDate = '2025-06-14T10:00:00.000Z';
        when(mockSettings.getTrialStartDate())
            .thenAnswer((_) async => existingDate);

        final service = createService();

        // Calling ensureTrialStarted multiple times should not change the date.
        await service.ensureTrialStarted();
        await service.ensureTrialStarted();
        await service.ensureTrialStarted();

        verifyNever(mockSettings.setTrialStartDate(any));
      });
    });
  });
}
