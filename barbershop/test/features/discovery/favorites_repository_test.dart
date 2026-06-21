import 'package:barbershop/features/discovery/data/favorites_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/fake_postgrest.dart';

class _MockClient extends Mock implements SupabaseClient {}

void main() {
  late _MockClient client;
  late FavoritesRepository repo;

  setUp(() {
    client = _MockClient();
    repo = FavoritesRepository(client);
  });

  test('toggle calls toggle_favorite RPC and returns the new state', () async {
    when(() => client.rpc('toggle_favorite', params: any(named: 'params')))
        .thenAnswer((_) => FakeFilterBuilder<dynamic>(true));

    final favorited = await repo.toggle('s1');

    expect(favorited, true);
    verify(() => client.rpc('toggle_favorite', params: {
          'p_salon_id': 's1',
        })).called(1);
  });
}
