import 'package:barbershop/features/salon/domain/service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Service.fromMap builds from a services row', () {
    final s = Service.fromMap({
      'id': 'sv1',
      'salon_id': 's1',
      'name': 'Coupe homme',
      'duration_min': 30,
      'price': 25,
      'active': true,
    });
    expect(s.id, 'sv1');
    expect(s.salonId, 's1');
    expect(s.name, 'Coupe homme');
    expect(s.durationMin, 30);
    expect(s.price, 25.0);
    expect(s.active, true);
  });
}
