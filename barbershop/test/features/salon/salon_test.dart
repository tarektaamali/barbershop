import 'package:barbershop/features/salon/domain/salon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SalonStatus', () {
    test('maps db value to enum and back', () {
      expect(SalonStatus.fromDb('approved'), SalonStatus.approved);
      expect(SalonStatus.suspended.dbValue, 'suspended');
    });

    test('unknown status falls back to pending', () {
      expect(SalonStatus.fromDb('weird'), SalonStatus.pending);
    });
  });

  group('Salon.fromMap', () {
    test('builds from a salons row', () {
      final s = Salon.fromMap({
        'id': 's1',
        'owner_id': 'u1',
        'name': 'Barber House',
        'description': 'Best fades',
        'city': 'Tunis',
        'address': 'Rue 1',
        'cover_url': null,
        'status': 'pending',
        'show_prices': true,
        'rating_avg': 4.5,
        'rating_count': 12,
      });
      expect(s.id, 's1');
      expect(s.ownerId, 'u1');
      expect(s.name, 'Barber House');
      expect(s.city, 'Tunis');
      expect(s.status, SalonStatus.pending);
      expect(s.showPrices, true);
      expect(s.ratingAvg, 4.5);
      expect(s.ratingCount, 12);
    });

    test('coerces integer rating_avg to double', () {
      final s = Salon.fromMap({
        'id': 's1',
        'owner_id': 'u1',
        'name': 'X',
        'city': 'Sfax',
        'status': 'approved',
        'show_prices': false,
        'rating_avg': 0,
        'rating_count': 0,
      });
      expect(s.ratingAvg, 0.0);
      expect(s.showPrices, false);
    });
  });
}
