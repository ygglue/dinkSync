import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../app/theme.dart';
import '../lobby/book_slot_sheet.dart' show BookSlotSheet;
import '../lobby/booking_repository.dart';

class ScheduleScreen extends ConsumerWidget {
  const ScheduleScreen({super.key});

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String _dateLabel(DateTime d) =>
      '${_weekdays[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}';

  Future<void> _cancel(
    BuildContext context,
    WidgetRef ref,
    CustomBooking booking,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel booking?'),
        content: const Text('This will free the slot and cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Cancel booking',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(bookingRepositoryProvider).cancelBooking(booking.id!);
      ref.invalidate(myBookingsProvider);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not cancel booking. Please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bookingsAsync = ref.watch(myBookingsProvider);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          'Schedule',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: scheme.primary,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myBookingsProvider),
        child: bookingsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Text('$e', style: TextStyle(color: scheme.error)),
          ),
          data: (bookings) {
            if (bookings.isEmpty) {
              return LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SizedBox(
                    height: constraints.maxHeight,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(PhosphorIconsFill.calendarBlank,
                              size: 56,
                              color: scheme.onSurfaceVariant
                                  .withValues(alpha: 0.4)),
                          const SizedBox(height: 16),
                          Text(
                            'No upcoming bookings',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }

            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                MediaQuery.of(context).padding.bottom + 92,
              ),
              itemCount: bookings.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final b = bookings[index];
              final startMins = b.startsAt.hour * 60 + b.startsAt.minute;
              final endMins = b.endsAt.hour * 60 + b.endsAt.minute;
              final durationH = (endMins - startMins) ~/ 60;
              final fee = b.amountCents != null && b.currency != null
                  ? BookSlotSheet.feeLabel(b.amountCents!, b.currency!)
                  : null;

              return _BookingCard(
                booking: b,
                dateLabel: _dateLabel(b.startsAt),
                startMins: startMins,
                endMins: endMins,
                durationH: durationH,
                fee: fee,
                onCancel: () => _cancel(context, ref, b),
              );
            },
          );
        },
      ),
      ),
    );
  }
}

// ── Booking card ──────────────────────────────────────────────────────────────

class _BookingCard extends StatelessWidget {
  const _BookingCard({
    required this.booking,
    required this.dateLabel,
    required this.startMins,
    required this.endMins,
    required this.durationH,
    this.fee,
    required this.onCancel,
  });

  final CustomBooking booking;
  final String dateLabel;
  final int startMins;
  final int endMins;
  final int durationH;
  final String? fee;
  final VoidCallback onCancel;

  static BoxDecoration _pillDecoration(ColorScheme scheme) => BoxDecoration(
        color: const Color(0xFF232821),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.primary, width: 1),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final b = booking;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(kRadius),
      ),
      child: Stack(
        children: [
          // ── Radial glow from upper-left ──
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topLeft,
                  radius: 1.4,
                  colors: [
                    scheme.primary.withValues(alpha: 0.22),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // ── Card content ──
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header: name/slot + cancel pill ──
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (b.courtName != null)
                            Text(
                              b.courtName!,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          if (b.slotLabel != null)
                            Text(
                              b.slotLabel!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: onCancel,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: scheme.error.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Cancel',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                Divider(
                    height: 1,
                    thickness: 1,
                    color: scheme.outlineVariant.withValues(alpha: 0.5)),
                const SizedBox(height: 12),

                // ── Date pill ──
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: _pillDecoration(scheme),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(PhosphorIconsFill.calendarBlank,
                              size: 13, color: scheme.primary),
                          const SizedBox(width: 6),
                          Text(
                            dateLabel,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // ── Inner time card with gradient ──
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.bottomLeft,
                      end: Alignment.topRight,
                      colors: [Color(0xFFCFE8C4), Color(0xFFF8F3EA)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: _TimelineRow(
                    startLabel: BookSlotSheet.timeLabel(startMins),
                    endLabel: BookSlotSheet.timeLabel(endMins),
                  ),
                ),

                const SizedBox(height: 12),

                // ── Footer: duration pill + fee pill ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: _pillDecoration(scheme),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(PhosphorIconsFill.clock,
                              size: 15, color: scheme.primary),
                          const SizedBox(width: 6),
                          Text(
                            '${durationH}h',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (fee != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: _pillDecoration(scheme),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(PhosphorIconsFill.receipt,
                                size: 15, color: scheme.primary),
                            const SizedBox(width: 6),
                            Text(
                              fee!,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.startLabel, required this.endLabel});

  final String startLabel;
  final String endLabel;

  static String _time(String label) => label.split(' ').first;
  static String _ampm(String label) {
    final parts = label.split(' ');
    return parts.length > 1 ? parts.last : '';
  }

  Widget _timeWidget(String label) => Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            _time(label),
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(width: 2),
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              _ampm(label),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A),
              ),
            ),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF2E7D32);
    const dotSize = 7.0;

    return Row(
      children: [
        _timeWidget(startLabel),
        const SizedBox(width: 10),
        Expanded(
          child: Row(
            children: [
              Container(
                width: dotSize,
                height: dotSize,
                decoration: const BoxDecoration(
                    color: green, shape: BoxShape.circle),
              ),
              Expanded(child: Container(height: 1.5, color: green)),
              Container(
                width: dotSize,
                height: dotSize,
                decoration: const BoxDecoration(
                    color: green, shape: BoxShape.circle),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _timeWidget(endLabel),
      ],
    );
  }
}
