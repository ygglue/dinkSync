import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dinksync/data/court.dart';
import 'package:dinksync/features/lobby/booking_repository.dart';
import 'package:dinksync/features/lobby/court_booking_screen.dart';

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
}

Widget _host({List<CustomBooking> bookings = const []}) => ProviderScope(
      overrides: [
        bookingRepositoryProvider.overrideWithValue(
          _FakeBookingRepo(slots: const [_slot], bookings: bookings),
        ),
      ],
      child: const MaterialApp(
        home: CourtBookingScreen(court: _court),
      ),
    );

void main() {
  testWidgets('day strip shows today label', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final now = DateTime.now();
    final todayLabel = '${weekdays[now.weekday - 1]} ${now.day}';
    expect(find.text(todayLabel), findsOneWidget);
  });

  testWidgets('Confirm booking button is disabled with no selection',
      (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    final btn = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(btn.onPressed, isNull);
  });

  testWidgets('tapping an available block selects start + end',
      (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('08:00'));
    await tester.pump();

    expect(find.textContaining('08:00–09:00'), findsOneWidget);
  });

  testWidgets('tapping second block extends range', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('08:00'));
    await tester.pump();
    await tester.tap(find.text('10:00'));
    await tester.pump();

    expect(find.textContaining('08:00–11:00'), findsOneWidget);
  });

  testWidgets('summary shows fee for selected range', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('08:00'));
    await tester.pump();
    await tester.tap(find.text('10:00'));
    await tester.pump();

    // 3 hours × ₱500 = ₱1500
    expect(find.textContaining('₱1500'), findsOneWidget);
  });

  testWidgets('booked block shows Booked label', (tester) async {
    final now = DateTime.now();
    final booking = CustomBooking(
      startsAt: DateTime(now.year, now.month, now.day, 10),
      endsAt: DateTime(now.year, now.month, now.day, 11),
    );
    await tester.pumpWidget(_host(bookings: [booking]));
    await tester.pumpAndSettle();

    expect(find.text('Booked'), findsOneWidget);
  });

  testWidgets('Confirm button enabled after selection', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('09:00'));
    await tester.pump();

    final btn = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(btn.onPressed, isNotNull);
  });
}
