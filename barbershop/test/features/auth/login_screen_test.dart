import 'package:barbershop/features/auth/data/auth_repository.dart';
import 'package:barbershop/features/auth/presentation/login_screen.dart';
import 'package:barbershop/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  testWidgets('tapping Se connecter calls signInWithEmail', (tester) async {
    final repo = _MockAuthRepository();
    when(() => repo.signInWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
        )).thenAnswer((_) async {});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: [Locale('fr')],
          home: LoginScreen(),
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('email')), 'a@b.dev');
    await tester.enterText(find.byKey(const Key('password')), 'secret');
    await tester.tap(find.text('Se connecter'));
    await tester.pump();

    verify(() => repo.signInWithEmail(email: 'a@b.dev', password: 'secret'))
        .called(1);
  });
}
