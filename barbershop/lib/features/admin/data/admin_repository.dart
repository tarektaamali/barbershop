import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../salon/domain/salon.dart';

class AdminRepository {
  AdminRepository(this._client);

  final SupabaseClient _client;

  Future<List<Salon>> fetchPendingSalons() async {
    final rows = await _client
        .from('salons')
        .select()
        .eq('status', 'pending')
        .order('created_at');
    return (rows as List)
        .map((r) => Salon.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> setStatus(String salonId, SalonStatus status) async {
    await _client.rpc('set_salon_status', params: {
      'p_salon_id': salonId,
      'p_status': status.dbValue,
    });
  }
}

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AdminRepository(ref.watch(supabaseClientProvider));
});

final pendingSalonsProvider = FutureProvider<List<Salon>>((ref) async {
  return ref.watch(adminRepositoryProvider).fetchPendingSalons();
});
