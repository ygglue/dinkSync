import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dinksync/data/theme_mode.dart';

void main() {
  group('ThemeModeController', () {
    test('defaults to system when nothing is stored', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(ThemeModeController(prefs).state, ThemeMode.system);
    });

    test('set persists and reloads as light', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = ThemeModeController(prefs);

      await controller.set(ThemeMode.light);

      expect(controller.state, ThemeMode.light);
      expect(ThemeModeController(prefs).state, ThemeMode.light);
    });

    test('set persists and reloads as dark', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = ThemeModeController(prefs);

      await controller.set(ThemeMode.dark);

      expect(controller.state, ThemeMode.dark);
      expect(ThemeModeController(prefs).state, ThemeMode.dark);
    });

    test('unrecognised stored value falls back to system', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'bogus'});
      final prefs = await SharedPreferences.getInstance();
      expect(ThemeModeController(prefs).state, ThemeMode.system);
    });
  });
}
