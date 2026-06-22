/// A court venue. Shared by the owner (management) and discovery (player)
/// features, so it lives in `data/` rather than inside either feature.
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

/// Formats a minor-unit amount with a currency symbol. Known symbols map
/// explicitly (PHP -> ₱, USD -> $); anything else falls back to the 3-letter
/// code as a prefix (e.g. "EUR 150").
String formatFee(int cents, String currency) {
  const symbols = {'PHP': '₱', 'USD': r'$'};
  final symbol = symbols[currency];
  final major = (cents / 100).toStringAsFixed(0);
  return symbol != null ? '$symbol$major' : '$currency $major';
}
