import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dinksync/features/owner/subscription_screen.dart';
import 'package:dinksync/features/owner/court_repository.dart';

class _FakeRepo implements CourtRepository {
  SubscriptionPlan? subscribedPlan;
  String? subscribedCourt;

  @override
  Future<void> subscribeCourt(
      {required String courtId, required SubscriptionPlan plan}) async {
    subscribedCourt = courtId;
    subscribedPlan = plan;
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
  Future<void> updateCourt(
      {required String courtId,
      required String name,
      required int entryFeeCents,
      String? address}) async {}
}

Widget _host(_FakeRepo repo, {void Function()? onSubscribed}) {
  return ProviderScope(
    overrides: [courtRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      home: SubscriptionScreen(
        courtId: 'court-1',
        onSubscribed: onSubscribed ?? () {},
      ),
    ),
  );
}

void main() {
  testWidgets('defaults to monthly and subscribes', (tester) async {
    final repo = _FakeRepo();
    var done = false;
    await tester.pumpWidget(_host(repo, onSubscribed: () => done = true));

    await tester.tap(find.text('Subscribe'));
    await tester.pumpAndSettle();

    expect(repo.subscribedCourt, 'court-1');
    expect(repo.subscribedPlan, SubscriptionPlan.monthly);
    expect(done, true);
  });

  testWidgets('selecting yearly subscribes yearly', (tester) async {
    final repo = _FakeRepo();
    await tester.pumpWidget(_host(repo));

    await tester.tap(find.text('Yearly'));
    await tester.pump();
    await tester.tap(find.text('Subscribe'));
    await tester.pumpAndSettle();

    expect(repo.subscribedPlan, SubscriptionPlan.yearly);
  });
}
