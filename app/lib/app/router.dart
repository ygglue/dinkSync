import 'dart:async' show StreamSubscription;

import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/app_mode.dart';
import '../data/capabilities.dart';
import '../data/supabase_client.dart';
import '../features/auth/auth_screen.dart';
import '../features/owner/court_edit_screen.dart';
import '../features/owner/court_onboarding_screen.dart';
import '../features/owner/court_repository.dart';
import '../features/owner/management_screen.dart';
import '../features/owner/subscription_screen.dart';
import '../features/discovery/court_detail_screen.dart';
import '../features/discovery/discovery_repository.dart';
import '../features/discovery/court_picker_screen.dart';
import '../features/lobby/lobby_screen.dart';
import '../features/owner/bookings_screen.dart';
import '../features/profile/player_profile_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/schedule/schedule_screen.dart';
import '../features/shell/launch_screen.dart';
import '../features/shell/manage_shell.dart';
import '../features/shell/placeholder_tab.dart';
import '../features/shell/play_shell.dart';

/// Where a signed-in user should land on launch, given their role + last mode.
String launchTarget({required bool isManager, required AppMode mode}) {
  if (isManager && mode == AppMode.management) return '/manage';
  return '/play';
}

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
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

      // Play shell — bottom nav: Play / Social / Schedule / Profile.
      StatefulShellRoute.indexedStack(
        builder: (c, s, navShell) => PlayShell(navigationShell: navShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/play', builder: (c, s) => const LobbyScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/social',
              builder: (c, s) => const PlaceholderTab(
                title: 'Social',
                icon: PhosphorIconsFill.usersThree,
                message: 'Friends and activity are coming soon.',
              ),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/schedule',
              builder: (c, s) => const ScheduleScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/profile', builder: (c, s) => const ProfileScreen()),
          ]),
        ],
      ),

      // Manage shell — bottom nav: Dashboard / Staff / Profile (Profile shared).
      StatefulShellRoute.indexedStack(
        builder: (c, s, navShell) => ManageShell(navigationShell: navShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/manage', builder: (c, s) => const ManagementHome()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/manage/bookings',
              builder: (c, s) => const BookingsScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/manage/profile',
              builder: (c, s) => const ProfileScreen(),
            ),
          ]),
        ],
      ),

      // Full-screen sub-pages pushed over the shells (with a back button).
      GoRoute(
        path: '/onboard',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (c, s) => _OnboardRoute(),
      ),
      GoRoute(
        path: '/manage/subscribe',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (c, s) => _SubscribeRoute(),
      ),
      GoRoute(
        path: '/manage/edit',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (c, s) => _EditRoute(),
      ),
      GoRoute(
        path: '/play/court/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (c, s) => CourtDetailScreen(courtId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/play/player/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (c, s) => PlayerProfileScreen(profileId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/play/courts',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (c, s) => const CourtPickerScreen(),
      ),
    ],
  );
});

void _backToManage(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/manage');
  }
}

/// First-time host onboarding (full screen). On success the user becomes a
/// manager; we drop into Management mode so the dashboard + subscribe banner show.
class _OnboardRoute extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CourtOnboardingScreen(
      onCreated: (_) {
        ref.invalidate(ownerCourtProvider);
        ref.invalidate(capabilitiesProvider);
        ref.read(appModeProvider.notifier).set(AppMode.management);
        context.go('/manage');
      },
    );
  }
}

/// Resolves the owner's current court, then shows the subscription screen.
class _SubscribeRoute extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courtAsync = ref.watch(ownerCourtProvider);
    return courtAsync.when(
      loading: () => _LoadingSubPage(onBack: () => _backToManage(context)),
      error: (e, s) => _ErrorSubPage(onBack: () => _backToManage(context)),
      data: (court) {
        if (court == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) _backToManage(context);
          });
          return _LoadingSubPage(onBack: () => _backToManage(context));
        }
        return SubscriptionScreen(
          courtId: court.id,
          onBack: () => _backToManage(context),
          onSubscribed: () {
            ref.invalidate(ownerCourtProvider);
            _backToManage(context);
          },
        );
      },
    );
  }
}

/// Resolves the owner's current court, then shows the edit screen.
class _EditRoute extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courtAsync = ref.watch(ownerCourtProvider);
    return courtAsync.when(
      loading: () => _LoadingSubPage(onBack: () => _backToManage(context)),
      error: (e, s) => _ErrorSubPage(onBack: () => _backToManage(context)),
      data: (court) {
        if (court == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) _backToManage(context);
          });
          return _LoadingSubPage(onBack: () => _backToManage(context));
        }
        return CourtEditScreen(
          court: court,
          onSaved: () {
            ref.invalidate(ownerCourtProvider);
            ref.invalidate(activeCourtsProvider);
            ref.invalidate(courtByIdProvider(court.id));
            _backToManage(context);
          },
        );
      },
    );
  }
}

/// Loading frame for a full-screen sub-page while its court resolves. Carries
/// its own back button so the user is never stranded without a way out.
class _LoadingSubPage extends StatelessWidget {
  const _LoadingSubPage({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: onBack)),
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}

/// Error frame for a full-screen sub-page, with a back button.
class _ErrorSubPage extends StatelessWidget {
  const _ErrorSubPage({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: onBack)),
      body: const Center(child: Text('Could not load court.')),
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
