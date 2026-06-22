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
  });
}
