import 'package:barbershop/features/salon/data/salon_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/fake_postgrest.dart';

class _MockClient extends Mock implements SupabaseClient {}

void main() {
  late _MockClient client;
  late SalonRepository repo;

  setUp(() {
    client = _MockClient();
    repo = SalonRepository(client);
  });

  test('registerSalon calls the register_salon RPC and returns the id', () async {
    when(() => client.rpc('register_salon', params: any(named: 'params')))
        .thenAnswer((_) => FakeFilterBuilder<dynamic>('new-salon-id'));

    final id = await repo.registerSalon(name: 'Barber House', city: 'Tunis');

    expect(id, 'new-salon-id');
    verify(() => client.rpc('register_salon', params: {
          'p_name': 'Barber House',
          'p_city': 'Tunis',
          'p_description': null,
          'p_address': null,
        })).called(1);
  });

  test('updateMySalon calls the update_my_salon RPC with all fields', () async {
    when(() => client.rpc('update_my_salon', params: any(named: 'params')))
        .thenAnswer((_) => FakeFilterBuilder<dynamic>(null));

    await repo.updateMySalon(
      name: 'New Name',
      description: 'desc',
      city: 'Sfax',
      address: null,
      showPrices: false,
    );

    verify(() => client.rpc('update_my_salon', params: {
          'p_name': 'New Name',
          'p_description': 'desc',
          'p_city': 'Sfax',
          'p_address': null,
          'p_show_prices': false,
        })).called(1);
  });
}
