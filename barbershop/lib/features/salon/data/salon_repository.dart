import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/salon.dart';

class SalonRepository {
  SalonRepository(this._client);

  final SupabaseClient _client;

  Future<String> registerSalon({
    required String name,
    required String city,
    String? description,
    String? address,
  }) async {
    final id = await _client.rpc('register_salon', params: {
      'p_name': name,
      'p_city': city,
      'p_description': description,
      'p_address': address,
    });
    return id as String;
  }

  Future<Salon?> fetchMySalon(String ownerId) async {
    final row = await _client
        .from('salons')
        .select()
        .eq('owner_id', ownerId)
        .maybeSingle();
    if (row == null) return null;
    return Salon.fromMap(row);
  }

  Future<void> updateMySalon({
    required String name,
    required String? description,
    required String city,
    required String? address,
    required bool showPrices,
  }) async {
    await _client.rpc('update_my_salon', params: {
      'p_name': name,
      'p_description': description,
      'p_city': city,
      'p_address': address,
      'p_show_prices': showPrices,
    });
  }
}

final salonRepositoryProvider = Provider<SalonRepository>((ref) {
  return SalonRepository(ref.watch(supabaseClientProvider));
});

/// The current user's salon (if they own one). Recomputes when the profile
/// changes (e.g. right after registration elevates them to salon_owner).
final mySalonProvider = FutureProvider<Salon?>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile == null) return null;
  return ref.watch(salonRepositoryProvider).fetchMySalon(profile.id);
});
