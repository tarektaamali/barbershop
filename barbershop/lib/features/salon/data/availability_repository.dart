import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';

class AvailabilityRepository {
  AvailabilityRepository(this._client);

  final SupabaseClient _client;

  Future<List<String>> availableSlots({
    required String salonId,
    required String serviceId,
    required String date,
    String? staffId,
  }) async {
    final rows = await _client.rpc('available_slots', params: {
      'p_salon_id': salonId,
      'p_service_id': serviceId,
      'p_date': date,
      'p_staff_id': staffId,
    });
    return (rows as List)
        .map((t) => (t as String).substring(0, 5))
        .toList();
  }
}

final availabilityRepositoryProvider =
    Provider<AvailabilityRepository>((ref) {
  return AvailabilityRepository(ref.watch(supabaseClientProvider));
});
