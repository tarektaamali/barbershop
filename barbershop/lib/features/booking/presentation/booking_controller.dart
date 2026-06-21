import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/booking_repository.dart';

class BookingController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> requestSlot({
    required String salonId,
    required String serviceId,
    required String date,
    required String startTime,
    String? staffId,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(bookingRepositoryProvider).requestBooking(
            salonId: salonId,
            serviceId: serviceId,
            date: date,
            startTime: startTime,
            staffId: staffId,
          ),
    );
  }
}

final bookingControllerProvider =
    AsyncNotifierProvider<BookingController, void>(BookingController.new);
