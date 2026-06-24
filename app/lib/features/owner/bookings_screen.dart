import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../lobby/book_slot_sheet.dart' show BookSlotSheet;
import '../lobby/booking_repository.dart';
import 'court_repository.dart';

const _kHourHeight = 72.0;
const _kStartHour = 6;
const _kEndHour = 22;
const _kLabelWidth = 52.0;

class BookingsScreen extends ConsumerStatefulWidget {
  const BookingsScreen({super.key});

  @override
  ConsumerState<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends ConsumerState<BookingsScreen> {
  late DateTime _selectedDay;
  String? _selectedSlotId;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static const _weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDay = DateTime(now.year, now.month, now.day);
  }

  String _formatDate(DateTime d) =>
      '${_weekdays[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}';

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  void _onBookingTap(BuildContext context, CustomBooking booking,
      CourtBookingQuery query) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _BookingDetailSheet(booking: booking),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final courtAsync = ref.watch(ownerCourtProvider);

    return courtAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (court) {
        if (court == null) {
          return const Center(child: Text('No court found.'));
        }

        final slotsAsync = ref.watch(courtSlotsProvider(court.id));
        final slots = slotsAsync.valueOrNull ?? [];
        final effectiveSlotId =
            _selectedSlotId ?? (slots.isNotEmpty ? slots.first.id : null);

        final query = effectiveSlotId != null
            ? CourtBookingQuery(slotId: effectiveSlotId, date: _selectedDay)
            : null;
        final bookingsAsync =
            query != null ? ref.watch(courtBookingsProvider(query)) : null;
        final bookings = bookingsAsync?.valueOrNull ?? [];
        final isLoading = bookingsAsync?.isLoading ?? false;

        return Column(
          children: [
            // ── Date navigator ──
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(PhosphorIconsFill.caretLeft),
                    onPressed: () => setState(() => _selectedDay =
                        _selectedDay.subtract(const Duration(days: 1))),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          _formatDate(_selectedDay),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (_isToday(_selectedDay))
                          Text(
                            'Today',
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: scheme.primary),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(PhosphorIconsFill.caretRight),
                    onPressed: () => setState(() => _selectedDay =
                        _selectedDay.add(const Duration(days: 1))),
                  ),
                ],
              ),
            ),

            // ── Slot selector (if multiple courts) ──
            if (slots.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: slots.map((slot) {
                      final selected = slot.id == effectiveSlotId;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(slot.label),
                          selected: selected,
                          onSelected: (_) =>
                              setState(() => _selectedSlotId = slot.id),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),

            const SizedBox(height: 12),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  if (isLoading)
                    const SizedBox(
                      height: 12,
                      width: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    )
                  else
                    Text(
                      bookings.isEmpty
                          ? 'No bookings'
                          : '${bookings.length} booking${bookings.length == 1 ? '' : 's'} — tap to manage',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // ── Timeline ──
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).padding.bottom + 92),
                child: _DayTimeline(
                  bookings: bookings,
                  selectedDay: _selectedDay,
                  court: court,
                  onBookingTap: query != null
                      ? (b) => _onBookingTap(context, b, query)
                      : null,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Timeline ──────────────────────────────────────────────────────────────────

class _DayTimeline extends StatelessWidget {
  const _DayTimeline({
    required this.bookings,
    required this.selectedDay,
    required this.court,
    this.onBookingTap,
  });

  final List<CustomBooking> bookings;
  final DateTime selectedDay;
  final Court court;
  final void Function(CustomBooking)? onBookingTap;

  static const _hours = _kEndHour - _kStartHour;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final totalHeight = _hours * _kHourHeight;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        height: totalHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hour labels
            SizedBox(
              width: _kLabelWidth,
              child: Stack(
                clipBehavior: Clip.none,
                children: List.generate(_hours + 1, (i) {
                  final hour = _kStartHour + i;
                  return Positioned(
                    top: i * _kHourHeight - 9,
                    left: 0,
                    right: 4,
                    child: Text(
                      _hourLabel(hour),
                      textAlign: TextAlign.right,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                  );
                }),
              ),
            ),

            // Grid + bookings
            Expanded(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Grid lines — stronger on even hours
                  ...List.generate(
                    _hours + 1,
                    (i) => Positioned(
                      top: i * _kHourHeight,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 1,
                        color: scheme.outlineVariant
                            .withValues(alpha: i % 2 == 0 ? 0.6 : 0.25),
                      ),
                    ),
                  ),

                  // Current-time indicator
                  _CurrentTimeLine(
                      selectedDay: selectedDay, color: scheme.error),

                  // Booking blocks
                  ...bookings.map(
                    (b) => _bookingBlock(b, scheme, theme, onBookingTap),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bookingBlock(
    CustomBooking b,
    ColorScheme scheme,
    ThemeData theme,
    void Function(CustomBooking)? onTap,
  ) {
    final startMins = b.startsAt.hour * 60 + b.startsAt.minute;
    final endMins = b.endsAt.hour * 60 + b.endsAt.minute;
    final top = (startMins - _kStartHour * 60) / 60 * _kHourHeight;
    final height = (endMins - startMins) / 60 * _kHourHeight;

    if (top + height <= 0 || top >= _hours * _kHourHeight) {
      return const SizedBox.shrink();
    }

    final durationMins = endMins - startMins;
    final durationH = durationMins ~/ 60;
    final durationM = durationMins % 60;
    final durationLabel =
        durationM == 0 ? '${durationH}h' : '${durationH}h ${durationM}m';

    final feeLabel = b.amountCents != null && b.currency != null
        ? ' · ${BookSlotSheet.feeLabel(b.amountCents!, b.currency!)}'
        : '';

    return Positioned(
      top: top + 1,
      left: 2,
      right: 2,
      height: height - 2,
      child: GestureDetector(
        onTap: onTap != null ? () => onTap(b) : null,
        child: Container(
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: scheme.primary.withValues(alpha: 0.4), width: 1),
          ),
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${_timeStr(b.startsAt)} – ${_timeStr(b.endsAt)}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (height > 36)
                Text(
                  '$durationLabel$feeLabel',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.75),
                    fontSize: 10,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _hourLabel(int hour) {
    if (hour == 0) return '12 AM';
    if (hour < 12) return '$hour AM';
    if (hour == 12) return '12 PM';
    return '${hour - 12} PM';
  }

  static String _timeStr(DateTime dt) {
    final h = dt.hour;
    final m = dt.minute;
    final mStr = m == 0 ? '' : ':${m.toString().padLeft(2, '0')}';
    if (h == 0) return '12${mStr}AM';
    if (h < 12) return '$h${mStr}AM';
    if (h == 12) return '12${mStr}PM';
    return '${h - 12}${mStr}PM';
  }
}

class _CurrentTimeLine extends StatelessWidget {
  const _CurrentTimeLine({required this.selectedDay, required this.color});

  final DateTime selectedDay;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isToday = selectedDay.year == now.year &&
        selectedDay.month == now.month &&
        selectedDay.day == now.day;
    if (!isToday) return const SizedBox.shrink();

    final nowMins = now.hour * 60 + now.minute;
    if (nowMins < _kStartHour * 60 || nowMins > _kEndHour * 60) {
      return const SizedBox.shrink();
    }

    final top = (nowMins - _kStartHour * 60) / 60 * _kHourHeight;
    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Expanded(child: Container(height: 1.5, color: color)),
        ],
      ),
    );
  }
}

// ── Booking detail bottom sheet (read-only; cancellation is in Profile) ──────

class _BookingDetailSheet extends StatelessWidget {
  const _BookingDetailSheet({required this.booking});

  final CustomBooking booking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final b = booking;

    final startMins = b.startsAt.hour * 60 + b.startsAt.minute;
    final endMins = b.endsAt.hour * 60 + b.endsAt.minute;
    final durationMins = endMins - startMins;
    final durationH = durationMins ~/ 60;
    final durationM = durationMins % 60;
    final durationLabel =
        durationM == 0 ? '${durationH}h' : '${durationH}h ${durationM}m';

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Booking details',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),

            _DetailRow(
              icon: PhosphorIconsFill.clock,
              label: '${BookSlotSheet.timeLabel(startMins)} – '
                  '${BookSlotSheet.timeLabel(endMins)}',
              sublabel: durationLabel,
              scheme: scheme,
              theme: theme,
            ),

            if (b.amountCents != null && b.currency != null) ...[
              const SizedBox(height: 12),
              _DetailRow(
                icon: PhosphorIconsFill.currencyDollar,
                label: BookSlotSheet.feeLabel(b.amountCents!, b.currency!),
                sublabel: 'Amount paid',
                scheme: scheme,
                theme: theme,
              ),
            ],

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.scheme,
    required this.theme,
  });

  final IconData icon;
  final String label;
  final String sublabel;
  final ColorScheme scheme;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            Text(sublabel,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
      ],
    );
  }
}
