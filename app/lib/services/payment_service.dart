import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/supabase_client.dart';

/// Result of creating an entry payment or marking one paid offline.
/// Keeps the UI decoupled from Supabase row shapes.
class Payment {
  const Payment({
    required this.id,
    required this.amountCents,
    required this.currency,
    required this.status,
    required this.provider,
  });

  final String id;
  final int amountCents;
  final String currency;
  final String status; // pending | paid | failed | refunded
  final String provider; // mock | stripe | gcash | maya | offline
}

/// Subscription result for owner -> admin billing (Phase 3).
class Subscription {
  const Subscription({
    required this.id,
    required this.courtId,
    required this.plan,
    required this.status,
  });

  final String id;
  final String courtId;
  final String plan; // monthly | yearly
  final String status; // active | past_due | canceled
}

/// The single payment seam for the whole app. Phase 0 ships [MockPaymentService]
/// so the full match loop can be demoed without a real payment provider. When
/// the launch region is decided, swap in a real implementation (Stripe Connect,
/// GCash/Maya, Pix, ...) behind this same interface — UI code does not change.
abstract class PaymentService {
  /// Player pays entry to a court. Inserts a payments row and "charges" it.
  Future<Payment> createEntryPayment({
    required String courtId,
    required String playerId,
    required int amountCents,
    required String currency,
  });

  /// Owner subscribes (pays admin). Phase 3.
  Future<Subscription> createOwnerSubscription({
    required String courtId,
    required String plan,
    required int amountCents,
    required String currency,
  });

  /// Staff marks an offline (cash / e-wallet) payment as collected.
  /// `collectedByMemberId` is the court_members row id of the staffer.
  Future<Payment> markPaidOffline({
    required String paymentId,
    required String collectedByMemberId,
  });
}

/// Provider — swap [MockPaymentService] for a real impl here, nowhere else.
final paymentServiceProvider = Provider<PaymentService>((ref) {
  return MockPaymentService();
});

/// Auto-succeeding stub. Writes a `paid` row to the `payments` table using the
/// client (RLS allows the payer to insert their own entry payment). When a real
/// provider is wired in, the charge happens BEFORE this insert and the row
/// status reflects the real outcome.
class MockPaymentService implements PaymentService {
  @override
  Future<Payment> createEntryPayment({
    required String courtId,
    required String playerId,
    required int amountCents,
    required String currency,
  }) async {
    final row = await supabase.from('payments').insert({
      'payer_profile_id': playerId,
      'payee_court_id': courtId,
      'kind': 'entry',
      'amount_cents': amountCents,
      'currency': currency,
      'status': 'paid', // mock always succeeds
      'provider': 'mock',
    }).select().single();
    return _toPayment(row);
  }

  @override
  Future<Subscription> createOwnerSubscription({
    required String courtId,
    required String plan,
    required int amountCents,
    required String currency,
  }) async {
    // Subscriptions are written via RPC in Phase 3 (service-role); the mock
    // just returns a synthetic active subscription for now.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return Subscription(
      id: 'mock_sub_${DateTime.now().millisecondsSinceEpoch}',
      courtId: courtId,
      plan: plan,
      status: 'active',
    );
  }

  @override
  Future<Payment> markPaidOffline({
    required String paymentId,
    required String collectedByMemberId,
  }) async {
    final row = await supabase
        .from('payments')
        .update({
          'status': 'paid',
          'provider': 'offline',
          'collected_by_member_id': collectedByMemberId,
        })
        .eq('id', paymentId)
        .select()
        .single();
    return _toPayment(row);
  }

  Payment _toPayment(Map<String, dynamic> row) {
    return Payment(
      id: row['id'] as String,
      amountCents: row['amount_cents'] as int,
      currency: row['currency'] as String,
      status: row['status'] as String,
      provider: row['provider'] as String,
    );
  }
}
