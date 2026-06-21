import 'package:flutter_test/flutter_test.dart';
import 'package:dinksync/data/app_mode.dart';
import 'package:dinksync/app/router.dart';

void main() {
  group('launchTarget', () {
    test('manager who last used management -> /manage', () {
      expect(
        launchTarget(isManager: true, mode: AppMode.management),
        '/manage',
      );
    });
    test('manager in play mode -> /play', () {
      expect(launchTarget(isManager: true, mode: AppMode.play), '/play');
    });
    test('non-manager always -> /play', () {
      expect(launchTarget(isManager: false, mode: AppMode.management), '/play');
      expect(launchTarget(isManager: false, mode: AppMode.play), '/play');
    });
  });
}
