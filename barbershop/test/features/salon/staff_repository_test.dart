import 'package:barbershop/features/salon/data/staff_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/fake_postgrest.dart';

class _MockClient extends Mock implements SupabaseClient {}

void main() {
  late _MockClient client;
  late StaffRepository repo;

  setUp(() {
    client = _MockClient();
    repo = StaffRepository(client);
  });

  test('addStaff calls add_staff RPC and returns the id', () async {
    when(() => client.rpc('add_staff', params: any(named: 'params')))
        .thenAnswer((_) => FakeFilterBuilder<dynamic>('st1'));

    final id = await repo.addStaff(
      salonId: 's1',
      displayName: 'Karim',
      specialty: 'Dégradé',
    );

    expect(id, 'st1');
    verify(() => client.rpc('add_staff', params: {
          'p_salon_id': 's1',
          'p_display_name': 'Karim',
          'p_specialty': 'Dégradé',
        })).called(1);
  });

  test('setActive calls set_staff_active RPC', () async {
    when(() => client.rpc('set_staff_active', params: any(named: 'params')))
        .thenAnswer((_) => FakeFilterBuilder<dynamic>(null));

    await repo.setActive('st1', false);

    verify(() => client.rpc('set_staff_active', params: {
          'p_staff_id': 'st1',
          'p_active': false,
        })).called(1);
  });
}
