import 'package:flutter_test/flutter_test.dart';
import 'package:dinksync/data/capabilities.dart';

void main() {
  group('Capabilities.from', () {
    test('no roles, not admin -> player only', () {
      final c = Capabilities.from(isAdmin: false, memberRoles: const []);
      expect(c.isAdmin, false);
      expect(c.isManager, false);
    });

    test('any court_members role -> manager', () {
      expect(
        Capabilities.from(isAdmin: false, memberRoles: const ['staff']).isManager,
        true,
      );
      expect(
        Capabilities.from(isAdmin: false, memberRoles: const ['owner']).isManager,
        true,
      );
    });

    test('admin flag is carried through', () {
      expect(
        Capabilities.from(isAdmin: true, memberRoles: const []).isAdmin,
        true,
      );
    });
  });
}
