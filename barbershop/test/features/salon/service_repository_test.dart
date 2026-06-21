import 'package:barbershop/features/salon/data/service_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/fake_postgrest.dart';

class _MockClient extends Mock implements SupabaseClient {}

void main() {
  late _MockClient client;
  late ServiceRepository repo;

  setUp(() {
    client = _MockClient();
    repo = ServiceRepository(client);
  });

  test('addService calls add_service RPC and returns the id', () async {
    when(() => client.rpc('add_service', params: any(named: 'params')))
        .thenAnswer((_) => FakeFilterBuilder<dynamic>('sv1'));

    final id = await repo.addService(
      salonId: 's1',
      name: 'Coupe homme',
      durationMin: 30,
      price: 25,
    );

    expect(id, 'sv1');
    verify(() => client.rpc('add_service', params: {
          'p_salon_id': 's1',
          'p_name': 'Coupe homme',
          'p_duration_min': 30,
          'p_price': 25.0,
        })).called(1);
  });

  test('setActive calls set_service_active RPC', () async {
    when(() => client.rpc('set_service_active', params: any(named: 'params')))
        .thenAnswer((_) => FakeFilterBuilder<dynamic>(null));

    await repo.setActive('sv1', false);

    verify(() => client.rpc('set_service_active', params: {
          'p_service_id': 'sv1',
          'p_active': false,
        })).called(1);
  });
}
