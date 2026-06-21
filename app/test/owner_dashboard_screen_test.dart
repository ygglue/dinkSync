import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dinksync/features/owner/court_repository.dart';
import 'package:dinksync/features/owner/owner_dashboard_screen.dart';

const _active = Court(
  id: 'c1',
  name: 'Cebu Dinks',
  status: 'active',
  entryFeeCents: 5000,
  currency: 'PHP',
  numCourts: 3,
);

const _suspended = Court(
  id: 'c2',
  name: 'Manila Smash',
  status: 'suspended',
  entryFeeCents: 0,
  currency: 'PHP',
  numCourts: 1,
);

Widget _host(Court court, {VoidCallback? onSubscribe}) => MaterialApp(
      home: OwnerDashboard(court: court, onSubscribe: onSubscribe ?? () {}),
    );

void main() {
  testWidgets('active court: no suspended banner, shows metric cards',
      (tester) async {
    await tester.pumpWidget(_host(_active));

    expect(find.text('Cebu Dinks'), findsOneWidget);
    expect(find.textContaining('hidden from players'), findsNothing);
    expect(find.text("Today's revenue"), findsOneWidget);
    expect(find.text('Players today'), findsOneWidget);
    expect(find.text('Active queue'), findsOneWidget);
  });

  testWidgets('suspended court: shows banner, tapping calls onSubscribe',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(_host(_suspended, onSubscribe: () => tapped = true));

    expect(find.textContaining('hidden from players'), findsOneWidget);

    await tester.tap(find.text('Subscribe'));
    await tester.pump();
    expect(tapped, true);
  });
}
