import 'dart:async' show StreamSubscription;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/supabase_client.dart';
import '../features/auth/auth_screen.dart';
import '../features/profile/profile_screen.dart';

/// The router. Redirects to /auth when signed out, to /profile when signed in.
/// Phase 0 only has two destinations; later phases add player/owner/staff/admin.
GoRouter buildRouter() {
  return GoRouter(
    initialLocation: '/profile',
    refreshListenable: _AuthListenable(),
    redirect: (context, state) {
      final signedIn = supabase.auth.currentSession != null;
      final onAuth = state.matchedLocation == '/auth';
      if (!signedIn && !onAuth) return '/auth';
      if (signedIn && onAuth) return '/profile';
      return null;
    },
    routes: [
      GoRoute(
        path: '/auth',
        builder: (context, state) => const AuthScreen(),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),
    ],
  );
}

/// A [Listenable] that fires whenever Supabase auth state changes, so GoRouter
/// can re-run its redirect and move the user between /auth and /profile
/// automatically.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable() {
    _sub = supabase.auth.onAuthStateChange.listen((_) {
      notifyListeners();
    });
  }
  late final StreamSubscription<AuthState> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
