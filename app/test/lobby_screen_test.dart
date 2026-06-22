import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dinksync/data/court.dart';
import 'package:dinksync/features/lobby/booking_repository.dart';
import 'package:dinksync/features/lobby/lobby_screen.dart';

const _courtNoFee = Court(
  id: 'c1',
  name: 'Cebu Dinks',
  status: 'active',
  entryFeeCents: 15000,
  currency: 'PHP',
  numCourts: 2,
);

const _courtWithFee = Court(
  id: 'c2',
  name: 'Manila Smash',
  status: 'active',
  entryFeeCents: 10000,
  currency: 'PHP',
  numCourts: 1,
  customFeeCents: 50000,
);

Widget _host({Court? preselected}) => ProviderScope(
      overrides: [
        currentUserDisplayNameProvider
            .overrideWith((ref) async => 'Test Player'),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: LobbyScreen(initialCourt: preselected),
        ),
      ),
    );

void main() {
  testWidgets('shows "Select a court" placeholder when no court selected',
      (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(find.text('Select a court'), findsOneWidget);
  });

  testWidgets('"Book a Court" disabled when no court selected', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    final btn = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    expect(btn.onPressed, isNull);
  });

  testWidgets('"Book a Court" disabled when court has no customFeeCents',
      (tester) async {
    await tester.pumpWidget(_host(preselected: _courtNoFee));
    await tester.pumpAndSettle();

    final btn = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    expect(btn.onPressed, isNull);
  });

  testWidgets('"Book a Court" enabled when court has customFeeCents',
      (tester) async {
    await tester.pumpWidget(_host(preselected: _courtWithFee));
    await tester.pumpAndSettle();

    final btn = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    expect(btn.onPressed, isNotNull);
  });

  testWidgets('shows selected court name in selector', (tester) async {
    await tester.pumpWidget(_host(preselected: _courtWithFee));
    await tester.pumpAndSettle();
    expect(find.text('Manila Smash'), findsOneWidget);
  });

  testWidgets('shows display name in You slot', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(find.text('Test Player'), findsOneWidget);
  });

  testWidgets('"Find Match" button is always disabled', (tester) async {
    await tester.pumpWidget(_host(preselected: _courtWithFee));
    await tester.pumpAndSettle();

    final btn = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(btn.onPressed, isNull);
  });
}
