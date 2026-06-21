import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dinksync/data/app_mode.dart';
import 'package:dinksync/data/capabilities.dart';
import 'package:dinksync/features/shell/mode_dropdown.dart';

Future<Widget> _host({required bool isManager}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      capabilitiesProvider.overrideWith(
        (ref) async =>
            Capabilities(isAdmin: false, isManager: isManager),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: ModeDropdown(onChanged: (_) {})),
      ),
    ),
  );
}

void main() {
  testWidgets('hidden for non-managers', (tester) async {
    await tester.pumpWidget(await _host(isManager: false));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mode-dropdown')), findsNothing);
  });

  testWidgets('shown for managers', (tester) async {
    await tester.pumpWidget(await _host(isManager: true));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mode-dropdown')), findsOneWidget);
  });
}
