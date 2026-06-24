import 'package:flutter_test/flutter_test.dart';
import 'package:dinksync/features/profile/player_profile_repository.dart';

void main() {
  group('PublicProfile.fromMap', () {
    test('parses a row with avatar', () {
      final p = PublicProfile.fromMap(const {
        'id': 'u1',
        'display_name': 'Ada',
        'avatar_url': 'https://x/a.png',
        'mmr': 1200,
        'created_at': '2026-01-02T03:04:05Z',
      });
      expect(p.id, 'u1');
      expect(p.displayName, 'Ada');
      expect(p.avatarUrl, 'https://x/a.png');
      expect(p.mmr, 1200);
      expect(p.createdAt.toUtc().year, 2026);
    });

    test('null avatar and missing mmr default', () {
      final p = PublicProfile.fromMap(const {
        'id': 'u2',
        'display_name': 'Bo',
        'avatar_url': null,
        'mmr': null,
        'created_at': '2026-01-02T03:04:05Z',
      });
      expect(p.avatarUrl, isNull);
      expect(p.mmr, 1000); // default starting MMR
    });
  });

  group('PlayerStats', () {
    test('fromMap parses counts', () {
      final s = PlayerStats.fromMap(const {'wins': 3, 'losses': 1});
      expect(s.wins, 3);
      expect(s.losses, 1);
      expect(s.total, 4);
      expect(s.winRate, closeTo(0.75, 1e-9));
    });

    test('null map -> zeroes', () {
      final s = PlayerStats.fromMap(null);
      expect(s.wins, 0);
      expect(s.losses, 0);
    });

    test('zero games -> winRate is null (no division by zero)', () {
      const s = PlayerStats(wins: 0, losses: 0);
      expect(s.total, 0);
      expect(s.winRate, isNull);
    });
  });

  group('RecentMatch.fromMap', () {
    test('parses a row', () {
      final m = RecentMatch.fromMap(const {
        'match_id': 'm1',
        'played_at': '2026-02-03T10:00:00Z',
        'result': 'win',
        'team': 1,
        'winning_team': 1,
      });
      expect(m.matchId, 'm1');
      expect(m.result, 'win');
      expect(m.team, 1);
      expect(m.winningTeam, 1);
      expect(m.playedAt.toUtc().month, 2);
    });
  });
}
