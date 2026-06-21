import 'package:barbershop/features/salon/domain/working_hours.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WorkingHours.fromMap parses a row and trims seconds', () {
    final wh = WorkingHours.fromMap({
      'id': 'wh1',
      'staff_id': 'st1',
      'weekday': 1,
      'start_time': '09:00:00',
      'end_time': '12:00:00',
    });
    expect(wh.id, 'wh1');
    expect(wh.staffId, 'st1');
    expect(wh.weekday, 1);
    expect(wh.startHm, '09:00');
    expect(wh.endHm, '12:00');
  });
}
