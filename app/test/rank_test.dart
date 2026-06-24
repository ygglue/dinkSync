import 'package:flutter_test/flutter_test.dart';
import 'package:dinksync/features/profile/rank.dart';

void main() {
  group('rankForMmr', () {
    test('boundaries map to the correct tier', () {
      expect(rankForMmr(899), PlayerRank.bronze);
      expect(rankForMmr(900), PlayerRank.silver);
      expect(rankForMmr(1199), PlayerRank.silver);
      expect(rankForMmr(1200), PlayerRank.gold);
      expect(rankForMmr(1499), PlayerRank.gold);
      expect(rankForMmr(1500), PlayerRank.platinum);
      expect(rankForMmr(1799), PlayerRank.platinum);
      expect(rankForMmr(1800), PlayerRank.diamond);
    });

    test('extremes', () {
      expect(rankForMmr(0), PlayerRank.bronze);
      expect(rankForMmr(99999), PlayerRank.diamond);
    });

    test('starting MMR (1000) is Silver', () {
      expect(rankForMmr(1000), PlayerRank.silver);
    });

    test('labels are human-readable', () {
      expect(PlayerRank.bronze.label, 'Bronze');
      expect(PlayerRank.diamond.label, 'Diamond');
    });
  });
}
