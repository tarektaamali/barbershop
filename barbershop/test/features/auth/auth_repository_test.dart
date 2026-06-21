import 'package:barbershop/features/auth/data/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockClient extends Mock implements SupabaseClient {}

class _MockAuth extends Mock implements GoTrueClient {}

void main() {
  late _MockClient client;
  late _MockAuth auth;
  late AuthRepository repo;

  setUp(() {
    client = _MockClient();
    auth = _MockAuth();
    when(() => client.auth).thenReturn(auth);
    repo = AuthRepository(client);
  });

  test('signInWithEmail delegates to Supabase auth', () async {
    when(
      () => auth.signInWithPassword(
        email: any(named: 'email'),
        password: any(named: 'password'),
      ),
    ).thenAnswer((_) async => AuthResponse());

    await repo.signInWithEmail(email: 'a@b.dev', password: 'secret');

    verify(
      () => auth.signInWithPassword(email: 'a@b.dev', password: 'secret'),
    ).called(1);
  });

  test('signUpWithEmail passes full_name in metadata', () async {
    when(
      () => auth.signUp(
        email: any(named: 'email'),
        password: any(named: 'password'),
        data: any(named: 'data'),
      ),
    ).thenAnswer((_) async => AuthResponse());

    await repo.signUpWithEmail(
      email: 'a@b.dev',
      password: 'secret',
      fullName: 'Tarek',
    );

    verify(
      () => auth.signUp(
        email: 'a@b.dev',
        password: 'secret',
        data: {'full_name': 'Tarek'},
      ),
    ).called(1);
  });

  test('currentUserId returns null when signed out', () {
    when(() => auth.currentUser).thenReturn(null);
    expect(repo.currentUserId, isNull);
  });
}
