// Phase 0 smoke tests. The full app requires Supabase + env at startup, so we
// test the pieces that are pure-logic here. End-to-end flows are covered by
// manual demo (see README) and integration tests in later phases.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dinksync/app/theme.dart';
import 'package:dinksync/config/app_config.dart';

void main() {
  group('AppTheme', () {
    testWidgets('light theme builds a valid ThemeData', (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light(), home: const Scaffold()),
      );
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('dark theme builds a valid ThemeData', (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark(), home: const Scaffold()),
      );
      expect(find.byType(Scaffold), findsOneWidget);
    });
  });

  group('AppConfigError', () {
    test('toString includes the message', () {
      const err = AppConfigError('boom');
      expect(err.toString(), contains('boom'));
    });
  });
}
