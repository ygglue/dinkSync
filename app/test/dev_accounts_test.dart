import 'package:flutter_test/flutter_test.dart';
import 'package:dinksync/features/auth/dev_accounts.dart';

void main() {
  group('dev_accounts', () {
    test('exposes exactly the five expected dev identities', () {
      final emails = kDevAccounts.map((a) => a.email).toList();
      expect(emails, [
        'p1@dinksync.dev',
        'p2@dinksync.dev',
        'owner@dinksync.dev',
        'staff@dinksync.dev',
        'admin@dinksync.dev',
      ]);
    });

    test('every account has a non-empty label', () {
      expect(kDevAccounts.every((a) => a.label.isNotEmpty), isTrue);
    });

    test('dev password matches the seed migration constant', () {
      expect(kDevPassword, 'dinkdev123');
    });
  });
}
