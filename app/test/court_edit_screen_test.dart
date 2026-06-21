import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dinksync/features/owner/court_edit_screen.dart';
import 'package:dinksync/features/owner/court_repository.dart';
import 'package:dinksync/features/owner/owner_dashboard_screen.dart';

const _court = Court(
  id: 'c1',
  name: 'Cebu Dinks',
  status: 'active',
  entryFeeCents: 5000,
  currency: 'PHP',
  numCourts: 3,
  address: 'Cebu City',
);

class _FakeRepo implements CourtRepository {
  int updateCalls = 0;
  Map<String, Object?>? lastArgs;

  @override
  Future<void> updateCourt({
    required String courtId,
    required String name,
    required int entryFeeCents,
    String? address,
  }) async {
    updateCalls++;
    lastArgs = {'courtId': courtId, 'name': name, 'entryFeeCents': entryFeeCents};
  }

  @override
  Future<Court?> myCourt() async => null;
  @override
  Future<String> createCourt(
          {required String name,
          required int entryFeeCents,
          required String currency,
          required int numCourts,
          String? address}) async =>
      'x';
  @override
  Future<void> subscribeCourt(
      {required String courtId, required SubscriptionPlan plan}) async {}
}

Widget _editHost(_FakeRepo repo, {void Function()? onSaved}) => ProviderScope(
      overrides: [courtRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        home: CourtEditScreen(court: _court, onSaved: onSaved ?? () {}),
      ),
    );

void main() {
  testWidgets('prefills, saves changes, calls onSaved', (tester) async {
    final repo = _FakeRepo();
    var saved = false;
    await tester.pumpWidget(_editHost(repo, onSaved: () => saved = true));

    expect(find.text('Cebu Dinks'), findsOneWidget); // prefilled name

    await tester.enterText(
        find.bySemanticsLabel('Court name'), 'Cebu Dinks 2');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(repo.updateCalls, 1);
    expect(repo.lastArgs!['courtId'], 'c1');
    expect(repo.lastArgs!['name'], 'Cebu Dinks 2');
    expect(repo.lastArgs!['entryFeeCents'], 5000);
    expect(saved, true);
  });

  testWidgets('blank name blocks save', (tester) async {
    final repo = _FakeRepo();
    await tester.pumpWidget(_editHost(repo));

    await tester.enterText(find.bySemanticsLabel('Court name'), '');
    await tester.tap(find.text('Save changes'));
    await tester.pump();

    expect(repo.updateCalls, 0);
    expect(find.text('Court name is required'), findsOneWidget);
  });

  testWidgets('dashboard shows edit button only when onEdit provided',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: OwnerDashboard(
        court: _court,
        onSubscribe: () {},
        onEdit: () => tapped = true,
      ),
    ));

    final editBtn = find.byKey(const Key('edit-court-button'));
    expect(editBtn, findsOneWidget);
    await tester.tap(editBtn);
    await tester.pump();
    expect(tapped, true);
  });
}
