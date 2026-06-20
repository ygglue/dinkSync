/// DEV ONLY. These identities exist solely in dev/seeded databases and are used
/// by the debug-only dev-login panel. This file is referenced only from code
/// wrapped in `if (kDebugMode)`, so it is tree-shaken out of release builds.
///
/// [kDevPassword] MUST match the password set in
/// `supabase/migrations/0005_dev_seed_auth.sql`.
library;

const String kDevPassword = 'dinkdev123';

class DevAccount {
  const DevAccount(this.label, this.email);
  final String label;
  final String email;
}

const List<DevAccount> kDevAccounts = [
  DevAccount('Player 1', 'p1@dinksync.dev'),
  DevAccount('Player 2', 'p2@dinksync.dev'),
  DevAccount('Owner', 'owner@dinksync.dev'),
  DevAccount('Staff', 'staff@dinksync.dev'),
  DevAccount('Admin', 'admin@dinksync.dev'),
];
