import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/supabase_client.dart';

// ── State ─────────────────────────────────────────────────────────────────────

sealed class MatchmakingState {
  const MatchmakingState();
}

class MatchmakingIdle extends MatchmakingState {
  const MatchmakingIdle();
}

class MatchmakingSearching extends MatchmakingState {
  const MatchmakingSearching({required this.requestId, required this.courtId});
  final String requestId;
  final String courtId;
}

class MatchmakingMatched extends MatchmakingState {
  const MatchmakingMatched({
    required this.groupId,
    required this.slotLabel,
    required this.memberIds,
  });
  final String groupId;
  final String? slotLabel;
  final List<String> memberIds;
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class MatchmakingNotifier extends StateNotifier<MatchmakingState> {
  MatchmakingNotifier() : super(const MatchmakingIdle());

  StreamSubscription<List<Map<String, dynamic>>>? _sub;

  Future<void> joinQueue({
    required String courtId,
    required int mmr,
  }) async {
    if (state is! MatchmakingIdle) return;
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    final row = await supabase
        .from('matchmaking_requests')
        .insert({
          'court_id': courtId,
          'profile_id': uid,
          'party_size_wanted': 1,
          'status': 'open',
          'mmr_at_request': mmr,
        })
        .select('id')
        .single();

    final requestId = row['id'] as String;
    state = MatchmakingSearching(requestId: requestId, courtId: courtId);

    // Watch this request row for status transitions
    _sub = supabase
        .from('matchmaking_requests')
        .stream(primaryKey: ['id'])
        .eq('id', requestId)
        .listen(_onRequestUpdate);
  }

  Future<void> cancelQueue() async {
    final s = state;
    if (s is! MatchmakingSearching) return;
    _sub?.cancel();
    _sub = null;
    try {
      await supabase
          .from('matchmaking_requests')
          .delete()
          .eq('id', s.requestId);
    } catch (_) {
      // Row may already be gone; safe to ignore
    }
    state = const MatchmakingIdle();
  }

  void acknowledgeMatch() {
    state = const MatchmakingIdle();
  }

  Future<void> _onRequestUpdate(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty || state is! MatchmakingSearching) return;
    final row = rows.first;
    if (row['status'] != 'matched') return;

    _sub?.cancel();
    _sub = null;

    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    // Find the group this player was placed into
    final memberRows = await supabase
        .from('match_group_members')
        .select('match_group_id, profile_id')
        .eq('profile_id', uid)
        .order('match_group_id');

    if (memberRows.isEmpty) return;
    final groupId = memberRows.last['match_group_id'] as String;

    // Fetch group details (slot_label)
    final groupRows = await supabase
        .from('match_groups')
        .select('id, slot_label, status')
        .eq('id', groupId)
        .limit(1);

    final slotLabel = groupRows.isNotEmpty
        ? groupRows.first['slot_label'] as String?
        : null;

    // Fetch all member ids in the group
    final allMembers = await supabase
        .from('match_group_members')
        .select('profile_id')
        .eq('match_group_id', groupId);

    final memberIds = allMembers
        .map((r) => r['profile_id'] as String)
        .toList();

    state = MatchmakingMatched(
      groupId: groupId,
      slotLabel: slotLabel,
      memberIds: memberIds,
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final matchmakingProvider =
    StateNotifierProvider<MatchmakingNotifier, MatchmakingState>(
  (ref) => MatchmakingNotifier(),
);

// ── Queue depth provider (live count of open requests at a court) ─────────────

final queueDepthProvider = StreamProvider.family<int, String>((ref, courtId) {
  // Poll via stream: Supabase .stream() filters by equality only, so we
  // stream all open requests and count client-side.
  final controller = StreamController<int>();

  final sub = supabase
      .from('matchmaking_requests')
      .stream(primaryKey: ['id'])
      .eq('court_id', courtId)
      .listen((rows) {
        final open = rows.where((r) => r['status'] == 'open').length;
        if (!controller.isClosed) controller.add(open);
      });

  ref.onDispose(() {
    sub.cancel();
    controller.close();
  });

  return controller.stream;
});
