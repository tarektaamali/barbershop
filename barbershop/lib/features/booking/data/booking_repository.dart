import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/booking.dart';

class BookingRepository {
  BookingRepository(this._client);

  final SupabaseClient _client;

  Future<String> requestBooking({
    required String salonId,
    required String serviceId,
    required String date,
    required String startTime,
    String? staffId,
  }) async {
    final id = await _client.rpc('request_booking', params: {
      'p_salon_id': salonId,
      'p_service_id': serviceId,
      'p_date': date,
      'p_start_time': startTime,
      'p_staff_id': staffId,
    });
    return id as String;
  }

  Future<void> confirm(String bookingId, {String? staffId}) async {
    await _client.rpc('confirm_booking', params: {
      'p_booking_id': bookingId,
      'p_staff_id': staffId,
    });
  }

  Future<void> decline(String bookingId) async {
    await _client.rpc('decline_booking', params: {
      'p_booking_id': bookingId,
    });
  }

  Future<void> cancel(String bookingId) async {
    await _client.rpc('cancel_booking', params: {
      'p_booking_id': bookingId,
    });
  }

  Future<List<Booking>> fetchMine(String customerId) async {
    final rows = await _client
        .from('bookings')
        .select()
        .eq('customer_id', customerId)
        .order('date', ascending: false);
    return (rows as List)
        .map((r) => Booking.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<Booking>> fetchPendingForSalon(String salonId) async {
    final rows = await _client
        .from('bookings')
        .select()
        .eq('salon_id', salonId)
        .eq('status', 'pending')
        .order('date');
    return (rows as List)
        .map((r) => Booking.fromMap(r as Map<String, dynamic>))
        .toList();
  }
}

final bookingRepositoryProvider = Provider<BookingRepository>((ref) {
  return BookingRepository(ref.watch(supabaseClientProvider));
});

final myBookingsProvider = FutureProvider<List<Booking>>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile == null) return [];
  return ref.watch(bookingRepositoryProvider).fetchMine(profile.id);
});

final pendingBookingsProvider =
    FutureProvider.family<List<Booking>, String>((ref, salonId) async {
  return ref.watch(bookingRepositoryProvider).fetchPendingForSalon(salonId);
});
