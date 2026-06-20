import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dinksync/features/auth/auth_screen.dart';
import 'package:dinksync/features/auth/dev_accounts.dart';

Widget _host() => const ProviderScope(
      child: MaterialApp(home: AuthScreen()),
    );

void main() {
  group('AuthScreen', () {
    testWidgets('shows Sign In / Sign Up toggle and Google button',
        (tester) async {
      await tester.pumpWidget(_host());
      expect(find.text('Sign In'), findsOneWidget);
      expect(find.text('Sign Up'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
    });

    testWidgets('renders a dev-login button for every dev account in debug',
        (tester) async {
      await tester.pumpWidget(_host());
      expect(find.text('DEV ONLY'), findsOneWidget);
      for (final account in kDevAccounts) {
        expect(find.widgetWithText(OutlinedButton, account.label),
            findsOneWidget);
      }
    });
  });
}
