import 'package:barbershop/features/admin/data/admin_repository.dart';
import 'package:barbershop/features/admin/presentation/admin_approvals_screen.dart';
import 'package:barbershop/features/salon/domain/salon.dart';
import 'package:barbershop/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockAdminRepository extends Mock implements AdminRepository {}

void main() {
  setUpAll(() => registerFallbackValue(SalonStatus.approved));

  testWidgets('tapping Valider approves the salon', (tester) async {
    final repo = _MockAdminRepository();
    when(() => repo.setStatus(any(), any())).thenAnswer((_) async {});

    const salon = Salon(
      id: 's1',
      ownerId: 'u1',
      name: 'Barber House',
      city: 'Tunis',
      status: SalonStatus.pending,
      showPrices: true,
      ratingAvg: 0,
      ratingCount: 0,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminRepositoryProvider.overrideWithValue(repo),
          pendingSalonsProvider.overrideWith((ref) async => [salon]),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: [Locale('fr')],
          home: AdminApprovalsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Valider'));
    await tester.pump();

    verify(() => repo.setStatus('s1', SalonStatus.approved)).called(1);
  });
}
