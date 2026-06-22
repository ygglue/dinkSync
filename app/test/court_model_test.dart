import 'package:flutter_test/flutter_test.dart';
import 'package:dinksync/data/court.dart';

void main() {
  group('formatFee', () {
    test('PHP uses peso symbol', () => expect(formatFee(15000, 'PHP'), '₱150'));
    test('USD uses dollar symbol', () => expect(formatFee(1000, 'USD'), r'$10'));
    test('unknown currency falls back to code prefix',
        () => expect(formatFee(15000, 'EUR'), 'EUR 150'));
  });

  group('Court.fromMap', () {
    test('parses a row', () {
      final c = Court.fromMap(const {
        'id': 'c1',
        'name': 'Cebu Dinks',
        'status': 'active',
        'entry_fee_cents': 5000,
        'currency': 'PHP',
        'num_courts': 3,
        'address': 'Cebu City',
      });
      expect(c.id, 'c1');
      expect(c.isActive, true);
      expect(c.address, 'Cebu City');
    });
  });
}
