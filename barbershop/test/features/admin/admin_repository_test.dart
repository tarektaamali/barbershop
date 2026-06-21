import 'package:barbershop/features/admin/data/admin_repository.dart';
import 'package:barbershop/features/salon/domain/salon.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/fake_postgrest.dart';

class _MockClient extends Mock implements SupabaseClient {}

void main() {
  late _MockClient client;
  late AdminRepository repo;

  setUp(() {
    client = _MockClient();
    repo = AdminRepository(client);
  });

  test('setStatus calls set_salon_status with the db value', () async {
    when(() => client.rpc('set_salon_status', params: any(named: 'params')))
        .thenAnswer((_) => FakeFilterBuilder<dynamic>(null));

    await repo.setStatus('salon-1', SalonStatus.approved);

    verify(() => client.rpc('set_salon_status', params: {
          'p_salon_id': 'salon-1',
          'p_status': 'approved',
        })).called(1);
  });
}
