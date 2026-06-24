/// A player's skill tier, derived from MMR. Starting MMR (1000) is Silver.
enum PlayerRank { bronze, silver, gold, platinum, diamond }

/// Maps an MMR value to its [PlayerRank]. Thresholds are inclusive lower bounds.
PlayerRank rankForMmr(int mmr) {
  if (mmr < 900) return PlayerRank.bronze;
  if (mmr < 1200) return PlayerRank.silver;
  if (mmr < 1500) return PlayerRank.gold;
  if (mmr < 1800) return PlayerRank.platinum;
  return PlayerRank.diamond;
}

extension PlayerRankX on PlayerRank {
  String get label => switch (this) {
        PlayerRank.bronze => 'Bronze',
        PlayerRank.silver => 'Silver',
        PlayerRank.gold => 'Gold',
        PlayerRank.platinum => 'Platinum',
        PlayerRank.diamond => 'Diamond',
      };
}
