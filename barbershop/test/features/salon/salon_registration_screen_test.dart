import 'package:barbershop/features/salon/data/salon_repository.dart';
import 'package:barbershop/features/salon/presentation/salon_registration_screen.dart';
import 'package:barbershop/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockSalonRepository extends Mock implements SalonRepository {}

void main() {
  testWidgets('submitting calls registerSalon with name and city',
      (tester) async {
    final repo = _MockSalonRepository();
    when(() => repo.registerSalon(
          name: any(named: 'name'),
          city: any(named: 'city'),
          description: any(named: 'description'),
          address: any(named: 'address'),
        )).thenAnswer((_) async => 'id');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [salonRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: [Locale('fr')],
          home: SalonRegistrationScreen(),
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('salonName')), 'Barber House');
    await tester.enterText(find.byKey(const Key('salonCity')), 'Tunis');
    await tester.tap(find.text('Envoyer'));
    await tester.pump();

    verify(() => repo.registerSalon(
          name: 'Barber House',
          city: 'Tunis',
          description: null,
          address: null,
        )).called(1);
  });
}
