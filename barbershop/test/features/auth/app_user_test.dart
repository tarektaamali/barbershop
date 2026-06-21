import 'package:barbershop/features/auth/domain/app_user.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserRole', () {
    test('maps db snake_case to enum', () {
      expect(UserRole.fromDb('salon_owner'), UserRole.salonOwner);
      expect(UserRole.fromDb('customer'), UserRole.customer);
    });

    test('serializes enum back to db value', () {
      expect(UserRole.salonOwner.dbValue, 'salon_owner');
      expect(UserRole.admin.dbValue, 'admin');
    });

    test('unknown role falls back to customer', () {
      expect(UserRole.fromDb('wizard'), UserRole.customer);
    });
  });

  group('AppUser.fromMap', () {
    test('builds from a profiles row', () {
      final user = AppUser.fromMap({
        'id': 'abc',
        'role': 'admin',
        'full_name': 'Tarek',
        'language': 'fr',
      });
      expect(user.id, 'abc');
      expect(user.role, UserRole.admin);
      expect(user.fullName, 'Tarek');
      expect(user.language, 'fr');
    });
  });
}
