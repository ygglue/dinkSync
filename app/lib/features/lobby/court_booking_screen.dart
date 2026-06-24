import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../data/court.dart';
import 'booking_repository.dart';

class CourtBookingScreen extends ConsumerStatefulWidget {
  const CourtBookingScreen({super.key, required this.court});
  final Court court;

  @override
  ConsumerState<CourtBookingScreen> createState() => _CourtBookingScreenState();
}

class _CourtBookingScreenState extends ConsumerState<CourtBookingScreen> {
  late DateTime _selectedDay;
  String? _selectedSlotId;
  int? _startHour;
  int? _endHour;
  bool _booking = false;
  String? _error;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDay = DateTime(now.year, now.month, now.day);
  }

  String _dayLabel(DateTime d) => '${_weekdays[d.weekday - 1]} ${d.day}';
  String _hourStr(int h) => '${h.toString().padLeft(2, '0')}:00';

  void _tapHour(int hour) {
    setState(() {
      if (_startHour == null) {
        _startHour = hour;
        _endHour = hour + 1;
      } else if (hour == _startHour) {
        _startHour = null;
        _endHour = null;
      } else if (hour < _startHour!) {
        _startHour = hour;
      } else {
        _endHour = hour + 1;
      }
    });
  }

  bool _isBooked(int hour, List<CustomBooking> bookings) {
    final blockStart = DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day, hour);
    final blockEnd   = DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day, hour + 1);
    return bookings.any((b) => b.startsAt.isBefore(blockEnd) && b.endsAt.isAfter(blockStart));
  }

  Future<void> _confirmBooking(String slotId) async {
    setState(() {
      _booking = true;
      _error = null;
    });
    try {
      final starts = DateTime(
          _selectedDay.year, _selectedDay.month, _selectedDay.day, _startHour!);
      final ends = DateTime(
          _selectedDay.year, _selectedDay.month, _selectedDay.day, _endHour!);
      await ref.read(bookingRepositoryProvider).bookSlot(
            slotId: slotId,
            startsAt: starts,
            endsAt: ends,
          );
      if (mounted) {
        // Read slot label BEFORE popping (ref may be invalid after pop)
        final slots = ref.read(courtSlotsProvider(widget.court.id)).valueOrNull;
        final label = slots != null
            ? (slots.where((s) => s.id == slotId).isNotEmpty
                ? slots.firstWhere((s) => s.id == slotId).label
                : 'your court')
            : 'your court';
        final messenger = ScaffoldMessenger.of(context);
        context.pop();
        messenger.showSnackBar(
          SnackBar(content: Text('Booked! See you on $label.')),
        );
      }
    } catch (e) {
      final msg = e.toString();
      setState(() {
        _error = msg.contains('slot_not_available')
            ? 'That time is no longer available. Please choose another slot.'
            : 'Booking failed. Please try again.';
        if (msg.contains('slot_not_available')) {
          _startHour = null;
          _endHour = null;
          ref.invalidate(courtBookingsProvider);
        }
      });
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final court = widget.court;
    final slotsAsync = ref.watch(courtSlotsProvider(court.id));

    // Auto-select first slot.
    final slots = slotsAsync.valueOrNull ?? [];
    final effectiveSlotId =
        _selectedSlotId ?? (slots.isNotEmpty ? slots.first.id : null);

    final bookingsAsync = effectiveSlotId != null
        ? ref.watch(courtBookingsProvider(
            CourtBookingQuery(slotId: effectiveSlotId, date: _selectedDay)))
        : null;
    final bookings = bookingsAsync?.valueOrNull ?? [];

    final hasSelection = _startHour != null && _endHour != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Book a Court')),
      body: Column(
        children: [
          // Day strip
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 8,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final day = DateTime.now().add(Duration(days: i));
                final dayDate = DateTime(day.year, day.month, day.day);
                final isSelected = dayDate == _selectedDay;
                return GestureDetector(
                  onTap: () => setState(() {
                    _selectedDay = dayDate;
                    _startHour = null;
                    _endHour = null;
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? scheme.primary
                          : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      _dayLabel(day),
                      style: TextStyle(
                        color:
                            isSelected ? scheme.onPrimary : scheme.onSurface,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // Slot tabs (only when >1 slot)
          if (slots.length > 1)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: slots.map((slot) {
                  final selected = slot.id == effectiveSlotId;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(slot.label),
                      selected: selected,
                      onSelected: (_) => setState(() {
                        _selectedSlotId = slot.id;
                        _startHour = null;
                        _endHour = null;
                      }),
                    ),
                  );
                }).toList(),
              ),
            ),
          // Timeline
          Expanded(
            child: effectiveSlotId == null
                ? const Center(child: Text('No slots available.'))
                : ListView.builder(
                    itemCount: 16, // hours 06–21
                    itemBuilder: (context, i) {
                      final hour = 6 + i;
                      final booked = _isBooked(hour, bookings);
                      final selected = hasSelection &&
                          hour >= _startHour! &&
                          hour < _endHour!;
                      return _HourBlock(
                        hour: hour,
                        isBooked: booked,
                        isSelected: selected,
                        onTap: booked ? null : () => _tapHour(hour),
                      );
                    },
                  ),
          ),
          // Error
          if (_error != null)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(_error!,
                  style: TextStyle(color: scheme.error),
                  textAlign: TextAlign.center),
            ),
          // Booking summary + confirm
          if (hasSelection && effectiveSlotId != null) ...[
            Container(
              width: double.infinity,
              color: scheme.surfaceContainerHighest,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                _buildSummary(slots, effectiveSlotId, court),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: FilledButton(
              onPressed:
                  (hasSelection && effectiveSlotId != null && !_booking)
                      ? () => _confirmBooking(effectiveSlotId)
                      : null,
              child: _booking
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child:
                          CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Confirm booking'),
            ),
          ),
        ],
      ),
    );
  }

  String _buildSummary(
      List<CourtSlot> slots, String slotId, Court court) {
    final slotLabel = slots.isNotEmpty &&
            slots.where((s) => s.id == slotId).isNotEmpty
        ? slots.firstWhere((s) => s.id == slotId).label
        : 'Court';
    final hours = _endHour! - _startHour!;
    final total = court.customFeeCents! * hours;
    final feeStr = formatFee(total, court.currency);
    final dayLabel = _dayLabel(_selectedDay);
    return '$slotLabel · $dayLabel · ${_hourStr(_startHour!)}–${_hourStr(_endHour!)} · $feeStr';
  }
}

class _HourBlock extends StatelessWidget {
  const _HourBlock({
    required this.hour,
    required this.isBooked,
    required this.isSelected,
    required this.onTap,
  });

  final int hour;
  final bool isBooked;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = '${hour.toString().padLeft(2, '0')}:00';

    Color bg;
    if (isSelected) {
      bg = scheme.primary.withValues(alpha: 0.15);
    } else if (isBooked) {
      bg = scheme.surfaceContainerHighest;
    } else {
      bg = scheme.surface;
    }

    return InkWell(
      onTap: onTap,
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: bg,
          border: Border(
            bottom: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.35)),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 60,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  label,
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ),
            ),
            if (isBooked)
              Text(
                'Booked',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
                ),
              ),
            if (isSelected && !isBooked)
              Icon(PhosphorIconsFill.checkCircle,
                  size: 16, color: scheme.primary.withValues(alpha: 0.7)),
          ],
        ),
      ),
    );
  }
}
