import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dinksync/data/app_mode.dart';
import 'package:dinksync/data/theme_mode.dart';
import 'package:dinksync/features/profile/appearance_selector.dart';

/// Mounts [AppearanceSelector] with a fresh (empty) SharedPreferences and
/// returns the backing container so tests can read [themeModeProvider].
Future<ProviderContainer> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: AppearanceSelector()),
      ),
    ),
  );
  return container;
}

void main() {
  testWidgets('renders System, Light and Dark segments', (tester) async {
    await _pump(tester);

    expect(find.text('System'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
  });

  testWidgets('defaults to system selection', (tester) async {
    final container = await _pump(tester);
    expect(container.read(themeModeProvider), ThemeMode.system);
  });

  testWidgets('tapping Light sets themeMode to light', (tester) async {
    final container = await _pump(tester);

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();

    expect(container.read(themeModeProvider), ThemeMode.light);
  });

  testWidgets('tapping Dark sets themeMode to dark', (tester) async {
    final container = await _pump(tester);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(container.read(themeModeProvider), ThemeMode.dark);
  });
}
