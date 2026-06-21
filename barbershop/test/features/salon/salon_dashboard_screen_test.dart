import 'package:barbershop/features/salon/data/salon_repository.dart';
import 'package:barbershop/features/salon/domain/salon.dart';
import 'package:barbershop/features/salon/presentation/salon_dashboard_screen.dart';
import 'package:barbershop/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Salon _salon(SalonStatus status) => Salon(
      id: 's1',
      ownerId: 'u1',
      name: 'Barber House',
      city: 'Tunis',
      status: status,
      showPrices: true,
      ratingAvg: 0,
      ratingCount: 0,
    );

Widget _dashboard(SalonStatus status) => ProviderScope(
      overrides: [
        mySalonProvider.overrideWith((ref) async => _salon(status)),
      ],
      child: const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [Locale('fr')],
        home: SalonDashboardScreen(),
      ),
    );

void main() {
  testWidgets('pending salon shows the pending banner', (tester) async {
    await tester.pumpWidget(_dashboard(SalonStatus.pending));
    await tester.pumpAndSettle();
    expect(find.text('En attente de validation'), findsOneWidget);
  });

  testWidgets('approved salon shows the editable profile form',
      (tester) async {
    await tester.pumpWidget(_dashboard(SalonStatus.approved));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profileName')), findsOneWidget);
    expect(find.byKey(const Key('showPricesSwitch')), findsOneWidget);
  });
}
