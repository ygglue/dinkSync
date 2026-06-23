import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/court.dart';
import 'booking_repository.dart';

class BookSlotSheet extends ConsumerStatefulWidget {
  const BookSlotSheet({super.key, required this.court});
  final Court court;

  static Future<String?> show(BuildContext context, Court court) {
    return showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => BookSlotSheet(court: court),
    );
  }

  static String timeLabel(int mins) {
    final h = mins ~/ 60;
    final m = mins % 60;
    final mStr = m == 0 ? '00' : '30';
    if (h == 0) return '12:$mStr AM';
    if (h < 12) return '$h:$mStr AM';
    if (h == 12) return '12:$mStr PM';
    return '${h - 12}:$mStr PM';
  }

  static String feeLabel(int totalCents, String currency) {
    final symbol = switch (currency.toUpperCase()) {
      'PHP' => '₱',
      'USD' => '\$',
      'EUR' => '€',
      'GBP' => '£',
      _ => '$currency ',
    };
    final whole = totalCents ~/ 100;
    final frac = totalCents % 100;
    final fracStr = frac == 0 ? '' : '.${frac.toString().padLeft(2, '0')}';
    final wholeStr = whole.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
    return '$symbol$wholeStr$fracStr';
  }

  @override
  ConsumerState<BookSlotSheet> createState() => _BookSlotSheetState();
}

class _BookSlotSheetState extends ConsumerState<BookSlotSheet> {
  late DateTime _selectedDay;
  String? _selectedSlotId;
  int _startMins = 480;  // default 8:00 AM; preserved across day changes
  int _durationHours = 1;
  bool _booking = false;
  String? _error;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static final _allStartSlots = List.generate(31, (i) => 360 + i * 30);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDay = DateTime(now.year, now.month, now.day);
  }

  String _dayLabel(DateTime d) => _weekdays[d.weekday - 1];

  static bool _overlapsAny(int s, int e, List<CustomBooking> bookings) =>
      bookings.any((b) {
        final bs = b.startsAt.hour * 60 + b.startsAt.minute;
        final be = b.endsAt.hour * 60 + b.endsAt.minute;
        return bs < e && be > s;
      });

  List<int> _availableStarts(List<CustomBooking> bookings) => _allStartSlots
      .where((s) => !_overlapsAny(s, s + 60, bookings))
      .toList();

  List<int> _availableDurations(List<CustomBooking> bookings) {
    final maxH = (1320 - _startMins) ~/ 60;
    return [1, 2, 3, 4]
        .where((d) =>
            d <= maxH &&
            !_overlapsAny(_startMins, _startMins + d * 60, bookings))
        .toList();
  }

  Future<void> _pickStartTime(
      BuildContext context, List<int> available, List<CustomBooking> bookings) async {
    if (available.isEmpty) return;
    final initialIndex = available.contains(_startMins)
        ? available.indexOf(_startMins)
        : 0;
    final picked = await showModalBottomSheet<int>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _TimePickerSheet(options: available, initialIndex: initialIndex),
    );
    if (picked != null && mounted) {
      setState(() {
        _startMins = picked;
        final valid = _availableDurations(bookings);
        if (!valid.contains(_durationHours)) {
          _durationHours = valid.isNotEmpty ? valid.first : 1;
        }
        _error = null;
      });
    }
  }

  Future<void> _confirm(String slotId) async {
    setState(() { _booking = true; _error = null; });
    try {
      final endMins = _startMins + _durationHours * 60;
      final starts = DateTime(_selectedDay.year, _selectedDay.month,
          _selectedDay.day, _startMins ~/ 60, _startMins % 60);
      final ends = DateTime(_selectedDay.year, _selectedDay.month,
          _selectedDay.day, endMins ~/ 60, endMins % 60);
      await ref.read(bookingRepositoryProvider).bookSlot(
            slotId: slotId, startsAt: starts, endsAt: ends);
      if (mounted) {
        final slots = ref.read(courtSlotsProvider(widget.court.id)).valueOrNull;
        final label = slots?.any((s) => s.id == slotId) == true
            ? slots!.firstWhere((s) => s.id == slotId).label
            : 'the court';
        Navigator.of(context).pop(label);
      }
    } catch (e) {
      final msg = e.toString();
      if (mounted) {
        setState(() {
          _error = msg.contains('slot_not_available')
              ? 'That time is no longer available. Choose another.'
              : 'Booking failed. Please try again.';
          if (msg.contains('slot_not_available')) ref.invalidate(courtBookingsProvider);
        });
      }
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final slotsAsync = ref.watch(courtSlotsProvider(widget.court.id));
    final slots = slotsAsync.valueOrNull ?? [];
    final effectiveSlotId =
        _selectedSlotId ?? (slots.isNotEmpty ? slots.first.id : null);

    final bookings = (effectiveSlotId != null
            ? ref.watch(courtBookingsProvider(
                CourtBookingQuery(slotId: effectiveSlotId, date: _selectedDay)))
            : null)
        ?.valueOrNull ??
        [];

    final availableStarts = _availableStarts(bookings);
    final availableDurations = _availableDurations(bookings);
    final startAvailable = availableStarts.contains(_startMins);
    final endMins = _startMins + _durationHours * 60;

    final canConfirm = startAvailable &&
        availableDurations.contains(_durationHours) &&
        effectiveSlotId != null &&
        !_booking;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Book a slot',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 24),

            // ── SELECT DATE ──
            _SectionLabel('SELECT DATE', theme),
            const SizedBox(height: 8),
            SizedBox(
              height: 68,
              child: Row(
                children: List.generate(7, (i) {
                  final day = DateTime.now().add(Duration(days: i));
                  final dayDate = DateTime(day.year, day.month, day.day);
                  final selected = dayDate == _selectedDay;
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _selectedDay = dayDate;
                          // Keep _startMins — user's pick is preserved across days.
                          _error = null;
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          decoration: BoxDecoration(
                            color: selected
                                ? scheme.primary
                                : scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(_dayLabel(day),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: selected
                                        ? scheme.onPrimary.withValues(alpha: 0.8)
                                        : scheme.onSurfaceVariant,
                                  )),
                              const SizedBox(height: 2),
                              Text('${day.day}',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: selected
                                        ? scheme.onPrimary
                                        : scheme.onSurface,
                                  )),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),

            // ── SLOT TABS ──
            if (slots.length > 1) ...[
              const SizedBox(height: 16),
              _SectionLabel('SELECT COURT', theme),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
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
                          _error = null;
                        }),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],

            const SizedBox(height: 20),

            // ── START TIME ──
            _SectionLabel('START TIME', theme),
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: availableStarts.isNotEmpty
                  ? () => _pickStartTime(context, availableStarts, bookings)
                  : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        availableStarts.isEmpty
                            ? 'No times available'
                            : startAvailable
                                ? BookSlotSheet.timeLabel(_startMins)
                                : 'Select a time',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: startAvailable
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Icon(Icons.keyboard_arrow_down_rounded,
                        color: scheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── DURATION ──
            _SectionLabel('DURATION', theme),
            const SizedBox(height: 8),
            Row(
              children: [1, 2, 3, 4].map((d) {
                final available = availableDurations.contains(d);
                final selected = _durationHours == d && startAvailable;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: available
                        ? () => setState(() { _durationHours = d; _error = null; })
                        : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: selected
                            ? scheme.primary
                            : scheme.surfaceContainerHighest
                                .withValues(alpha: available ? 1.0 : 0.4),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${d}h',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? scheme.onPrimary
                              : scheme.onSurface
                                  .withValues(alpha: available ? 1.0 : 0.3),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 10),
            Text(
              'Ends at ${BookSlotSheet.timeLabel(endMins)}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.error_outline, size: 14, color: scheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(_error!,
                        style: TextStyle(color: scheme.error, fontSize: 13)),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 20),
            FilledButton(
              onPressed: canConfirm ? () => _confirm(effectiveSlotId) : null,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              child: _booking
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Confirm slot'),
                        if (widget.court.customFeeCents != null) ...[
                          const SizedBox(width: 8),
                          const Text('·'),
                          const SizedBox(width: 8),
                          Text(BookSlotSheet.feeLabel(
                            widget.court.customFeeCents! * _durationHours,
                            widget.court.currency,
                          )),
                        ],
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward, size: 18),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimePickerSheet extends StatefulWidget {
  const _TimePickerSheet({required this.options, required this.initialIndex});
  final List<int> options;
  final int initialIndex;

  @override
  State<_TimePickerSheet> createState() => _TimePickerSheetState();
}

class _TimePickerSheetState extends State<_TimePickerSheet> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex.clamp(0, widget.options.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
            child: Row(
              children: [
                Text('Select start time',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).pop(widget.options[_selectedIndex]),
                  child: Text('Done',
                      style: TextStyle(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 16)),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 200,
            child: CupertinoPicker(
              itemExtent: 48,
              scrollController:
                  FixedExtentScrollController(initialItem: _selectedIndex),
              onSelectedItemChanged: (i) => setState(() => _selectedIndex = i),
              children: widget.options
                  .map((m) => Center(
                        child: Text(BookSlotSheet.timeLabel(m),
                            style: TextStyle(
                                color: scheme.onSurface, fontSize: 20)),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, this.theme);
  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        letterSpacing: 1.0,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
