import 'package:barbershop/features/booking/domain/booking.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BookingStatus', () {
    test('maps no_show both ways', () {
      expect(BookingStatus.fromDb('no_show'), BookingStatus.noShow);
      expect(BookingStatus.noShow.dbValue, 'no_show');
    });

    test('unknown falls back to pending', () {
      expect(BookingStatus.fromDb('weird'), BookingStatus.pending);
    });
  });

  test('Booking.fromMap parses a row and trims time seconds', () {
    final b = Booking.fromMap({
      'id': 'b1',
      'salon_id': 's1',
      'staff_id': 'st1',
      'service_name_snapshot': 'Coupe homme',
      'price_default_snapshot': 25,
      'date': '2026-06-22',
      'start_time': '09:00:00',
      'end_time': '09:30:00',
      'status': 'confirmed',
    });
    expect(b.id, 'b1');
    expect(b.salonId, 's1');
    expect(b.staffId, 'st1');
    expect(b.serviceName, 'Coupe homme');
    expect(b.priceDefault, 25.0);
    expect(b.date, '2026-06-22');
    expect(b.startHm, '09:00');
    expect(b.endHm, '09:30');
    expect(b.status, BookingStatus.confirmed);
  });
}
