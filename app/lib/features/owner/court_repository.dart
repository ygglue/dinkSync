import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_client.dart';

/// A court venue owned/managed by the current user.
class Court {
  const Court({
    required this.id,
    required this.name,
    required this.status,
    required this.entryFeeCents,
    required this.currency,
    required this.numCourts,
    this.address,
  });

  final String id;
  final String name;
  final String status; // active | suspended | offboarded
  final int entryFeeCents;
  final String currency;
  final int numCourts;
  final String? address;

  bool get isActive => status == 'active';

  factory Court.fromMap(Map<String, dynamic> m) => Court(
        id: m['id'] as String,
        name: m['name'] as String,
        status: m['status'] as String,
        entryFeeCents: m['entry_fee_cents'] as int,
        currency: m['currency'] as String,
        numCourts: m['num_courts'] as int,
        address: m['address'] as String?,
      );
}

enum SubscriptionPlan { monthly, yearly }

/// Canonical centavo prices (mirror the server-side values in 0008).
int planPriceCents(SubscriptionPlan p) =>
    p == SubscriptionPlan.monthly ? 99900 : 999000;

String planName(SubscriptionPlan p) =>
    p == SubscriptionPlan.monthly ? 'monthly' : 'yearly';

/// Parse a user-entered major-unit amount ("999", "12.50") into integer minor
/// units (centavos). Returns null for blank/invalid/negative input.
int? parseAmountToMinor(String input) {
  final t = input.trim();
  if (t.isEmpty) return null;
  final v = double.tryParse(t);
  if (v == null || v < 0) return null;
  return (v * 100).round();
}

abstract class CourtRepository {
  Future<Court?> myCourt();
  Future<String> createCourt({
    required String name,
    required int entryFeeCents,
    required String currency,
    required int numCourts,
    String? address,
  });
  Future<void> subscribeCourt({
    required String courtId,
    required SubscriptionPlan plan,
  });
  Future<void> updateCourt({
    required String courtId,
    required String name,
    required int entryFeeCents,
    String? address,
  });
}

class SupabaseCourtRepository implements CourtRepository {
  SupabaseCourtRepository(this._db);
  final SupabaseClient _db;

  @override
  Future<Court?> myCourt() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return null;
    final rows = await _db
        .from('courts')
        .select()
        .eq('owner_profile_id', uid)
        .limit(1);
    return rows.isEmpty
        ? null
        : Court.fromMap(rows.first);
  }

  @override
  Future<String> createCourt({
    required String name,
    required int entryFeeCents,
    required String currency,
    required int numCourts,
    String? address,
  }) async {
    final id = await _db.rpc('create_court', params: {
      'p_name': name,
      'p_entry_fee_cents': entryFeeCents,
      'p_currency': currency,
      'p_num_courts': numCourts,
      'p_address': address,
    });
    return id as String;
  }

  @override
  Future<void> subscribeCourt({
    required String courtId,
    required SubscriptionPlan plan,
  }) async {
    await _db.rpc('subscribe_court', params: {
      'p_court_id': courtId,
      'p_plan': planName(plan),
    });
  }

  @override
  Future<void> updateCourt({
    required String courtId,
    required String name,
    required int entryFeeCents,
    String? address,
  }) async {
    await _db.from('courts').update({
      'name': name,
      'entry_fee_cents': entryFeeCents,
      'address': address,
    }).eq('id', courtId);
  }
}

final courtRepositoryProvider = Provider<CourtRepository>(
  (ref) => SupabaseCourtRepository(supabase),
);

final ownerCourtProvider = FutureProvider<Court?>(
  (ref) => ref.watch(courtRepositoryProvider).myCourt(),
);
