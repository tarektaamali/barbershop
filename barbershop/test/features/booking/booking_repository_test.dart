import 'package:barbershop/features/booking/data/booking_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/fake_postgrest.dart';

class _MockClient extends Mock implements SupabaseClient {}

void main() {
  late _MockClient client;
  late BookingRepository repo;

  setUp(() {
    client = _MockClient();
    repo = BookingRepository(client);
  });

  test('requestBooking calls request_booking RPC and returns the id', () async {
    when(() => client.rpc('request_booking', params: any(named: 'params')))
        .thenAnswer((_) => FakeFilterBuilder<dynamic>('b1'));

    final id = await repo.requestBooking(
      salonId: 's1',
      serviceId: 'sv1',
      date: '2026-06-22',
      startTime: '09:00',
    );

    expect(id, 'b1');
    verify(() => client.rpc('request_booking', params: {
          'p_salon_id': 's1',
          'p_service_id': 'sv1',
          'p_date': '2026-06-22',
          'p_start_time': '09:00',
          'p_staff_id': null,
        })).called(1);
  });

  test('confirm calls confirm_booking RPC', () async {
    when(() => client.rpc('confirm_booking', params: any(named: 'params')))
        .thenAnswer((_) => FakeFilterBuilder<dynamic>(null));

    await repo.confirm('b1', staffId: 'st2');

    verify(() => client.rpc('confirm_booking', params: {
          'p_booking_id': 'b1',
          'p_staff_id': 'st2',
        })).called(1);
  });

  test('cancel calls cancel_booking RPC', () async {
    when(() => client.rpc('cancel_booking', params: any(named: 'params')))
        .thenAnswer((_) => FakeFilterBuilder<dynamic>(null));

    await repo.cancel('b1');

    verify(() => client.rpc('cancel_booking', params: {
          'p_booking_id': 'b1',
        })).called(1);
  });
}
