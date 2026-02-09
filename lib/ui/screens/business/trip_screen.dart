// Kira - The Receipt Saver
// Trip management screen: create/view trips within a workspace, trip name,
// date range, associated receipts, and trip totals.

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../../theme/kira_icons.dart';
import '../../theme/kira_theme.dart';

// ---------------------------------------------------------------------------
// In-memory trip model (backed by SQLite trips table)
// ---------------------------------------------------------------------------

class _Trip {
  final String tripId;
  final String workspaceId;
  final String name;
  final String? description;
  final DateTime? startDate;
  final DateTime? endDate;
  final String createdBy;
  final double totalAmount;
  final int receiptCount;

  _Trip({
    required this.tripId,
    required this.workspaceId,
    required this.name,
    this.description,
    this.startDate,
    this.endDate,
    required this.createdBy,
    this.totalAmount = 0,
    this.receiptCount = 0,
  });
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class TripScreen extends StatefulWidget {
  final String? workspaceId;
  final String? workspaceName;

  const TripScreen({
    super.key,
    this.workspaceId,
    this.workspaceName,
  });

  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> {
  List<_Trip> _trips = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  Future<void> _loadTrips() async {
    setState(() => _loading = true);
    // TODO: Load from DAO for the given workspace.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    setState(() => _loading = false);
  }

  String _formatCurrency(double amount) {
    return NumberFormat.currency(symbol: r'CA$', decimalDigits: 2)
        .format(amount);
  }

  String _formatDateRange(_Trip trip) {
    if (trip.startDate == null) return '--';
    final start = DateFormat.yMMMd().format(trip.startDate!);
    if (trip.endDate == null) return start;
    final end = DateFormat.yMMMd().format(trip.endDate!);
    return '$start - $end';
  }

  Future<void> _createTrip(AppLocalizations l10n) async {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    DateTime? startDate;
    DateTime? endDate;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(l10n.createTrip),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: l10n.tripName,
                        hintText: l10n.tripName,
                      ),
                    ),
                    const SizedBox(height: KiraDimens.spacingMd),
                    TextField(
                      controller: descController,
                      decoration: InputDecoration(
                        labelText: l10n.notes,
                        hintText: l10n.notes,
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: KiraDimens.spacingMd),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: ctx,
                                initialDate: DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate:
                                    DateTime.now().add(const Duration(days: 365)),
                              );
                              if (picked != null) {
                                setDialogState(() => startDate = picked);
                              }
                            },
                            icon: const Icon(
                              KiraIcons.calendar,
                              size: KiraDimens.iconSm,
                            ),
                            label: Text(
                              startDate != null
                                  ? DateFormat.yMMMd().format(startDate!)
                                  : l10n.receiptDate,
                              style:
                                  Theme.of(ctx).textTheme.bodySmall,
                            ),
                          ),
                        ),
                        const SizedBox(width: KiraDimens.spacingSm),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: ctx,
                                initialDate:
                                    startDate ?? DateTime.now(),
                                firstDate: startDate ?? DateTime(2020),
                                lastDate:
                                    DateTime.now().add(const Duration(days: 365)),
                              );
                              if (picked != null) {
                                setDialogState(() => endDate = picked);
                              }
                            },
                            icon: const Icon(
                              KiraIcons.dateRange,
                              size: KiraDimens.iconSm,
                            ),
                            label: Text(
                              endDate != null
                                  ? DateFormat.yMMMd().format(endDate!)
                                  : l10n.receiptDate,
                              style:
                                  Theme.of(ctx).textTheme.bodySmall,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(l10n.cancel),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(l10n.save),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true && nameController.text.trim().isNotEmpty) {
      final trip = _Trip(
        tripId: DateTime.now().millisecondsSinceEpoch.toString(),
        workspaceId: widget.workspaceId ?? '',
        name: nameController.text.trim(),
        description: descController.text.trim().isEmpty
            ? null
            : descController.text.trim(),
        startDate: startDate,
        endDate: endDate,
        createdBy: 'current_user',
      );
      setState(() => _trips.add(trip));
      // TODO: Persist via DAO.
    }

    nameController.dispose();
    descController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(KiraIcons.arrowBack),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: l10n.back,
        ),
        title: Text(l10n.trips),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createTrip(l10n),
        icon: const Icon(KiraIcons.add),
        label: Text(l10n.createTrip),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _trips.isEmpty
              ? _buildEmptyState(l10n, colors, text)
              : ListView.builder(
                  padding: const EdgeInsets.only(
                    bottom: KiraDimens.spacingXxxl * 2,
                    top: KiraDimens.spacingSm,
                  ),
                  itemCount: _trips.length,
                  itemBuilder: (context, index) =>
                      _buildTripCard(_trips[index], l10n),
                ),
    );
  }

  Widget _buildEmptyState(
    AppLocalizations l10n,
    ColorScheme colors,
    TextTheme text,
  ) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            KiraIcons.trip,
            size: KiraDimens.iconXl,
            color: colors.outline,
          ),
          const SizedBox(height: KiraDimens.spacingLg),
          Text(
            l10n.trips,
            style: text.titleMedium?.copyWith(color: colors.outline),
          ),
          const SizedBox(height: KiraDimens.spacingSm),
          Text(
            l10n.createTrip,
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildTripCard(_Trip trip, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: KiraDimens.spacingLg,
        vertical: KiraDimens.spacingSm,
      ),
      child: InkWell(
        onTap: () {
          // TODO: Navigate to trip detail / receipt association view.
        },
        borderRadius: BorderRadius.circular(KiraDimens.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(KiraDimens.spacingLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    KiraIcons.trip,
                    color: colors.primary,
                    size: KiraDimens.iconMd,
                  ),
                  const SizedBox(width: KiraDimens.spacingSm),
                  Expanded(
                    child: Text(
                      trip.name,
                      style: text.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(
                    KiraIcons.chevronRight,
                    size: KiraDimens.iconMd,
                  ),
                ],
              ),
              if (trip.description != null) ...[
                const SizedBox(height: KiraDimens.spacingXs),
                Text(
                  trip.description!,
                  style: text.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: KiraDimens.spacingSm),
              Row(
                children: [
                  Icon(
                    KiraIcons.dateRange,
                    size: KiraDimens.iconSm,
                    color: colors.outline,
                  ),
                  const SizedBox(width: KiraDimens.spacingXs),
                  Text(
                    _formatDateRange(trip),
                    style: text.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: KiraDimens.spacingXs),
              Row(
                children: [
                  Icon(
                    KiraIcons.receipt,
                    size: KiraDimens.iconSm,
                    color: colors.outline,
                  ),
                  const SizedBox(width: KiraDimens.spacingXs),
                  Text(
                    '${trip.receiptCount} ${l10n.receiptList}',
                    style: text.bodySmall,
                  ),
                  const Spacer(),
                  Text(
                    _formatCurrency(trip.totalAmount),
                    style: text.titleSmall?.copyWith(color: colors.primary),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
