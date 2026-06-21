import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../data/salon_repository.dart';

class SalonRegistrationController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> submit({
    required String name,
    required String city,
    String? description,
    String? address,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(salonRepositoryProvider).registerSalon(
            name: name,
            city: city,
            description: description,
            address: address,
          );
      // Role changed to salon_owner and a salon now exists — refresh both so
      // the router redirects to the salon dashboard.
      ref.invalidate(currentProfileProvider);
      ref.invalidate(mySalonProvider);
    });
  }
}

final salonRegistrationControllerProvider =
    AsyncNotifierProvider<SalonRegistrationController, void>(
  SalonRegistrationController.new,
);
