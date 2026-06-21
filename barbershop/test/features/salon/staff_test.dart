import 'package:barbershop/features/salon/domain/staff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Staff.fromMap builds from a staff row', () {
    final s = Staff.fromMap({
      'id': 'st1',
      'salon_id': 's1',
      'display_name': 'Karim',
      'specialty': 'Dégradé',
      'avatar_url': null,
      'active': true,
    });
    expect(s.id, 'st1');
    expect(s.salonId, 's1');
    expect(s.displayName, 'Karim');
    expect(s.specialty, 'Dégradé');
    expect(s.active, true);
  });
}
