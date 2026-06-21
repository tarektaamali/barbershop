import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/domain/app_user.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/admin/presentation/admin_approvals_screen.dart';
import '../../features/booking/presentation/booking_screen.dart';
import '../../features/booking/presentation/my_reservations_screen.dart';
import '../../features/discovery/presentation/favorites_screen.dart';
import '../../features/discovery/presentation/salon_profile_screen.dart';
import '../../features/home/presentation/customer_home_screen.dart';
import '../../features/salon/presentation/salon_dashboard_screen.dart';
import '../../features/salon/presentation/salon_registration_screen.dart';

const _publicRoutes = {'/login', '/signup'};

String _homeFor(UserRole role) {
  switch (role) {
    case UserRole.customer:
      return '/home';
    case UserRole.salonOwner:
    case UserRole.staff:
      return '/salon';
    case UserRole.admin:
      return '/admin';
  }
}

/// Pure routing decision. Returns the path to redirect to, or null to stay.
String? resolveRedirect({
  required bool isLoggedIn,
  required UserRole? role,
  required String location,
}) {
  final onPublicRoute = _publicRoutes.contains(location);

  if (!isLoggedIn) {
    return onPublicRoute ? null : '/login';
  }

  // Logged in but profile/role not loaded yet — wait where we are.
  if (role == null) return null;

  final target = _homeFor(role);
  if (onPublicRoute || location == '/') return target;
  return null;
}

final goRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final repo = ref.read(authRepositoryProvider);
      final profile = ref.read(currentProfileProvider).value;
      return resolveRedirect(
        isLoggedIn: repo.currentUserId != null,
        role: profile?.role,
        location: state.matchedLocation,
      );
    },
    refreshListenable: _ProviderRefreshListenable(ref),
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SizedBox.shrink()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, __) => const SignupScreen()),
      GoRoute(path: '/home', builder: (_, __) => const CustomerHomeScreen()),
      GoRoute(
        path: '/book/:salonId',
        builder: (_, state) =>
            BookingScreen(salonId: state.pathParameters['salonId']!),
      ),
      GoRoute(
        path: '/reservations',
        builder: (_, __) => const MyReservationsScreen(),
      ),
      GoRoute(
        path: '/s/:salonId',
        builder: (_, state) =>
            SalonProfileScreen(salonId: state.pathParameters['salonId']!),
      ),
      GoRoute(
        path: '/favorites',
        builder: (_, __) => const FavoritesScreen(),
      ),
      GoRoute(
        path: '/salon/register',
        builder: (_, __) => const SalonRegistrationScreen(),
      ),
      GoRoute(path: '/salon', builder: (_, __) => const SalonDashboardScreen()),
      GoRoute(path: '/admin', builder: (_, __) => const AdminApprovalsScreen()),
    ],
  );
});

/// Rebuilds the router when auth state or the loaded profile changes.
class _ProviderRefreshListenable extends ChangeNotifier {
  _ProviderRefreshListenable(Ref ref) {
    ref.listen(authStateChangesProvider, (_, __) => notifyListeners());
    ref.listen(currentProfileProvider, (_, __) => notifyListeners());
  }
}
