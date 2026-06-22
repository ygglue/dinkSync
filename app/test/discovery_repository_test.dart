import 'package:flutter_test/flutter_test.dart';
import 'package:dinksync/features/discovery/discovery_repository.dart';

void main() {
  group('CourtAvailability.fromSlotRows', () {
    test('counts open and in-service (excludes closed)', () {
      final a = CourtAvailability.fromSlotRows(const [
        {'status': 'open'},
        {'status': 'open'},
        {'status': 'occupied'},
        {'status': 'closed'},
      ]);
      expect(a.openCount, 2);
      expect(a.totalCount, 3);
    });

    test('no slots -> zeroes', () {
      final a = CourtAvailability.fromSlotRows(const []);
      expect(a.openCount, 0);
      expect(a.totalCount, 0);
    });
  });
}
