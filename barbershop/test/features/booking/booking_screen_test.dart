import 'package:barbershop/features/booking/presentation/booking_screen.dart';
import 'package:barbershop/features/salon/data/service_repository.dart';
import 'package:barbershop/features/salon/data/staff_repository.dart';
import 'package:barbershop/features/salon/domain/service.dart';
import 'package:barbershop/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the service picker and slot heading', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          servicesProvider('s1').overrideWith((ref) async => const [
                Service(
                  id: 'sv1',
                  salonId: 's1',
                  name: 'Coupe homme',
                  durationMin: 30,
                  price: 25,
                  active: true,
                ),
              ]),
          staffProvider('s1').overrideWith((ref) async => []),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: [Locale('fr')],
          home: BookingScreen(salonId: 's1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('servicePicker')), findsOneWidget);
    expect(find.text('Créneau'), findsOneWidget);
  });
}
