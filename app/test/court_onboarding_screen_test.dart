import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dinksync/features/owner/court_onboarding_screen.dart';
import 'package:dinksync/features/owner/court_repository.dart';

class _FakeRepo implements CourtRepository {
  int createCalls = 0;
  Map<String, Object?>? lastArgs;

  @override
  Future<String> createCourt({
    required String name,
    required int entryFeeCents,
    required String currency,
    required int numCourts,
    String? address,
    int? customFeeCents,
  }) async {
    createCalls++;
    lastArgs = {
      'name': name,
      'entryFeeCents': entryFeeCents,
      'numCourts': numCourts,
      'customFeeCents': customFeeCents,
    };
    return 'new-court-id';
  }

  @override
  Future<Court?> myCourt() async => null;
  @override
  Future<void> subscribeCourt(
          {required String courtId, required SubscriptionPlan plan}) async {}
  @override
  Future<void> updateCourt(
      {required String courtId,
      required String name,
      required int entryFeeCents,
      String? address,
      int? customFeeCents}) async {}
}

Widget _host(_FakeRepo repo, {void Function(String)? onCreated}) {
  return ProviderScope(
    overrides: [courtRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      home: CourtOnboardingScreen(onCreated: onCreated ?? (_) {}),
    ),
  );
}

void main() {
  testWidgets('blank name blocks submit and shows error', (tester) async {
    final repo = _FakeRepo();
    await tester.pumpWidget(_host(repo));

    await tester.ensureVisible(find.text('Create court'));
    await tester.tap(find.text('Create court'));
    await tester.pump();

    expect(repo.createCalls, 0);
    expect(find.text('Court name is required'), findsOneWidget);
  });

  testWidgets('valid form calls createCourt and onCreated', (tester) async {
    final repo = _FakeRepo();
    String? created;
    await tester.pumpWidget(_host(repo, onCreated: (id) => created = id));

    await tester.enterText(find.bySemanticsLabel('Court name'), 'Cebu Dinks');
    await tester.enterText(find.bySemanticsLabel('Entry fee (PHP)'), '50');
    await tester.ensureVisible(find.text('Create court'));
    await tester.tap(find.text('Create court'));
    await tester.pumpAndSettle();

    expect(repo.createCalls, 1);
    expect(repo.lastArgs!['name'], 'Cebu Dinks');
    expect(repo.lastArgs!['entryFeeCents'], 5000);
    expect(repo.lastArgs!['numCourts'], 1);
    expect(created, 'new-court-id');
  });
}
