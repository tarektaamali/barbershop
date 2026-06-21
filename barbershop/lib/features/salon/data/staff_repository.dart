import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/staff.dart';

class StaffRepository {
  StaffRepository(this._client);

  final SupabaseClient _client;

  Future<List<Staff>> fetchForSalon(String salonId) async {
    final rows = await _client
        .from('staff')
        .select()
        .eq('salon_id', salonId)
        .order('created_at');
    return (rows as List)
        .map((r) => Staff.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<String> addStaff({
    required String salonId,
    required String displayName,
    String? specialty,
  }) async {
    final id = await _client.rpc('add_staff', params: {
      'p_salon_id': salonId,
      'p_display_name': displayName,
      'p_specialty': specialty,
    });
    return id as String;
  }

  Future<void> updateStaff({
    required String id,
    required String displayName,
    String? specialty,
  }) async {
    await _client.rpc('update_staff', params: {
      'p_staff_id': id,
      'p_display_name': displayName,
      'p_specialty': specialty,
    });
  }

  Future<void> setActive(String id, bool active) async {
    await _client.rpc('set_staff_active', params: {
      'p_staff_id': id,
      'p_active': active,
    });
  }
}

final staffRepositoryProvider = Provider<StaffRepository>((ref) {
  return StaffRepository(ref.watch(supabaseClientProvider));
});

final staffProvider =
    FutureProvider.family<List<Staff>, String>((ref, salonId) async {
  return ref.watch(staffRepositoryProvider).fetchForSalon(salonId);
});
