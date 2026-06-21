import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dinksync/data/app_mode.dart';

void main() {
  group('AppModeController', () {
    test('defaults to play when nothing is stored', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(AppModeController(prefs).state, AppMode.play);
    });

    test('set persists and reloads as management', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = AppModeController(prefs);

      await controller.set(AppMode.management);

      expect(controller.state, AppMode.management);
      expect(AppModeController(prefs).state, AppMode.management);
    });
  });
}
