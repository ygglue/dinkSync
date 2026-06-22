import 'package:flutter_test/flutter_test.dart';
import 'package:dinksync/features/lobby/booking_repository.dart';

void main() {
  group('CourtBookingQuery equality', () {
    final day = DateTime(2026, 6, 22);

    test('equal when slotId and date match', () {
      final a = CourtBookingQuery(slotId: 'slot-1', date: day);
      final b = CourtBookingQuery(slotId: 'slot-1', date: day);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('not equal when slotId differs', () {
      final a = CourtBookingQuery(slotId: 'slot-1', date: day);
      final b = CourtBookingQuery(slotId: 'slot-2', date: day);
      expect(a, isNot(equals(b)));
    });

    test('not equal when date differs', () {
      final a = CourtBookingQuery(slotId: 'slot-1', date: DateTime(2026, 6, 22));
      final b = CourtBookingQuery(slotId: 'slot-1', date: DateTime(2026, 6, 23));
      expect(a, isNot(equals(b)));
    });

    test('date normalised to midnight — different times same day are equal', () {
      final a = CourtBookingQuery(
          slotId: 'slot-1',
          date: DateTime(2026, 6, 22, 9, 30)); // 9:30am
      final b = CourtBookingQuery(
          slotId: 'slot-1',
          date: DateTime(2026, 6, 22, 23, 59)); // 11:59pm
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
