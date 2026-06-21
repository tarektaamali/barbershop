import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/working_hours.dart';

class WorkingHoursRepository {
  WorkingHoursRepository(this._client);

  final SupabaseClient _client;

  Future<List<WorkingHours>> fetchForStaff(String staffId) async {
    final rows = await _client
        .from('working_hours')
        .select()
        .eq('staff_id', staffId)
        .order('weekday');
    return (rows as List)
        .map((r) => WorkingHours.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<String> addRange({
    required String staffId,
    required int weekday,
    required String start,
    required String end,
  }) async {
    final id = await _client.rpc('add_working_hours', params: {
      'p_staff_id': staffId,
      'p_weekday': weekday,
      'p_start': start,
      'p_end': end,
    });
    return id as String;
  }

  Future<void> deleteRange(String hoursId) async {
    await _client.rpc('delete_working_hours', params: {
      'p_hours_id': hoursId,
    });
  }
}

final workingHoursRepositoryProvider =
    Provider<WorkingHoursRepository>((ref) {
  return WorkingHoursRepository(ref.watch(supabaseClientProvider));
});

final workingHoursProvider =
    FutureProvider.family<List<WorkingHours>, String>((ref, staffId) async {
  return ref.watch(workingHoursRepositoryProvider).fetchForStaff(staffId);
});
