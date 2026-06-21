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

  Future<List<Salon>> fetchApproved() async {
    final rows = await _client
        .from('salons')
        .select()
        .eq('status', 'approved')
        .order('rating_avg', ascending: false);
    return (rows as List)
        .map((r) => Salon.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<Salon?> fetchApprovedById(String id) async {
    final row = await _client
        .from('salons')
        .select()
        .eq('id', id)
        .eq('status', 'approved')
        .maybeSingle();
    if (row == null) return null;
    return Salon.fromMap(row);
  }

  Future<void> setCover(String url) async {
    await _client.rpc('set_salon_cover', params: {'p_cover_url': url});
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

/// All approved salons, highest-rated first (the customer feed).
final approvedSalonsProvider = FutureProvider<List<Salon>>((ref) async {
  return ref.watch(salonRepositoryProvider).fetchApproved();
});

/// A single approved salon by id (the salon profile screen).
final approvedSalonByIdProvider =
    FutureProvider.family<Salon?, String>((ref, id) async {
  return ref.watch(salonRepositoryProvider).fetchApprovedById(id);
});
