import 'package:barbershop/features/salon/data/staff_repository.dart';
import 'package:barbershop/features/salon/domain/staff.dart';
import 'package:barbershop/features/salon/presentation/staff_tab.dart';
import 'package:barbershop/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(List<Staff> staff) => ProviderScope(
      overrides: [
        staffProvider('s1').overrideWith((ref) async => staff),
      ],
      child: const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [Locale('fr')],
        home: StaffTab(salonId: 's1'),
      ),
    );

void main() {
  testWidgets('renders a staff row', (tester) async {
    await tester.pumpWidget(_wrap(const [
      Staff(
        id: 'st1',
        salonId: 's1',
        displayName: 'Karim',
        specialty: 'Dégradé',
        active: true,
      ),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('Karim'), findsOneWidget);
    expect(find.text('Dégradé'), findsOneWidget);
  });

  testWidgets('empty state shows no-staff message', (tester) async {
    await tester.pumpWidget(_wrap(const []));
    await tester.pumpAndSettle();
    expect(find.text('Aucun coiffeur'), findsOneWidget);
  });
}
