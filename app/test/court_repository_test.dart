import 'package:flutter_test/flutter_test.dart';
import 'package:dinksync/features/owner/court_repository.dart';

void main() {
  group('parseAmountToMinor', () {
    test('whole pesos -> centavos', () {
      expect(parseAmountToMinor('999'), 99900);
    });
    test('decimal pesos -> centavos (rounded)', () {
      expect(parseAmountToMinor('12.50'), 1250);
      expect(parseAmountToMinor('12.505'), 1251);
    });
    test('blank or invalid or negative -> null', () {
      expect(parseAmountToMinor(''), null);
      expect(parseAmountToMinor('abc'), null);
      expect(parseAmountToMinor('-5'), null);
    });
  });

  group('plan pricing', () {
    test('canonical centavo prices', () {
      expect(planPriceCents(SubscriptionPlan.monthly), 99900);
      expect(planPriceCents(SubscriptionPlan.yearly), 999000);
    });
    test('plan db names', () {
      expect(planName(SubscriptionPlan.monthly), 'monthly');
      expect(planName(SubscriptionPlan.yearly), 'yearly');
    });
  });

  group('Court.fromMap', () {
    test('maps fields and isActive', () {
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
      expect(c.name, 'Cebu Dinks');
      expect(c.isActive, true);
      expect(c.entryFeeCents, 5000);
      expect(c.numCourts, 3);
      expect(c.address, 'Cebu City');
    });
    test('suspended is not active; null address ok', () {
      final c = Court.fromMap(const {
        'id': 'c2',
        'name': 'X',
        'status': 'suspended',
        'entry_fee_cents': 0,
        'currency': 'PHP',
        'num_courts': 1,
        'address': null,
      });
      expect(c.isActive, false);
      expect(c.address, null);
    });
    test('Court.fromMap maps custom_fee_cents', () {
      final c = Court.fromMap({
        'id': 'x1',
        'name': 'Test',
        'status': 'active',
        'entry_fee_cents': 10000,
        'currency': 'PHP',
        'num_courts': 2,
        'address': null,
        'image_url': null,
        'custom_fee_cents': 50000,
      });
      expect(c.customFeeCents, 50000);
    });

    test('Court.fromMap custom_fee_cents null when absent', () {
      final c = Court.fromMap({
        'id': 'x2',
        'name': 'Test2',
        'status': 'active',
        'entry_fee_cents': 0,
        'currency': 'PHP',
        'num_courts': 1,
        'address': null,
        'image_url': null,
        'custom_fee_cents': null,
      });
      expect(c.customFeeCents, isNull);
    });
  });
}
