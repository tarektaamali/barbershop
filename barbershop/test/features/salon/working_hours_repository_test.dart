import 'package:barbershop/features/salon/data/working_hours_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/fake_postgrest.dart';

class _MockClient extends Mock implements SupabaseClient {}

void main() {
  late _MockClient client;
  late WorkingHoursRepository repo;

  setUp(() {
    client = _MockClient();
    repo = WorkingHoursRepository(client);
  });

  test('addRange calls add_working_hours RPC and returns the id', () async {
    when(() => client.rpc('add_working_hours', params: any(named: 'params')))
        .thenAnswer((_) => FakeFilterBuilder<dynamic>('wh1'));

    final id = await repo.addRange(
      staffId: 'st1',
      weekday: 1,
      start: '09:00',
      end: '12:00',
    );

    expect(id, 'wh1');
    verify(() => client.rpc('add_working_hours', params: {
          'p_staff_id': 'st1',
          'p_weekday': 1,
          'p_start': '09:00',
          'p_end': '12:00',
        })).called(1);
  });

  test('deleteRange calls delete_working_hours RPC', () async {
    when(() => client.rpc('delete_working_hours', params: any(named: 'params')))
        .thenAnswer((_) => FakeFilterBuilder<dynamic>(null));

    await repo.deleteRange('wh1');

    verify(() => client.rpc('delete_working_hours', params: {
          'p_hours_id': 'wh1',
        })).called(1);
  });
}
