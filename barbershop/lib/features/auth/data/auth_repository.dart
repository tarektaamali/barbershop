import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/app_user.dart';

class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signUpWithEmail({
    required String email,
    required String password,
    String? fullName,
  }) async {
    await _client.auth.signUp(
      email: email,
      password: password,
      data: fullName == null ? null : {'full_name': fullName},
    );
  }

  Future<void> signInWithGoogle() async {
    await _client.auth.signInWithOAuth(OAuthProvider.google);
  }

  Future<void> signOut() => _client.auth.signOut();

  Stream<AuthState> authStateChanges() => _client.auth.onAuthStateChange;

  String? get currentUserId => _client.auth.currentUser?.id;

  Future<AppUser?> fetchProfile(String userId) async {
    final row = await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
    if (row == null) return null;
    return AppUser.fromMap(row);
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});

final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

/// Resolves the signed-in user's profile (role-bearing). Recomputes whenever
/// the auth state changes.
final currentProfileProvider = FutureProvider<AppUser?>((ref) async {
  ref.watch(authStateChangesProvider);
  final repo = ref.watch(authRepositoryProvider);
  final id = repo.currentUserId;
  if (id == null) return null;
  return repo.fetchProfile(id);
});
