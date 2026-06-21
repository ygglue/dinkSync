import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'supabase_client.dart';

/// What a signed-in user is allowed to do. Roles are derived, not a single
/// column: admin from profiles.is_platform_admin, manager from any
/// court_members row (owner or staff).
class Capabilities {
  const Capabilities({required this.isAdmin, required this.isManager});
  const Capabilities.none() : isAdmin = false, isManager = false;

  final bool isAdmin;
  final bool isManager;

  factory Capabilities.from({
    required bool isAdmin,
    required List<String> memberRoles,
  }) {
    return Capabilities(isAdmin: isAdmin, isManager: memberRoles.isNotEmpty);
  }
}

/// Reads the current user's capabilities once. Invalidate after creating a
/// court so the mode dropdown appears.
final capabilitiesProvider = FutureProvider<Capabilities>((ref) async {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) return const Capabilities.none();

  final profile = await supabase
      .from('profiles')
      .select('is_platform_admin')
      .eq('id', uid)
      .maybeSingle();

  final members =
      await supabase.from('court_members').select('role').eq('profile_id', uid);

  final roles = (members as List)
      .map((m) => (m as Map<String, dynamic>)['role'] as String)
      .toList();

  return Capabilities.from(
    isAdmin: (profile?['is_platform_admin'] as bool?) ?? false,
    memberRoles: roles,
  );
});
