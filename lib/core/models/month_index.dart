/// Month-level index model for the Kira receipt storage system.
///
/// Each month folder (e.g. `2025/06/`) contains a `month_index.json`
/// represented by [MonthIndex]. It provides a high-level summary of every
/// day that has receipts, enabling the UI to render monthly views and totals
/// without downloading individual day indexes.
///
/// Merge semantics mirror the day-level rules:
///   - Day summaries are matched by [DaySummary.date].
///   - New days (present in remote but not local) are **added**.
///   - Days present only in local are **kept** (never auto-deleted).
///   - When both sides have the same date, the one with the later
///     `lastUpdated` wins and `conflict` is set to `true` if metadata differs.
library;

import 'package:collection/collection.dart';

// ---------------------------------------------------------------------------
// DaySummary
// ---------------------------------------------------------------------------

/// A lightweight pointer/summary for a single day inside a month index.
class DaySummary {
  /// The date in `YYYY-MM-DD` format.
  final String date;

  /// Number of receipts stored in the corresponding day index.
  final int receiptCount;

  /// Sum of all `amountTracked` values for the day, broken down by currency.
  /// Example: `{ 'CAD': 134.50, 'USD': 22.00 }`
  final Map<String, double> totalsByCurrency;

  /// ISO-8601 UTC timestamp of the last update to the day's index.
  final String lastUpdated;

  /// Set to `true` when a merge detects conflicting summaries for the same
  /// date. Defaults to `false`.
  final bool conflict;

  const DaySummary({
    required this.date,
    required this.receiptCount,
    required this.totalsByCurrency,
    required this.lastUpdated,
    this.conflict = false,
  });

  factory DaySummary.fromJson(Map<String, dynamic> json) {
    final rawTotals = json['totals_by_currency'] as Map<String, dynamic>? ??
        <String, dynamic>{};
    return DaySummary(
      date: json['date'] as String,
      receiptCount: json['receipt_count'] as int,
      totalsByCurrency: rawTotals
          .map((key, value) => MapEntry(key, (value as num).toDouble())),
      lastUpdated: json['last_updated'] as String,
      conflict: json['conflict'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'date': date,
      'receipt_count': receiptCount,
      'totals_by_currency': totalsByCurrency,
      'last_updated': lastUpdated,
      'conflict': conflict,
    };
  }

  DaySummary copyWith({
    String? date,
    int? receiptCount,
    Map<String, double>? totalsByCurrency,
    String? lastUpdated,
    bool? conflict,
  }) {
    return DaySummary(
      date: date ?? this.date,
      receiptCount: receiptCount ?? this.receiptCount,
      totalsByCurrency: totalsByCurrency ?? this.totalsByCurrency,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      conflict: conflict ?? this.conflict,
    );
  }

  /// Whether two summaries have identical metadata (ignoring the conflict
  /// flag).
  bool metadataEquals(DaySummary other) {
    return date == other.date &&
        receiptCount == other.receiptCount &&
        const MapEquality<String, double>()
            .equals(totalsByCurrency, other.totalsByCurrency);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! DaySummary) return false;
    return other.date == date &&
        other.receiptCount == receiptCount &&
        const MapEquality<String, double>()
            .equals(other.totalsByCurrency, totalsByCurrency) &&
        other.lastUpdated == lastUpdated &&
        other.conflict == conflict;
  }

  @override
  int get hashCode => Object.hash(
        date,
        receiptCount,
        const MapEquality<String, double>().hash(totalsByCurrency),
        lastUpdated,
        conflict,
      );

  @override
  String toString() =>
      'DaySummary(date: $date, count: $receiptCount, conflict: $conflict)';
}

// ---------------------------------------------------------------------------
// MonthIndex
// ---------------------------------------------------------------------------

/// Represents the `month_index.json` stored in a month folder.
class MonthIndex {
  /// The month this index covers, in `YYYY-MM` format.
  final String month;

  /// Schema version for forward-compatible migrations.
  final int schemaVersion;

  /// ISO-8601 UTC timestamp of the last modification to this index.
  final String lastUpdated;

  /// Per-day summaries/pointers.
  final List<DaySummary> days;

  /// Optional month-level totals aggregated across all days, keyed by
  /// currency code. Computed on write and used for fast dashboard rendering.
  /// May be `null` if not yet calculated.
  final Map<String, double>? totals;

  const MonthIndex({
    required this.month,
    this.schemaVersion = 1,
    required this.lastUpdated,
    required this.days,
    this.totals,
  });

  factory MonthIndex.fromJson(Map<String, dynamic> json) {
    final rawDays = json['days'] as List<dynamic>? ?? <dynamic>[];
    final rawTotals = json['totals'] as Map<String, dynamic>?;

    return MonthIndex(
      month: json['month'] as String,
      schemaVersion: json['schema_version'] as int? ?? 1,
      lastUpdated: json['last_updated'] as String,
      days: rawDays
          .map((e) => DaySummary.fromJson(e as Map<String, dynamic>))
          .toList(),
      totals: rawTotals
          ?.map((key, value) => MapEntry(key, (value as num).toDouble())),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'month': month,
      'schema_version': schemaVersion,
      'last_updated': lastUpdated,
      'days': days.map((d) => d.toJson()).toList(),
      if (totals != null) 'totals': totals,
    };
  }

  MonthIndex copyWith({
    String? month,
    int? schemaVersion,
    String? lastUpdated,
    List<DaySummary>? days,
    Map<String, double>? Function()? totals,
  }) {
    return MonthIndex(
      month: month ?? this.month,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      days: days ?? this.days,
      totals: totals != null ? totals() : this.totals,
    );
  }

  /// Recomputes the [totals] map from the current [days] list.
  MonthIndex recomputeTotals() {
    final combined = <String, double>{};
    for (final day in days) {
      day.totalsByCurrency.forEach((currency, amount) {
        combined[currency] = (combined[currency] ?? 0.0) + amount;
      });
    }
    return copyWith(totals: () => combined);
  }

  // -------------------------------------------------------------------------
  // Merge logic
  // -------------------------------------------------------------------------

  /// Merges [remote] into **this** (local) month index and returns a new
  /// [MonthIndex].
  ///
  /// Merge rules:
  /// 1. Day summaries are keyed by [DaySummary.date].
  /// 2. Summaries that exist only in remote are **added**.
  /// 3. Summaries that exist only in local are **kept** (never auto-deleted).
  /// 4. When both sides have the same date:
  ///    a. If metadata is identical the local copy is kept.
  ///    b. Otherwise the entry with the later `lastUpdated` wins and its
  ///       `conflict` flag is set to `true`.
  /// 5. The resulting totals are recomputed from the merged day list.
  MonthIndex merge(MonthIndex remote) {
    final localMap = <String, DaySummary>{
      for (final d in days) d.date: d,
    };
    final remoteMap = <String, DaySummary>{
      for (final d in remote.days) d.date: d,
    };

    final allDates = <String>{...localMap.keys, ...remoteMap.keys};
    final merged = <DaySummary>[];

    for (final date in allDates) {
      final local = localMap[date];
      final remoteDay = remoteMap[date];

      if (local != null && remoteDay == null) {
        merged.add(local);
      } else if (local == null && remoteDay != null) {
        merged.add(remoteDay);
      } else if (local != null && remoteDay != null) {
        if (local.metadataEquals(remoteDay)) {
          merged.add(local);
        } else {
          final localTime = DateTime.parse(local.lastUpdated);
          final remoteTime = DateTime.parse(remoteDay.lastUpdated);
          final winner =
              remoteTime.isAfter(localTime) ? remoteDay : local;
          merged.add(winner.copyWith(conflict: true));
        }
      }
    }

    // Sort by date for deterministic ordering.
    merged.sort((a, b) => a.date.compareTo(b.date));

    final localTime = DateTime.parse(lastUpdated);
    final remoteTime = DateTime.parse(remote.lastUpdated);
    final latestTimestamp =
        remoteTime.isAfter(localTime) ? remote.lastUpdated : lastUpdated;

    return MonthIndex(
      month: month,
      schemaVersion: schemaVersion > remote.schemaVersion
          ? schemaVersion
          : remote.schemaVersion,
      lastUpdated: latestTimestamp,
      days: merged,
    ).recomputeTotals();
  }

  // -------------------------------------------------------------------------
  // Equality
  // -------------------------------------------------------------------------

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! MonthIndex) return false;
    if (other.month != month ||
        other.schemaVersion != schemaVersion ||
        other.lastUpdated != lastUpdated ||
        other.days.length != days.length) {
      return false;
    }
    if (!const ListEquality<DaySummary>().equals(other.days, days)) {
      return false;
    }
    if (totals == null && other.totals == null) return true;
    if (totals == null || other.totals == null) return false;
    return const MapEquality<String, double>().equals(other.totals!, totals!);
  }

  @override
  int get hashCode => Object.hash(
        month,
        schemaVersion,
        lastUpdated,
        const ListEquality<DaySummary>().hash(days),
        totals == null
            ? null
            : const MapEquality<String, double>().hash(totals!),
      );

  @override
  String toString() =>
      'MonthIndex(month: $month, days: ${days.length}, '
      'lastUpdated: $lastUpdated)';
}
