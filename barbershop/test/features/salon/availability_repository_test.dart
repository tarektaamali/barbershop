import 'package:barbershop/features/salon/data/availability_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/fake_postgrest.dart';

class _MockClient extends Mock implements SupabaseClient {}

void main() {
  late _MockClient client;
  late AvailabilityRepository repo;

  setUp(() {
    client = _MockClient();
    repo = AvailabilityRepository(client);
  });

  test('availableSlots calls the RPC and trims seconds', () async {
    when(() => client.rpc('available_slots', params: any(named: 'params')))
        .thenAnswer(
            (_) => FakeFilterBuilder<dynamic>(['09:00:00', '09:15:00']));

    final slots = await repo.availableSlots(
      salonId: 's1',
      serviceId: 'sv1',
      date: '2026-06-22',
    );

    expect(slots, ['09:00', '09:15']);
    verify(() => client.rpc('available_slots', params: {
          'p_salon_id': 's1',
          'p_service_id': 'sv1',
          'p_date': '2026-06-22',
          'p_staff_id': null,
        })).called(1);
  });
}
