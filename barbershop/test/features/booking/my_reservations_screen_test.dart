import 'package:barbershop/features/booking/data/booking_repository.dart';
import 'package:barbershop/features/booking/domain/booking.dart';
import 'package:barbershop/features/booking/presentation/my_reservations_screen.dart';
import 'package:barbershop/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _booking = Booking(
  id: 'b1',
  salonId: 's1',
  serviceName: 'Coupe homme',
  date: '2026-06-22',
  startTime: '09:00:00',
  endTime: '09:30:00',
  status: BookingStatus.pending,
  priceDefault: 25,
);

void main() {
  testWidgets('lists a reservation with a localized status', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myBookingsProvider.overrideWith((ref) async => const [_booking]),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: [Locale('fr')],
          home: MyReservationsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Coupe homme'), findsOneWidget);
    expect(find.text('En attente'), findsOneWidget);
    expect(find.text('Annuler'), findsOneWidget);
  });
}
