import 'package:barbershop/core/router/app_router.dart';
import 'package:barbershop/features/auth/domain/app_user.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveRedirect', () {
    test('logged-out user is sent to /login', () {
      expect(
        resolveRedirect(isLoggedIn: false, role: null, location: '/'),
        '/login',
      );
    });

    test('logged-out user already on /signup stays', () {
      expect(
        resolveRedirect(isLoggedIn: false, role: null, location: '/signup'),
        isNull,
      );
    });

    test('customer landing on /login is routed to /home', () {
      expect(
        resolveRedirect(
          isLoggedIn: true,
          role: UserRole.customer,
          location: '/login',
        ),
        '/home',
      );
    });

    test('salon owner is routed to /salon', () {
      expect(
        resolveRedirect(
          isLoggedIn: true,
          role: UserRole.salonOwner,
          location: '/login',
        ),
        '/salon',
      );
    });

    test('staff also routes to /salon', () {
      expect(
        resolveRedirect(
          isLoggedIn: true,
          role: UserRole.staff,
          location: '/',
        ),
        '/salon',
      );
    });

    test('admin is routed to /admin', () {
      expect(
        resolveRedirect(
          isLoggedIn: true,
          role: UserRole.admin,
          location: '/login',
        ),
        '/admin',
      );
    });

    test('customer already on /home stays', () {
      expect(
        resolveRedirect(
          isLoggedIn: true,
          role: UserRole.customer,
          location: '/home',
        ),
        isNull,
      );
    });
  });
}
