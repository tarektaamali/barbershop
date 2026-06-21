import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/service.dart';

class ServiceRepository {
  ServiceRepository(this._client);

  final SupabaseClient _client;

  Future<List<Service>> fetchForSalon(String salonId) async {
    final rows = await _client
        .from('services')
        .select()
        .eq('salon_id', salonId)
        .order('created_at');
    return (rows as List)
        .map((r) => Service.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<String> addService({
    required String salonId,
    required String name,
    required int durationMin,
    required double price,
  }) async {
    final id = await _client.rpc('add_service', params: {
      'p_salon_id': salonId,
      'p_name': name,
      'p_duration_min': durationMin,
      'p_price': price,
    });
    return id as String;
  }

  Future<void> updateService({
    required String id,
    required String name,
    required int durationMin,
    required double price,
  }) async {
    await _client.rpc('update_service', params: {
      'p_service_id': id,
      'p_name': name,
      'p_duration_min': durationMin,
      'p_price': price,
    });
  }

  Future<void> setActive(String id, bool active) async {
    await _client.rpc('set_service_active', params: {
      'p_service_id': id,
      'p_active': active,
    });
  }
}

final serviceRepositoryProvider = Provider<ServiceRepository>((ref) {
  return ServiceRepository(ref.watch(supabaseClientProvider));
});

final servicesProvider =
    FutureProvider.family<List<Service>, String>((ref, salonId) async {
  return ref.watch(serviceRepositoryProvider).fetchForSalon(salonId);
});
