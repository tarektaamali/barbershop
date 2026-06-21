import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';

class FavoritesRepository {
  FavoritesRepository(this._client);

  final SupabaseClient _client;

  Future<bool> toggle(String salonId) async {
    final result = await _client.rpc('toggle_favorite', params: {
      'p_salon_id': salonId,
    });
    return result as bool;
  }

  Future<Set<String>> fetchMyIds() async {
    final rows = await _client.from('favorites').select('salon_id');
    return (rows as List)
        .map((r) => (r as Map<String, dynamic>)['salon_id'] as String)
        .toSet();
  }
}

final favoritesRepositoryProvider = Provider<FavoritesRepository>((ref) {
  return FavoritesRepository(ref.watch(supabaseClientProvider));
});

final favoriteSalonIdsProvider = FutureProvider<Set<String>>((ref) async {
  return ref.watch(favoritesRepositoryProvider).fetchMyIds();
});
