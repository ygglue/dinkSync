import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_client.dart';

class CourtSlot {
  const CourtSlot({required this.id, required this.label});
  final String id;
  final String label;
}

class CustomBooking {
  const CustomBooking({
    this.id,
    required this.startsAt,
    required this.endsAt,
    this.status = 'confirmed',
    this.amountCents,
    this.currency,
    this.courtName,
    this.slotLabel,
  });
  final String? id;
  final DateTime startsAt;
  final DateTime endsAt;
  final String status;
  final int? amountCents;
  final String? currency;
  final String? courtName;
  final String? slotLabel;
}

/// Used as a Riverpod family arg — must implement == and hashCode.
class CourtBookingQuery {
  CourtBookingQuery({required this.slotId, required DateTime date})
      : date = DateTime(date.year, date.month, date.day);
  final String slotId;
  final DateTime date; // date-only (year/month/day); time part ignored

  @override
  bool operator ==(Object other) =>
      other is CourtBookingQuery &&
      slotId == other.slotId &&
      date == other.date;

  @override
  int get hashCode => Object.hash(slotId, date);
}

abstract class BookingRepository {
  Future<List<CourtSlot>> courtSlots(String courtId);
  Future<List<CustomBooking>> bookingsForSlot(CourtBookingQuery query);
  Future<void> bookSlot({
    required String slotId,
    required DateTime startsAt,
    required DateTime endsAt,
  });
  Future<void> cancelBooking(String bookingId);
  Future<List<CustomBooking>> myUpcomingBookings();
}

class SupabaseBookingRepository implements BookingRepository {
  const SupabaseBookingRepository(this._db);
  final SupabaseClient _db;

  @override
  Future<List<CourtSlot>> courtSlots(String courtId) async {
    final rows = await _db
        .from('court_slots')
        .select('id, label')
        .eq('court_id', courtId)
        .order('label');
    return rows
        .map((r) => CourtSlot(id: r['id'] as String, label: r['label'] as String))
        .toList();
  }

  @override
  Future<List<CustomBooking>> bookingsForSlot(CourtBookingQuery query) async {
    final d = query.date;
    final nextDay = d.add(const Duration(days: 1));
    final rows = await _db
        .from('custom_bookings')
        .select('id, starts_at, ends_at, status, amount_cents, currency')
        .eq('court_slot_id', query.slotId)
        .eq('status', 'confirmed')
        .gte('starts_at', d.toUtc().toIso8601String())
        .lt('starts_at', nextDay.toUtc().toIso8601String());
    return rows
        .map((r) => CustomBooking(
              id: r['id'] as String,
              startsAt: DateTime.parse(r['starts_at'] as String).toLocal(),
              endsAt: DateTime.parse(r['ends_at'] as String).toLocal(),
              status: r['status'] as String,
              amountCents: r['amount_cents'] as int?,
              currency: r['currency'] as String?,
            ))
        .toList();
  }

  @override
  Future<void> bookSlot({
    required String slotId,
    required DateTime startsAt,
    required DateTime endsAt,
  }) async {
    await _db.rpc('book_custom_slot', params: {
      'p_court_slot_id': slotId,
      'p_starts_at': startsAt.toUtc().toIso8601String(),
      'p_ends_at': endsAt.toUtc().toIso8601String(),
    });
  }

  @override
  Future<void> cancelBooking(String bookingId) async {
    await _db.rpc('cancel_custom_booking', params: {
      'p_booking_id': bookingId,
    });
  }

  @override
  Future<List<CustomBooking>> myUpcomingBookings() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return [];
    final rows = await _db
        .from('custom_bookings')
        .select('id, starts_at, ends_at, status, amount_cents, currency, courts(name), court_slots(label)')
        .eq('booker_profile_id', uid)
        .eq('status', 'confirmed')
        .gte('starts_at', DateTime.now().toUtc().toIso8601String())
        .order('starts_at');
    return rows.map((r) => CustomBooking(
          id: r['id'] as String,
          startsAt: DateTime.parse(r['starts_at'] as String).toLocal(),
          endsAt: DateTime.parse(r['ends_at'] as String).toLocal(),
          status: r['status'] as String,
          amountCents: r['amount_cents'] as int?,
          currency: r['currency'] as String?,
          courtName: (r['courts'] as Map?)?['name'] as String?,
          slotLabel: (r['court_slots'] as Map?)?['label'] as String?,
        )).toList();
  }
}

final bookingRepositoryProvider = Provider<BookingRepository>(
  (ref) => SupabaseBookingRepository(supabase),
);

final courtSlotsProvider =
    FutureProvider.family<List<CourtSlot>, String>((ref, courtId) {
  return ref.watch(bookingRepositoryProvider).courtSlots(courtId);
});

final courtBookingsProvider =
    FutureProvider.family<List<CustomBooking>, CourtBookingQuery>((ref, query) {
  return ref.watch(bookingRepositoryProvider).bookingsForSlot(query);
});

final myBookingsProvider = FutureProvider<List<CustomBooking>>((ref) {
  return ref.watch(bookingRepositoryProvider).myUpcomingBookings();
});

class LobbyProfile {
  const LobbyProfile({
    required this.displayName,
    required this.mmr,
    this.avatarUrl,
  });
  final String displayName;
  final int mmr;
  final String? avatarUrl;
}

final currentUserProfileProvider = FutureProvider<LobbyProfile>((ref) async {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) return const LobbyProfile(displayName: 'Player', mmr: 1000);
  final rows = await supabase
      .from('profiles')
      .select('display_name, mmr, avatar_url')
      .eq('id', uid)
      .limit(1);
  if (rows.isEmpty) return const LobbyProfile(displayName: 'Player', mmr: 1000);
  return LobbyProfile(
    displayName: (rows.first['display_name'] as String?) ?? 'Player',
    mmr: (rows.first['mmr'] as int?) ?? 1000,
    avatarUrl: rows.first['avatar_url'] as String?,
  );
});
