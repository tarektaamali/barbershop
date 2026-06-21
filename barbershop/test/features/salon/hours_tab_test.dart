import 'package:barbershop/features/salon/data/staff_repository.dart';
import 'package:barbershop/features/salon/data/working_hours_repository.dart';
import 'package:barbershop/features/salon/domain/staff.dart';
import 'package:barbershop/features/salon/domain/working_hours.dart';
import 'package:barbershop/features/salon/presentation/hours_tab.dart';
import 'package:barbershop/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(List<Staff> staff, List<WorkingHours> hours) => ProviderScope(
      overrides: [
        staffProvider('s1').overrideWith((ref) async => staff),
        workingHoursProvider('st1').overrideWith((ref) async => hours),
      ],
      child: const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [Locale('fr')],
        home: Scaffold(body: HoursTab(salonId: 's1')),
      ),
    );

const _karim = Staff(
  id: 'st1',
  salonId: 's1',
  displayName: 'Karim',
  specialty: 'Dégradé',
  active: true,
);

void main() {
  testWidgets('with no staff shows the add-staff hint', (tester) async {
    await tester.pumpWidget(_wrap(const [], const []));
    await tester.pumpAndSettle();
    expect(find.text("Ajoutez d'abord un coiffeur"), findsOneWidget);
  });

  testWidgets('shows a configured range for the selected staff',
      (tester) async {
    await tester.pumpWidget(_wrap(const [_karim], const [
      WorkingHours(
        id: 'wh1',
        staffId: 'st1',
        weekday: 1,
        startTime: '09:00:00',
        endTime: '12:00:00',
      ),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('Lundi'), findsOneWidget);
    expect(find.text('09:00 – 12:00'), findsOneWidget);
  });
}
