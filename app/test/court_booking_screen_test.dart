import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dinksync/data/court.dart';
import 'package:dinksync/features/lobby/booking_repository.dart';
import 'package:dinksync/features/lobby/book_slot_sheet.dart';

const _court = Court(
  id: 'c1',
  name: 'Cebu Dinks',
  status: 'active',
  entryFeeCents: 15000,
  currency: 'PHP',
  numCourts: 1,
  customFeeCents: 50000,
);

const _slot = CourtSlot(id: 'slot-1', label: 'Court 1');

class _FakeBookingRepo implements BookingRepository {
  _FakeBookingRepo({this.slots = const [], this.bookings = const []});
  final List<CourtSlot> slots;
  final List<CustomBooking> bookings;

  @override
  Future<List<CourtSlot>> courtSlots(String courtId) async => slots;

  @override
  Future<List<CustomBooking>> bookingsForSlot(CourtBookingQuery query) async =>
      bookings;

  @override
  Future<void> bookSlot({
    required String slotId,
    required DateTime startsAt,
    required DateTime endsAt,
  }) async {}

  @override
  Future<void> cancelBooking(String bookingId) async {}

  @override
  Future<List<CustomBooking>> myUpcomingBookings() async => [];
}

Widget _host({List<CustomBooking> bookings = const []}) => ProviderScope(
      overrides: [
        bookingRepositoryProvider.overrideWithValue(
          _FakeBookingRepo(slots: const [_slot], bookings: bookings),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(body: BookSlotSheet(court: _court)),
      ),
    );

void main() {
  testWidgets('date strip shows today', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final now = DateTime.now();
    expect(find.text(weekdays[now.weekday - 1]), findsWidgets);
    expect(find.text('${now.day}'), findsWidgets);
  });

  testWidgets('shows section labels', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.text('SELECT DATE'), findsOneWidget);
    expect(find.text('START TIME'), findsOneWidget);
    expect(find.text('DURATION'), findsOneWidget);
  });

  testWidgets('shows default start time and duration chips', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    // Default start is 8:00 AM.
    expect(find.text('8:00 AM'), findsWidgets);
    // Duration chip row should be visible.
    expect(find.text('1h'), findsOneWidget);
    expect(find.text('2h'), findsOneWidget);
  });

  testWidgets('Confirm slot button is enabled with valid selection',
      (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    final btn = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(btn.onPressed, isNotNull);
  });

  testWidgets('Confirm slot button is disabled when all times are booked',
      (tester) async {
    final now = DateTime.now();
    // Block the entire bookable window (6:00 AM to 10:00 PM).
    final booking = CustomBooking(
      startsAt: DateTime(now.year, now.month, now.day, 6, 0),
      endsAt: DateTime(now.year, now.month, now.day, 22, 0),
    );
    await tester.pumpWidget(_host(bookings: [booking]));
    await tester.pumpAndSettle();

    final btn = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(btn.onPressed, isNull);
  });

  testWidgets('tapping a different date chip resets start time', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    final tomorrow = DateTime.now().add(const Duration(days: 1));
    await tester.tap(find.text('${tomorrow.day}').first);
    await tester.pumpAndSettle();

    // After date change, auto-selection should re-pick a time.
    final btn = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(btn.onPressed, isNotNull);
  });

  test('timeLabel formats times correctly', () {
    expect(BookSlotSheet.timeLabel(0), '12:00 AM');
    expect(BookSlotSheet.timeLabel(480), '8:00 AM');
    expect(BookSlotSheet.timeLabel(510), '8:30 AM');
    expect(BookSlotSheet.timeLabel(720), '12:00 PM');
    expect(BookSlotSheet.timeLabel(750), '12:30 PM');
    expect(BookSlotSheet.timeLabel(780), '1:00 PM');
    expect(BookSlotSheet.timeLabel(1260), '9:00 PM');
  });
}
