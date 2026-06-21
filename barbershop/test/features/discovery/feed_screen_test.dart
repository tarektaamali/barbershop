import 'package:barbershop/features/discovery/data/favorites_repository.dart';
import 'package:barbershop/features/discovery/presentation/feed_screen.dart';
import 'package:barbershop/features/salon/data/salon_repository.dart';
import 'package:barbershop/features/salon/domain/salon.dart';
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
  ratingAvg: 4.5,
  ratingCount: 3,
);

void main() {
  testWidgets('shows a salon card with name and book button', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          approvedSalonsProvider.overrideWith((ref) async => const [_salon]),
          favoriteSalonIdsProvider.overrideWith((ref) async => <String>{}),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: [Locale('fr')],
          home: Scaffold(body: FeedScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Barber House'), findsOneWidget);
    expect(find.text('Réserver'), findsOneWidget);
    expect(find.byKey(const Key('feedSearch')), findsOneWidget);
  });
}
