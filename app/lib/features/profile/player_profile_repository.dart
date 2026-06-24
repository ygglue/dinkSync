import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_client.dart';

/// Public, read-only view of another player (from the public_profiles view).
class PublicProfile {
  const PublicProfile({
    required this.id,
    required this.displayName,
    this.avatarUrl,
    required this.mmr,
    required this.createdAt,
  });

  final String id;
  final String displayName;
  final String? avatarUrl;
  final int mmr;
  final DateTime createdAt;

  factory PublicProfile.fromMap(Map<String, dynamic> m) => PublicProfile(
        id: m['id'] as String,
        displayName: (m['display_name'] as String?) ?? 'Player',
        avatarUrl: m['avatar_url'] as String?,
        mmr: (m['mmr'] as int?) ?? 1000,
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}

/// Aggregate win/loss record (from public_player_stats).
class PlayerStats {
  const PlayerStats({required this.wins, required this.losses});

  final int wins;
  final int losses;

  int get total => wins + losses;

  /// Fraction of games won, or null when no games have been played.
  double? get winRate => total == 0 ? null : wins / total;

  factory PlayerStats.fromMap(Map<String, dynamic>? m) => PlayerStats(
        wins: (m?['wins'] as int?) ?? 0,
        losses: (m?['losses'] as int?) ?? 0,
      );
}

/// One completed match for a player (from public_recent_matches).
class RecentMatch {
  const RecentMatch({
    required this.matchId,
    required this.playedAt,
    required this.result,
    required this.team,
    this.winningTeam,
  });

  final String matchId;
  final DateTime playedAt;
  final String result; // 'win' | 'loss'
  final int team;
  final int? winningTeam;

  factory RecentMatch.fromMap(Map<String, dynamic> m) => RecentMatch(
        matchId: m['match_id'] as String,
        playedAt: DateTime.parse(m['played_at'] as String).toLocal(),
        result: m['result'] as String,
        team: m['team'] as int,
        winningTeam: m['winning_team'] as int?,
      );
}

abstract class PlayerProfileRepository {
  Future<PublicProfile?> fetchProfile(String id);
  Future<PlayerStats> fetchStats(String id);
  Future<List<RecentMatch>> fetchRecentMatches(String id);
  Future<List<PublicProfile>> searchPlayers(String query);
}

class SupabasePlayerProfileRepository implements PlayerProfileRepository {
  SupabasePlayerProfileRepository(this._db);
  final SupabaseClient _db;

  @override
  Future<PublicProfile?> fetchProfile(String id) async {
    final rows =
        await _db.from('public_profiles').select().eq('id', id).limit(1);
    return rows.isEmpty ? null : PublicProfile.fromMap(rows.first);
  }

  @override
  Future<PlayerStats> fetchStats(String id) async {
    final rows = await _db
        .from('public_player_stats')
        .select('wins, losses')
        .eq('profile_id', id)
        .limit(1);
    return PlayerStats.fromMap(rows.isEmpty ? null : rows.first);
  }

  @override
  Future<List<RecentMatch>> fetchRecentMatches(String id) async {
    final rows = await _db
        .from('public_recent_matches')
        .select('match_id, played_at, result, team, winning_team')
        .eq('profile_id', id)
        .order('played_at', ascending: false)
        .limit(10);
    return rows.map(RecentMatch.fromMap).toList();
  }

  @override
  Future<List<PublicProfile>> searchPlayers(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final me = _db.auth.currentUser?.id;
    // Build the base filter then conditionally exclude the current user.
    // supabase_flutter ^2.x returns PostgrestFilterBuilder which supports
    // chaining; we store as dynamic to avoid the generic type mismatch when
    // the optional .neq() call returns a narrower type.
    dynamic builder = _db
        .from('public_profiles')
        .select()
        .ilike('display_name', '%$q%');
    if (me != null) builder = (builder as PostgrestFilterBuilder).neq('id', me);
    final dynamic rawRows = await (builder as PostgrestFilterBuilder)
        .order('display_name')
        .limit(20);
    final rows = List<Map<String, dynamic>>.from(rawRows as List);
    return rows.map(PublicProfile.fromMap).toList();
  }
}

final playerProfileRepositoryProvider = Provider<PlayerProfileRepository>(
  (ref) => SupabasePlayerProfileRepository(supabase),
);

final playerProfileProvider =
    FutureProvider.family<PublicProfile?, String>((ref, id) {
  return ref.watch(playerProfileRepositoryProvider).fetchProfile(id);
});

final playerStatsProvider =
    FutureProvider.family<PlayerStats, String>((ref, id) {
  return ref.watch(playerProfileRepositoryProvider).fetchStats(id);
});

final playerRecentMatchesProvider =
    FutureProvider.family<List<RecentMatch>, String>((ref, id) {
  return ref.watch(playerProfileRepositoryProvider).fetchRecentMatches(id);
});

final playerSearchProvider =
    FutureProvider.family<List<PublicProfile>, String>((ref, query) {
  return ref.watch(playerProfileRepositoryProvider).searchPlayers(query);
});
