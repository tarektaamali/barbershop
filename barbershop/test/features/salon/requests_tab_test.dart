import 'package:barbershop/features/booking/data/booking_repository.dart';
import 'package:barbershop/features/booking/domain/booking.dart';
import 'package:barbershop/features/salon/presentation/requests_tab.dart';
import 'package:barbershop/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

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
  testWidgets('confirming a request calls confirm', (tester) async {
    final repo = _MockBookingRepository();
    when(() => repo.confirm(any(), staffId: any(named: 'staffId')))
        .thenAnswer((_) async {});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookingRepositoryProvider.overrideWithValue(repo),
          pendingBookingsProvider('s1')
              .overrideWith((ref) async => const [_booking]),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: [Locale('fr')],
          home: Scaffold(body: RequestsTab(salonId: 's1')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Coupe homme'), findsOneWidget);
    await tester.tap(find.text('Confirmer'));
    await tester.pump();

    verify(() => repo.confirm('b1')).called(1);
  });
}
