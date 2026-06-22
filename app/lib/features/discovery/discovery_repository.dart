import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/court.dart';
import '../../data/supabase_client.dart';

/// Live court availability for a venue, derived from its `court_slots`.
class CourtAvailability {
  const CourtAvailability({required this.openCount, required this.totalCount});

  final int openCount; // slots with status 'open'
  final int totalCount; // in-service slots: 'open' or 'occupied'

  /// Builds availability from `court_slots` rows (each having a `status`).
  /// `closed` slots are out of service and excluded from [totalCount].
  factory CourtAvailability.fromSlotRows(List<Map<String, dynamic>> rows) {
    var open = 0;
    var total = 0;
    for (final r in rows) {
      final status = r['status'] as String?;
      if (status == 'open') {
        open++;
        total++;
      } else if (status == 'occupied') {
        total++;
      }
    }
    return CourtAvailability(openCount: open, totalCount: total);
  }
}

/// Player-facing reads of public court data.
abstract class DiscoveryRepository {
  Future<List<Court>> listActiveCourts();
  Future<Court?> courtById(String id);
  Future<CourtAvailability> availability(String courtId);
}

class SupabaseDiscoveryRepository implements DiscoveryRepository {
  SupabaseDiscoveryRepository(this._db);
  final SupabaseClient _db;

  @override
  Future<List<Court>> listActiveCourts() async {
    final rows = await _db
        .from('courts')
        .select()
        .eq('status', 'active')
        .order('name');
    return rows.map(Court.fromMap).toList();
  }

  @override
  Future<Court?> courtById(String id) async {
    final rows = await _db.from('courts').select().eq('id', id).limit(1);
    return rows.isEmpty ? null : Court.fromMap(rows.first);
  }

  @override
  Future<CourtAvailability> availability(String courtId) async {
    final rows =
        await _db.from('court_slots').select('status').eq('court_id', courtId);
    return CourtAvailability.fromSlotRows(rows);
  }
}

final discoveryRepositoryProvider = Provider<DiscoveryRepository>(
  (ref) => SupabaseDiscoveryRepository(supabase),
);

/// All active courts, fetched once. Name search filters this list client-side.
final activeCourtsProvider = FutureProvider<List<Court>>(
  (ref) => ref.watch(discoveryRepositoryProvider).listActiveCourts(),
);

final courtByIdProvider = FutureProvider.family<Court?, String>(
  (ref, id) => ref.watch(discoveryRepositoryProvider).courtById(id),
);

final courtAvailabilityProvider =
    FutureProvider.family<CourtAvailability, String>(
  (ref, id) => ref.watch(discoveryRepositoryProvider).availability(id),
);
