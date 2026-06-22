import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dinksync/data/court.dart';
import 'package:dinksync/features/discovery/court_detail_screen.dart';
import 'package:dinksync/features/discovery/discovery_repository.dart';

class _FakeRepo implements DiscoveryRepository {
  _FakeRepo(this.court, this.avail);
  final Court court;
  final CourtAvailability avail;

  @override
  Future<List<Court>> listActiveCourts() async => [court];
  @override
  Future<Court?> courtById(String id) async => id == court.id ? court : null;
  @override
  Future<CourtAvailability> availability(String courtId) async => avail;
}

const _court = Court(
  id: 'c1',
  name: 'Cebu Dinks',
  status: 'active',
  entryFeeCents: 15000,
  currency: 'PHP',
  numCourts: 3,
  address: 'Cebu City',
);

Widget _host(DiscoveryRepository repo) => ProviderScope(
      overrides: [discoveryRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: CourtDetailScreen(courtId: 'c1')),
    );

void main() {
  testWidgets('renders venue info, availability, and disabled CTA',
      (tester) async {
    final repo = _FakeRepo(
        _court, const CourtAvailability(openCount: 2, totalCount: 3));
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(find.text('Cebu Dinks'), findsWidgets); // app bar + body
    expect(find.text('Cebu City'), findsOneWidget);
    expect(find.text('Entry fee ₱150'), findsOneWidget);
    expect(find.text('2 of 3 courts open'), findsOneWidget);

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull); // disabled
    expect(find.text('Join queue — coming soon'), findsOneWidget);
  });

  testWidgets('no in-service courts shows "No courts in service"',
      (tester) async {
    final repo = _FakeRepo(
        _court, const CourtAvailability(openCount: 0, totalCount: 0));
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(find.text('No courts in service'), findsOneWidget);
  });
}
