import 'package:barbershop/features/salon/data/service_repository.dart';
import 'package:barbershop/features/salon/data/staff_repository.dart';
import 'package:barbershop/features/salon/domain/salon.dart';
import 'package:barbershop/features/salon/presentation/salon_manage_tabs.dart';
import 'package:barbershop/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _salon = Salon(
  id: 's1',
  ownerId: 'u1',
  name: 'Barber House',
  city: 'Tunis',
  status: SalonStatus.approved,
  showPrices: true,
  ratingAvg: 0,
  ratingCount: 0,
);

void main() {
  testWidgets('shows the three management tabs', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          servicesProvider('s1').overrideWith((ref) async => []),
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
          home: Scaffold(body: SalonManageTabs(salon: _salon)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Profil'), findsOneWidget);
    expect(find.text('Services'), findsOneWidget);
    expect(find.text('Équipe'), findsOneWidget);
  });
}
