import 'dart:async' show StreamSubscription;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/app_mode.dart';
import '../data/supabase_client.dart';
import '../features/auth/auth_screen.dart';
import '../features/owner/court_repository.dart';
import '../features/owner/management_screen.dart';
import '../features/owner/subscription_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/shell/launch_screen.dart';
import '../features/shell/placeholder_tab.dart';
import '../features/shell/play_shell.dart';

/// Where a signed-in user should land on launch, given their role + last mode.
String launchTarget({required bool isManager, required AppMode mode}) {
  if (isManager && mode == AppMode.management) return '/manage';
  return '/play';
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: _AuthListenable(),
    redirect: (context, state) {
      final signedIn = supabase.auth.currentSession != null;
      final onAuth = state.matchedLocation == '/auth';
      if (!signedIn && !onAuth) return '/auth';
      if (signedIn && onAuth) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/auth', builder: (c, s) => const AuthScreen()),
      GoRoute(path: '/', builder: (c, s) => const LaunchScreen()),
      GoRoute(path: '/manage', builder: (c, s) => const ManagementScreen()),
      GoRoute(
        path: '/manage/subscribe',
        builder: (c, s) => _SubscribeRoute(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (c, s, navShell) => PlayShell(navigationShell: navShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/play',
              builder: (c, s) => const PlaceholderTab(
                title: 'Find a game',
                icon: Icons.sports_tennis,
                message: 'Court discovery and matchmaking are coming soon.',
              ),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/social',
              builder: (c, s) => const PlaceholderTab(
                title: 'Social',
                icon: Icons.groups,
                message: 'Friends and activity are coming soon.',
              ),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/profile',
              builder: (c, s) => const ProfileScreen(),
            ),
          ]),
        ],
      ),
    ],
  );
});

/// Resolves the owner's current court id, then shows the subscription screen.
class _SubscribeRoute extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courtAsync = ref.watch(ownerCourtProvider);
    return courtAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) =>
          const Scaffold(body: Center(child: Text('Could not load court.'))),
      data: (court) {
        if (court == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) context.go('/manage');
          });
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        return SubscriptionScreen(
          courtId: court.id,
          onSubscribed: () {
            ref.invalidate(ownerCourtProvider);
            context.go('/manage');
          },
        );
      },
    );
  }
}

/// Bridges Supabase auth changes to GoRouter's redirect.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable() {
    _sub = supabase.auth.onAuthStateChange.listen((_) => notifyListeners());
  }
  late final StreamSubscription<AuthState> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
