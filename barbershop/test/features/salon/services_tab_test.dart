import 'package:barbershop/features/salon/data/service_repository.dart';
import 'package:barbershop/features/salon/domain/service.dart';
import 'package:barbershop/features/salon/presentation/services_tab.dart';
import 'package:barbershop/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(List<Service> services) => ProviderScope(
      overrides: [
        servicesProvider('s1').overrideWith((ref) async => services),
      ],
      child: const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [Locale('fr')],
        home: ServicesTab(salonId: 's1'),
      ),
    );

void main() {
  testWidgets('renders a service row', (tester) async {
    await tester.pumpWidget(_wrap(const [
      Service(
        id: 'sv1',
        salonId: 's1',
        name: 'Coupe homme',
        durationMin: 30,
        price: 25,
        active: true,
      ),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('Coupe homme'), findsOneWidget);
    expect(find.textContaining('30'), findsWidgets);
  });

  testWidgets('empty state shows no-services message', (tester) async {
    await tester.pumpWidget(_wrap(const []));
    await tester.pumpAndSettle();
    expect(find.text('Aucun service'), findsOneWidget);
  });
}
