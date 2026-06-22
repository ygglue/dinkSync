import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dinksync/data/court.dart';
import 'package:dinksync/features/discovery/court_list_screen.dart';
import 'package:dinksync/features/discovery/discovery_repository.dart';

class _FakeRepo implements DiscoveryRepository {
  _FakeRepo(this.courts);
  final List<Court> courts;

  @override
  Future<List<Court>> listActiveCourts() async => courts;
  @override
  Future<Court?> courtById(String id) async {
    for (final c in courts) {
      if (c.id == id) return c;
    }
    return null;
  }

  @override
  Future<CourtAvailability> availability(String courtId) async =>
      const CourtAvailability(openCount: 0, totalCount: 0);
}

const _courts = [
  Court(
      id: 'c1',
      name: 'Cebu Dinks',
      status: 'active',
      entryFeeCents: 15000,
      currency: 'PHP',
      numCourts: 3,
      address: 'Cebu City'),
  Court(
      id: 'c2',
      name: 'Manila Smash',
      status: 'active',
      entryFeeCents: 0,
      currency: 'PHP',
      numCourts: 1),
];

Widget _host(List<Court> courts) => ProviderScope(
      overrides: [
        discoveryRepositoryProvider.overrideWithValue(_FakeRepo(courts)),
      ],
      child: const MaterialApp(home: Scaffold(body: CourtListScreen())),
    );

// New helper for picker mode:
Widget _pickerHost(List<Court> courts, void Function(Court) onSelect) =>
    ProviderScope(
      overrides: [
        discoveryRepositoryProvider.overrideWithValue(_FakeRepo(courts)),
      ],
      child: MaterialApp(
        home: Scaffold(body: CourtListScreen(onSelect: onSelect)),
      ),
    );

void main() {
  testWidgets('lists courts with name and fee', (tester) async {
    await tester.pumpWidget(_host(_courts));
    await tester.pumpAndSettle();

    expect(find.text('Cebu Dinks'), findsOneWidget);
    expect(find.text('Manila Smash'), findsOneWidget);
    expect(find.text('₱150'), findsOneWidget);
  });

  testWidgets('search filters by name (case-insensitive)', (tester) async {
    await tester.pumpWidget(_host(_courts));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'manila');
    await tester.pump();

    expect(find.text('Manila Smash'), findsOneWidget);
    expect(find.text('Cebu Dinks'), findsNothing);
  });

  testWidgets('no courts at all shows empty message', (tester) async {
    await tester.pumpWidget(_host(const []));
    await tester.pumpAndSettle();

    expect(find.text('No courts available yet.'), findsOneWidget);
  });

  testWidgets('search with no match shows no-match message', (tester) async {
    await tester.pumpWidget(_host(_courts));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();

    expect(find.textContaining('No courts match'), findsOneWidget);
  });

  testWidgets('picker mode: tapping card calls onSelect, not navigation',
      (tester) async {
    Court? selected;
    await tester.pumpWidget(_pickerHost(_courts, (c) => selected = c));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cebu Dinks'));
    await tester.pump();

    expect(selected?.id, 'c1');
  });

  testWidgets('picker mode: info button is shown on each card', (tester) async {
    await tester.pumpWidget(_pickerHost(_courts, (_) {}));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.info_outline), findsNWidgets(2));
  });

  testWidgets('normal mode: info button is NOT shown', (tester) async {
    await tester.pumpWidget(_host(_courts));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.info_outline), findsNothing);
  });
}
