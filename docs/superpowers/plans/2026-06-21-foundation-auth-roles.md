# Foundation — Auth & Roles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the Flutter + Supabase project so a user can sign up / log in (email or Google) and land on a role-appropriate home screen, with the `profiles` table secured by Row-Level Security.

**Architecture:** Single Flutter codebase (web-first in dev), feature-first folders. Riverpod for dependency injection and state, go_router for navigation with an auth-aware redirect. Supabase provides Auth, Postgres, and RLS. A `profiles` row (1:1 with `auth.users`) carries the `role` that drives which home screen is shown.

**Tech Stack:** Flutter (stable), Dart 3.9+, `supabase_flutter` v2, `flutter_riverpod` v2, `go_router` v14, `mocktail` (tests), Supabase CLI + Docker (local DB + pgTAP RLS tests).

## Global Constraints

- **Frontend:** Flutter, single codebase, web-first during development (`flutter run -d chrome`). Target Android/iOS later.
- **Backend:** Supabase — Postgres, Auth (email + Google), RLS. Trusted logic in Edge Functions (not in this plan).
- **Localization:** All user-facing strings come from ARB files (`intl`); **no hardcoded UI text**. French (`fr`) only for now, structured for more languages later.
- **Roles:** `profiles.role` ∈ {`customer`, `salon_owner`, `staff`, `admin`}. Default for self-signup is `customer`.
- **Security:** RLS enabled on every table; a user may read/write only their own `profiles` row (admin excepted, handled in a later plan).
- **TDD:** Write the failing test first for every behavior. Commit after each green step.
- **State/DI:** Use Riverpod providers; no global singletons except `Supabase.instance`.

---

## File Structure

```
barbershop/
├── pubspec.yaml                  # deps + flutter l10n config
├── analysis_options.yaml         # lints
├── l10n.yaml                     # localization generator config
├── lib/
│   ├── main.dart                 # bootstrap: init Supabase, run ProviderScope(App)
│   ├── app.dart                  # MaterialApp.router + theme + localizations
│   ├── core/
│   │   ├── config/env.dart       # reads --dart-define env values
│   │   ├── supabase/supabase_providers.dart  # supabaseClientProvider
│   │   ├── theme/app_theme.dart  # ThemeData
│   │   └── router/app_router.dart            # goRouterProvider + redirect
│   ├── l10n/
│   │   └── app_fr.arb            # French strings (source of truth)
│   └── features/
│       ├── auth/
│       │   ├── domain/app_user.dart          # UserRole enum + AppUser model
│       │   ├── data/auth_repository.dart      # AuthRepository + provider
│       │   └── presentation/
│       │       ├── auth_controller.dart       # AsyncNotifier for sign in/up/out
│       │       ├── login_screen.dart
│       │       └── signup_screen.dart
│       └── home/
│           └── presentation/
│               ├── customer_home_screen.dart
│               ├── salon_home_screen.dart
│               └── admin_home_screen.dart
├── test/
│   ├── features/auth/app_user_test.dart
│   ├── features/auth/auth_repository_test.dart
│   └── features/auth/role_routing_test.dart
└── supabase/
    ├── config.toml               # created by `supabase init`
    ├── migrations/
    │   └── 0001_profiles.sql
    └── tests/
        └── profiles_rls_test.sql # pgTAP
```

---

## Prerequisites (one-time setup — verify before Task 1)

- [ ] **Step 1: Install Flutter SDK** (Dart 3.9 is present, but `flutter` is not on PATH).

Run:
```bash
brew install --cask flutter || echo "If brew cask unavailable, follow https://docs.flutter.dev/get-started/install/macos"
flutter --version
```
Expected: prints a Flutter 3.x version. If it errors, install manually and re-run.

- [ ] **Step 2: Enable Flutter web and accept tooling.**

Run:
```bash
flutter config --enable-web
flutter doctor
```
Expected: `flutter doctor` shows Chrome (web) available; other checkmarks may be incomplete (Android/iOS not needed yet).

- [ ] **Step 3: Install the Supabase CLI** (Docker 28 is already present).

Run:
```bash
brew install supabase/tap/supabase
supabase --version
```
Expected: prints a version (e.g. `2.x`).

---

## Task 1: Scaffold the Flutter project with dependencies and lints

**Files:**
- Create: `barbershop/` (Flutter project), `pubspec.yaml`, `analysis_options.yaml`
- Test: `barbershop/test/smoke_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: a buildable Flutter project at repo root `barbershop/` with `flutter_riverpod`, `supabase_flutter`, `go_router`, `intl`, `mocktail` available; `flutter test` runs.

- [ ] **Step 1: Create the Flutter app in place.**

Run (from `/Users/macbook/Desktop/DEVCAMP`):
```bash
flutter create --org com.barbershop --platforms web,android,ios --project-name barbershop barbershop
```
Expected: creates `barbershop/` with `lib/main.dart` and `test/widget_test.dart`.

- [ ] **Step 2: Add dependencies.**

Run:
```bash
cd barbershop
flutter pub add flutter_riverpod supabase_flutter go_router intl
flutter pub add dev:mocktail
flutter pub get
```
Expected: `pubspec.yaml` lists the packages; `pub get` succeeds.

- [ ] **Step 3: Enable strict lints.** Replace `barbershop/analysis_options.yaml` with:

```yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  language:
    strict-casts: true
    strict-raw-types: true
  errors:
    invalid_annotation_target: ignore

linter:
  rules:
    prefer_const_constructors: true
    require_trailing_commas: true
    avoid_print: true
```

- [ ] **Step 4: Remove the default counter widget test and add a smoke test.** Delete `barbershop/test/widget_test.dart`, then create `barbershop/test/smoke_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('toolchain runs tests', () {
    expect(1 + 1, 2);
  });
}
```

- [ ] **Step 5: Run analyzer and tests.**

Run:
```bash
flutter analyze
flutter test
```
Expected: analyzer reports no errors (the default `lib/main.dart` still compiles); `smoke_test.dart` passes.

- [ ] **Step 6: Commit.**

```bash
cd /Users/macbook/Desktop/DEVCAMP
git add barbershop/.gitignore barbershop/pubspec.yaml barbershop/pubspec.lock barbershop/analysis_options.yaml barbershop/lib barbershop/test barbershop/web
git commit -m "chore: scaffold Flutter project with core dependencies"
```

---

## Task 2: Profiles table, role enum, and RLS (with pgTAP tests)

**Files:**
- Create: `supabase/config.toml` (via `supabase init`), `supabase/migrations/0001_profiles.sql`, `supabase/tests/profiles_rls_test.sql`

**Interfaces:**
- Consumes: nothing.
- Produces: a `profiles` table with columns `id uuid` (PK, FK→`auth.users`), `role user_role`, `full_name text`, `phone text`, `avatar_url text`, `language text`, `fcm_token text`, `created_at timestamptz`; an `auth.users` insert trigger that creates a default `customer` profile; RLS allowing a user to select/update only their own row.

- [ ] **Step 1: Initialize Supabase locally.**

Run (from `/Users/macbook/Desktop/DEVCAMP`):
```bash
supabase init
supabase start
```
Expected: `supabase init` creates `supabase/`; `supabase start` boots local stack and prints `API URL`, `anon key`, and `service_role key`. **Record the API URL and anon key** — Task 4 needs them.

- [ ] **Step 2: Write the migration.** Create `supabase/migrations/0001_profiles.sql`:

```sql
-- Roles available in the platform.
create type public.user_role as enum ('customer', 'salon_owner', 'staff', 'admin');

create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  role        public.user_role not null default 'customer',
  full_name   text,
  phone       text,
  avatar_url  text,
  language    text not null default 'fr',
  fcm_token   text,
  created_at  timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- A user can read their own profile.
create policy "profiles_select_own"
  on public.profiles for select
  using (auth.uid() = id);

-- A user can update their own profile, but cannot change their role
-- (role changes happen server-side / by admin in a later plan).
create policy "profiles_update_own"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id and role = (select role from public.profiles where id = auth.uid()));

-- Auto-create a default profile when a new auth user is created.
create function public.handle_new_user()
  returns trigger
  language plpgsql
  security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, new.raw_user_meta_data ->> 'full_name');
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
```

- [ ] **Step 3: Apply the migration.**

Run:
```bash
supabase db reset
```
Expected: resets the local DB and applies `0001_profiles.sql` without error.

- [ ] **Step 4: Write the failing RLS test.** Create `supabase/tests/profiles_rls_test.sql`:

```sql
begin;
select plan(3);

-- Seed two auth users (the trigger creates their profiles).
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.dev'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.dev');

-- Act as user A.
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

-- 1. A sees exactly their own profile.
select is(
  (select count(*)::int from public.profiles),
  1,
  'user A sees only their own profile'
);

-- 2. New profiles default to the customer role.
select is(
  (select role::text from public.profiles where id = '11111111-1111-1111-1111-111111111111'),
  'customer',
  'new profile defaults to customer'
);

-- 3. A cannot read B's row (RLS hides it -> 0 rows).
select is(
  (select count(*)::int from public.profiles where id = '22222222-2222-2222-2222-222222222222'),
  0,
  'user A cannot see user B profile'
);

select * from finish();
rollback;
```

- [ ] **Step 5: Run the RLS test and verify it passes.**

Run:
```bash
supabase test db
```
Expected: `profiles_rls_test.sql` reports `ok 1`, `ok 2`, `ok 3` and a passing summary. (If pgTAP reports the suite missing, ensure the file is under `supabase/tests/`.)

- [ ] **Step 6: Commit.**

```bash
git add supabase/config.toml supabase/migrations/0001_profiles.sql supabase/tests/profiles_rls_test.sql supabase/.gitignore
git commit -m "feat(db): profiles table with role enum, default-customer trigger, and RLS"
```

---

## Task 3: Domain model — UserRole enum and AppUser

**Files:**
- Create: `barbershop/lib/features/auth/domain/app_user.dart`
- Test: `barbershop/test/features/auth/app_user_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum UserRole { customer, salonOwner, staff, admin }` with `UserRole.fromDb(String)` and `String get dbValue`.
  - `class AppUser { final String id; final UserRole role; final String? fullName; final String language; }` with `factory AppUser.fromMap(Map<String, dynamic>)`.

- [ ] **Step 1: Write the failing test.** Create `barbershop/test/features/auth/app_user_test.dart`:

```dart
import 'package:barbershop/features/auth/domain/app_user.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserRole', () {
    test('maps db snake_case to enum', () {
      expect(UserRole.fromDb('salon_owner'), UserRole.salonOwner);
      expect(UserRole.fromDb('customer'), UserRole.customer);
    });

    test('serializes enum back to db value', () {
      expect(UserRole.salonOwner.dbValue, 'salon_owner');
      expect(UserRole.admin.dbValue, 'admin');
    });

    test('unknown role falls back to customer', () {
      expect(UserRole.fromDb('wizard'), UserRole.customer);
    });
  });

  group('AppUser.fromMap', () {
    test('builds from a profiles row', () {
      final user = AppUser.fromMap({
        'id': 'abc',
        'role': 'admin',
        'full_name': 'Tarek',
        'language': 'fr',
      });
      expect(user.id, 'abc');
      expect(user.role, UserRole.admin);
      expect(user.fullName, 'Tarek');
      expect(user.language, 'fr');
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails.**

Run: `cd barbershop && flutter test test/features/auth/app_user_test.dart`
Expected: FAIL — `app_user.dart` does not exist.

- [ ] **Step 3: Implement the model.** Create `barbershop/lib/features/auth/domain/app_user.dart`:

```dart
enum UserRole {
  customer('customer'),
  salonOwner('salon_owner'),
  staff('staff'),
  admin('admin');

  const UserRole(this.dbValue);

  final String dbValue;

  static UserRole fromDb(String value) {
    return UserRole.values.firstWhere(
      (r) => r.dbValue == value,
      orElse: () => UserRole.customer,
    );
  }
}

class AppUser {
  const AppUser({
    required this.id,
    required this.role,
    required this.language,
    this.fullName,
  });

  final String id;
  final UserRole role;
  final String language;
  final String? fullName;

  factory AppUser.fromMap(Map<String, dynamic> map) {
    return AppUser(
      id: map['id'] as String,
      role: UserRole.fromDb(map['role'] as String? ?? 'customer'),
      fullName: map['full_name'] as String?,
      language: map['language'] as String? ?? 'fr',
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes.**

Run: `flutter test test/features/auth/app_user_test.dart`
Expected: PASS (all 4 tests green).

- [ ] **Step 5: Commit.**

```bash
git add barbershop/lib/features/auth/domain/app_user.dart barbershop/test/features/auth/app_user_test.dart
git commit -m "feat(auth): UserRole enum and AppUser model"
```

---

## Task 4: Core config and Supabase providers

**Files:**
- Create: `barbershop/lib/core/config/env.dart`, `barbershop/lib/core/supabase/supabase_providers.dart`

**Interfaces:**
- Consumes: `Supabase.instance` (initialized in Task 11's `main.dart`).
- Produces:
  - `class Env { static const String supabaseUrl; static const String supabaseAnonKey; }` read from `--dart-define`.
  - `final supabaseClientProvider = Provider<SupabaseClient>(...)` returning `Supabase.instance.client`.

- [ ] **Step 1: Create the env reader.** Create `barbershop/lib/core/config/env.dart`:

```dart
/// Compile-time configuration, supplied via --dart-define.
///
/// Example:
///   flutter run -d chrome \
///     --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
///     --dart-define=SUPABASE_ANON_KEY=<local anon key>
class Env {
  const Env._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
```

- [ ] **Step 2: Create the Supabase client provider.** Create `barbershop/lib/core/supabase/supabase_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The initialized Supabase client. `Supabase.initialize` must run in main()
/// before any provider reads this.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});
```

- [ ] **Step 3: Verify it compiles.**

Run: `cd barbershop && flutter analyze lib/core`
Expected: no errors.

- [ ] **Step 4: Commit.**

```bash
git add barbershop/lib/core/config/env.dart barbershop/lib/core/supabase/supabase_providers.dart
git commit -m "feat(core): env config and Supabase client provider"
```

---

## Task 5: AuthRepository (TDD with mocktail)

**Files:**
- Create: `barbershop/lib/features/auth/data/auth_repository.dart`
- Test: `barbershop/test/features/auth/auth_repository_test.dart`

**Interfaces:**
- Consumes: `supabaseClientProvider` (Task 4); `AppUser` (Task 3).
- Produces:
  - `class AuthRepository` with:
    - `Future<void> signInWithEmail({required String email, required String password})`
    - `Future<void> signUpWithEmail({required String email, required String password, String? fullName})`
    - `Future<void> signInWithGoogle()`
    - `Future<void> signOut()`
    - `Stream<AuthState> authStateChanges()`
    - `String? get currentUserId`
    - `Future<AppUser?> fetchProfile(String userId)`
  - `final authRepositoryProvider = Provider<AuthRepository>(...)`
  - `final authStateChangesProvider = StreamProvider<AuthState>(...)`
  - `final currentProfileProvider = FutureProvider<AppUser?>(...)`

- [ ] **Step 1: Write the failing test.** Create `barbershop/test/features/auth/auth_repository_test.dart`:

```dart
import 'package:barbershop/features/auth/data/auth_repository.dart';
import 'package:barbershop/features/auth/domain/app_user.dart';
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
```

- [ ] **Step 2: Run the test to verify it fails.**

Run: `cd barbershop && flutter test test/features/auth/auth_repository_test.dart`
Expected: FAIL — `auth_repository.dart` does not exist.

- [ ] **Step 3: Implement the repository.** Create `barbershop/lib/features/auth/data/auth_repository.dart`:

```dart
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
```

- [ ] **Step 4: Run the test to verify it passes.**

Run: `flutter test test/features/auth/auth_repository_test.dart`
Expected: PASS (3 tests green).

- [ ] **Step 5: Commit.**

```bash
git add barbershop/lib/features/auth/data/auth_repository.dart barbershop/test/features/auth/auth_repository_test.dart
git commit -m "feat(auth): AuthRepository with email/Google auth and profile fetch"
```

---

## Task 6: Localization scaffolding (French)

**Files:**
- Create: `barbershop/l10n.yaml`, `barbershop/lib/l10n/app_fr.arb`
- Modify: `barbershop/pubspec.yaml` (enable `generate: true`, add `flutter_localizations`)

**Interfaces:**
- Consumes: nothing.
- Produces: generated `AppLocalizations` (import `package:flutter_gen/gen_l10n/app_localizations.dart`) exposing: `appTitle`, `loginTitle`, `signupTitle`, `emailLabel`, `passwordLabel`, `fullNameLabel`, `signInButton`, `signUpButton`, `googleButton`, `signOutButton`, `noAccountPrompt`, `haveAccountPrompt`, `customerHomeTitle`, `salonHomeTitle`, `adminHomeTitle`.

- [ ] **Step 1: Add localization deps and enable generation.** In `barbershop/pubspec.yaml`, under `dependencies:` add:

```yaml
  flutter_localizations:
    sdk: flutter
```

and under the `flutter:` section add:

```yaml
  generate: true
```

- [ ] **Step 2: Create `barbershop/l10n.yaml`:**

```yaml
arb-dir: lib/l10n
template-arb-file: app_fr.arb
output-localization-file: app_localizations.dart
```

- [ ] **Step 3: Create the French strings file `barbershop/lib/l10n/app_fr.arb`:**

```json
{
  "@@locale": "fr",
  "appTitle": "Barbershop",
  "loginTitle": "Connexion",
  "signupTitle": "Créer un compte",
  "emailLabel": "E-mail",
  "passwordLabel": "Mot de passe",
  "fullNameLabel": "Nom complet",
  "signInButton": "Se connecter",
  "signUpButton": "S'inscrire",
  "googleButton": "Continuer avec Google",
  "signOutButton": "Se déconnecter",
  "noAccountPrompt": "Pas de compte ? Inscrivez-vous",
  "haveAccountPrompt": "Déjà un compte ? Connectez-vous",
  "customerHomeTitle": "Accueil",
  "salonHomeTitle": "Mon salon",
  "adminHomeTitle": "Administration"
}
```

- [ ] **Step 4: Generate localizations and verify.**

Run:
```bash
cd barbershop && flutter pub get && flutter gen-l10n
```
Expected: generates `.dart_tool/flutter_gen/gen_l10n/app_localizations.dart`; no errors.

- [ ] **Step 5: Commit.**

```bash
git add barbershop/pubspec.yaml barbershop/pubspec.lock barbershop/l10n.yaml barbershop/lib/l10n/app_fr.arb
git commit -m "feat(l10n): French localization scaffolding"
```

---

## Task 7: Theme and placeholder home screens

**Files:**
- Create: `barbershop/lib/core/theme/app_theme.dart`, `barbershop/lib/features/home/presentation/customer_home_screen.dart`, `.../salon_home_screen.dart`, `.../admin_home_screen.dart`

**Interfaces:**
- Consumes: `AppLocalizations` (Task 6); `authRepositoryProvider` (Task 5).
- Produces: `class AppTheme { static ThemeData light(); }`; three `ConsumerWidget` screens `CustomerHomeScreen`, `SalonHomeScreen`, `AdminHomeScreen`, each showing its localized title and a sign-out button.

- [ ] **Step 1: Create the theme.** Create `barbershop/lib/core/theme/app_theme.dart`:

```dart
import 'package:flutter/material.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF22C55E),
      brightness: Brightness.light,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    );
  }
}
```

- [ ] **Step 2: Create the customer home screen.** Create `barbershop/lib/features/home/presentation/customer_home_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';

class CustomerHomeScreen extends ConsumerWidget {
  const CustomerHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.customerHomeTitle),
        actions: [
          IconButton(
            tooltip: l10n.signOutButton,
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
          ),
        ],
      ),
      body: Center(child: Text(l10n.customerHomeTitle)),
    );
  }
}
```

- [ ] **Step 3: Create the salon home screen.** Create `barbershop/lib/features/home/presentation/salon_home_screen.dart` — identical structure, replacing the class name with `SalonHomeScreen` and both `l10n.customerHomeTitle` references with `l10n.salonHomeTitle`.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';

class SalonHomeScreen extends ConsumerWidget {
  const SalonHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.salonHomeTitle),
        actions: [
          IconButton(
            tooltip: l10n.signOutButton,
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
          ),
        ],
      ),
      body: Center(child: Text(l10n.salonHomeTitle)),
    );
  }
}
```

- [ ] **Step 4: Create the admin home screen.** Create `barbershop/lib/features/home/presentation/admin_home_screen.dart` — same as Step 3 but `AdminHomeScreen` and `l10n.adminHomeTitle`.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';

class AdminHomeScreen extends ConsumerWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminHomeTitle),
        actions: [
          IconButton(
            tooltip: l10n.signOutButton,
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
          ),
        ],
      ),
      body: Center(child: Text(l10n.adminHomeTitle)),
    );
  }
}
```

- [ ] **Step 5: Verify compilation.**

Run: `cd barbershop && flutter analyze lib/core/theme lib/features/home`
Expected: no errors.

- [ ] **Step 6: Commit.**

```bash
git add barbershop/lib/core/theme barbershop/lib/features/home
git commit -m "feat(home): theme and per-role placeholder home screens"
```

---

## Task 8: Router with auth-aware, role-based redirect

**Files:**
- Create: `barbershop/lib/core/router/app_router.dart`
- Test: `barbershop/test/features/auth/role_routing_test.dart`

**Interfaces:**
- Consumes: `currentProfileProvider`, `authStateChangesProvider` (Task 5); home screens (Task 7); `LoginScreen`/`SignupScreen` (Task 9, referenced by route name now, created next).
- Produces:
  - A pure helper `String? resolveRedirect({required bool isLoggedIn, required UserRole? role, required String location})` used for routing decisions and unit-tested in isolation.
  - `final goRouterProvider = Provider<GoRouter>(...)`.

- [ ] **Step 1: Write the failing test for the redirect logic.** Create `barbershop/test/features/auth/role_routing_test.dart`:

```dart
import 'package:barbershop/core/router/app_router.dart';
import 'package:barbershop/features/auth/domain/app_user.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveRedirect', () {
    test('logged-out user is sent to /login', () {
      expect(
        resolveRedirect(isLoggedIn: false, role: null, location: '/'),
        '/login',
      );
    });

    test('logged-out user already on /signup stays', () {
      expect(
        resolveRedirect(isLoggedIn: false, role: null, location: '/signup'),
        isNull,
      );
    });

    test('customer landing on /login is routed to /home', () {
      expect(
        resolveRedirect(
          isLoggedIn: true,
          role: UserRole.customer,
          location: '/login',
        ),
        '/home',
      );
    });

    test('salon owner is routed to /salon', () {
      expect(
        resolveRedirect(
          isLoggedIn: true,
          role: UserRole.salonOwner,
          location: '/login',
        ),
        '/salon',
      );
    });

    test('staff also routes to /salon', () {
      expect(
        resolveRedirect(
          isLoggedIn: true,
          role: UserRole.staff,
          location: '/',
        ),
        '/salon',
      );
    });

    test('admin is routed to /admin', () {
      expect(
        resolveRedirect(
          isLoggedIn: true,
          role: UserRole.admin,
          location: '/login',
        ),
        '/admin',
      );
    });

    test('customer already on /home stays', () {
      expect(
        resolveRedirect(
          isLoggedIn: true,
          role: UserRole.customer,
          location: '/home',
        ),
        isNull,
      );
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails.**

Run: `cd barbershop && flutter test test/features/auth/role_routing_test.dart`
Expected: FAIL — `app_router.dart` / `resolveRedirect` not defined.

- [ ] **Step 3: Implement the router and redirect helper.** Create `barbershop/lib/core/router/app_router.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/domain/app_user.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/home/presentation/admin_home_screen.dart';
import '../../features/home/presentation/customer_home_screen.dart';
import '../../features/home/presentation/salon_home_screen.dart';

const _publicRoutes = {'/login', '/signup'};

String _homeFor(UserRole role) {
  switch (role) {
    case UserRole.customer:
      return '/home';
    case UserRole.salonOwner:
    case UserRole.staff:
      return '/salon';
    case UserRole.admin:
      return '/admin';
  }
}

/// Pure routing decision. Returns the path to redirect to, or null to stay.
String? resolveRedirect({
  required bool isLoggedIn,
  required UserRole? role,
  required String location,
}) {
  final onPublicRoute = _publicRoutes.contains(location);

  if (!isLoggedIn) {
    return onPublicRoute ? null : '/login';
  }

  // Logged in but profile/role not loaded yet — wait where we are.
  if (role == null) return null;

  final target = _homeFor(role);
  if (onPublicRoute || location == '/') return target;
  return null;
}

final goRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final repo = ref.read(authRepositoryProvider);
      final profile = ref.read(currentProfileProvider).valueOrNull;
      return resolveRedirect(
        isLoggedIn: repo.currentUserId != null,
        role: profile?.role,
        location: state.matchedLocation,
      );
    },
    refreshListenable: _ProviderRefreshListenable(ref),
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SizedBox.shrink()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, __) => const SignupScreen()),
      GoRoute(path: '/home', builder: (_, __) => const CustomerHomeScreen()),
      GoRoute(path: '/salon', builder: (_, __) => const SalonHomeScreen()),
      GoRoute(path: '/admin', builder: (_, __) => const AdminHomeScreen()),
    ],
  );
});

/// Rebuilds the router when auth state or the loaded profile changes.
class _ProviderRefreshListenable extends ChangeNotifier {
  _ProviderRefreshListenable(Ref ref) {
    ref.listen(authStateChangesProvider, (_, __) => notifyListeners());
    ref.listen(currentProfileProvider, (_, __) => notifyListeners());
  }
}
```

> Note: `ChangeNotifier` is in `package:flutter/foundation.dart`. Add `import 'package:flutter/foundation.dart';` at the top of the file.

- [ ] **Step 4: Add the missing import.** At the top of `app_router.dart`, add:

```dart
import 'package:flutter/foundation.dart';
```

- [ ] **Step 5: Run the test to verify it passes.**

Run: `flutter test test/features/auth/role_routing_test.dart`
Expected: PASS (7 tests). (The file imports `login_screen.dart`/`signup_screen.dart`; if they don't exist yet, this task is blocked on Task 9 — implement Task 9 first if the analyzer complains, then return. They are split because the redirect *logic* is what's under test here.)

- [ ] **Step 6: Commit.**

```bash
git add barbershop/lib/core/router/app_router.dart barbershop/test/features/auth/role_routing_test.dart
git commit -m "feat(router): auth-aware role-based redirect with go_router"
```

---

## Task 9: Auth UI — login and signup screens

**Files:**
- Create: `barbershop/lib/features/auth/presentation/auth_controller.dart`, `.../login_screen.dart`, `.../signup_screen.dart`
- Test: `barbershop/test/features/auth/login_screen_test.dart`

**Interfaces:**
- Consumes: `authRepositoryProvider` (Task 5); `AppLocalizations` (Task 6).
- Produces: `class AuthController extends AsyncNotifier<void>` with `signIn`, `signUp`, `signInWithGoogle`; `final authControllerProvider`; widgets `LoginScreen`, `SignupScreen`.

- [ ] **Step 1: Create the controller.** Create `barbershop/lib/features/auth/presentation/auth_controller.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';

class AuthController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> signIn(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).signInWithEmail(
            email: email,
            password: password,
          ),
    );
  }

  Future<void> signUp(String email, String password, String fullName) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).signUpWithEmail(
            email: email,
            password: password,
            fullName: fullName.isEmpty ? null : fullName,
          ),
    );
  }

  Future<void> signInWithGoogle() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).signInWithGoogle(),
    );
  }
}

final authControllerProvider =
    AutoDisposeAsyncNotifierProvider<AuthController, void>(
  AuthController.new,
);
```

- [ ] **Step 2: Create the login screen.** Create `barbershop/lib/features/auth/presentation/login_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(authControllerProvider);
    final busy = state.isLoading;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.loginTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              TextField(
                key: const Key('email'),
                controller: _email,
                decoration: InputDecoration(labelText: l10n.emailLabel),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('password'),
                controller: _password,
                decoration: InputDecoration(labelText: l10n.passwordLabel),
                obscureText: true,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: busy
                    ? null
                    : () => ref.read(authControllerProvider.notifier).signIn(
                          _email.text.trim(),
                          _password.text,
                        ),
                child: Text(l10n.signInButton),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () => ref
                        .read(authControllerProvider.notifier)
                        .signInWithGoogle(),
                icon: const Icon(Icons.g_mobiledata),
                label: Text(l10n.googleButton),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.go('/signup'),
                child: Text(l10n.noAccountPrompt),
              ),
              if (state.hasError)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    state.error.toString(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Create the signup screen.** Create `barbershop/lib/features/auth/presentation/signup_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth_controller.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _fullName.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(authControllerProvider);
    final busy = state.isLoading;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.signupTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              TextField(
                key: const Key('fullName'),
                controller: _fullName,
                decoration: InputDecoration(labelText: l10n.fullNameLabel),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('email'),
                controller: _email,
                decoration: InputDecoration(labelText: l10n.emailLabel),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('password'),
                controller: _password,
                decoration: InputDecoration(labelText: l10n.passwordLabel),
                obscureText: true,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: busy
                    ? null
                    : () => ref.read(authControllerProvider.notifier).signUp(
                          _email.text.trim(),
                          _password.text,
                          _fullName.text.trim(),
                        ),
                child: Text(l10n.signUpButton),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.go('/login'),
                child: Text(l10n.haveAccountPrompt),
              ),
              if (state.hasError)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    state.error.toString(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Write a widget test for the login screen.** Create `barbershop/test/features/auth/login_screen_test.dart`:

```dart
import 'package:barbershop/features/auth/data/auth_repository.dart';
import 'package:barbershop/features/auth/presentation/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
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
```

- [ ] **Step 5: Run the widget test to verify it passes.**

Run: `cd barbershop && flutter test test/features/auth/login_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Run the full test suite + analyzer.**

Run: `flutter test && flutter analyze`
Expected: all tests pass; analyzer clean. (Task 8's `role_routing_test.dart` now compiles since the screens exist.)

- [ ] **Step 7: Commit.**

```bash
git add barbershop/lib/features/auth/presentation barbershop/test/features/auth/login_screen_test.dart
git commit -m "feat(auth): login and signup screens wired to AuthController"
```

---

## Task 10: App widget and bootstrap

**Files:**
- Create: `barbershop/lib/app.dart`
- Modify: `barbershop/lib/main.dart` (replace generated content)

**Interfaces:**
- Consumes: `goRouterProvider` (Task 8); `AppTheme` (Task 7); `Env` (Task 4); `AppLocalizations` (Task 6).
- Produces: `class App extends ConsumerWidget` (MaterialApp.router); a `main()` that initializes Supabase and runs the app.

- [ ] **Step 1: Create the App widget.** Create `barbershop/lib/app.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      theme: AppTheme.light(),
      routerConfig: router,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('fr')],
      locale: const Locale('fr'),
    );
  }
}
```

- [ ] **Step 2: Replace `barbershop/lib/main.dart`:**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  assert(
    Env.isConfigured,
    'Missing SUPABASE_URL / SUPABASE_ANON_KEY. Pass them with --dart-define.',
  );

  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
  );

  runApp(const ProviderScope(child: App()));
}
```

- [ ] **Step 3: Verify the whole app compiles.**

Run: `cd barbershop && flutter analyze`
Expected: no errors.

- [ ] **Step 4: Commit.**

```bash
git add barbershop/lib/app.dart barbershop/lib/main.dart
git commit -m "feat(app): MaterialApp.router bootstrap with Supabase init"
```

---

## Task 11: End-to-end manual verification on web

**Files:** none (manual run + Google OAuth config note).

**Interfaces:** consumes the running local Supabase from Task 2.

- [ ] **Step 1: Confirm local Supabase is running and capture credentials.**

Run:
```bash
supabase status
```
Expected: prints `API URL` (e.g. `http://127.0.0.1:54321`) and `anon key`.

- [ ] **Step 2: Run the app on Chrome with the local credentials.**

Run (from `barbershop/`, substitute the anon key from Step 1):
```bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_ANON_KEY=<anon-key>
```
Expected: the app loads at `/login`.

- [ ] **Step 3: Verify email signup → customer home.** In the browser: open `/signup`, enter a name, email, and password, tap **S'inscrire**. (Local Supabase auto-confirms emails by default.)
Expected: after signup you are redirected to **`/home`** (customer home) showing "Accueil". A `profiles` row exists — verify:
```bash
supabase db query "select id, role from public.profiles;" 2>/dev/null \
  || psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -c "select id, role from public.profiles;"
```
Expected: one row with `role = customer`.

- [ ] **Step 4: Verify sign-out and sign-in.** Tap the logout icon → redirected to `/login`. Sign back in with the same credentials → back to `/home`.

- [ ] **Step 5: Verify role routing manually.** Promote the user to `admin` and confirm routing:
```bash
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
  -c "update public.profiles set role='admin';"
```
Reload the app (still signed in). Expected: redirected to **`/admin`** ("Administration"). Set it back to `customer` afterward.

- [ ] **Step 6: Document Google OAuth setup (config only — full native flow is later).** Append to `barbershop/README.md`:

```markdown
## Google sign-in (local dev)

Google OAuth requires a Google Cloud OAuth client. For local testing, add the
client id/secret to `supabase/config.toml` under `[auth.external.google]` and set
`enabled = true`, then `supabase stop && supabase start`. The "Continuer avec
Google" button uses `signInWithOAuth(OAuthProvider.google)` and is fully wired;
it only needs these credentials to complete the redirect.
```

- [ ] **Step 7: Commit.**

```bash
cd /Users/macbook/Desktop/DEVCAMP
git add barbershop/README.md
git commit -m "docs: local run instructions and Google OAuth setup note"
```

---

## Self-Review

**Spec coverage (against the design doc §4, §5, §9):**
- Flutter single codebase, web-first → Tasks 1, 11. ✓
- Supabase Postgres + Auth (email + Google) → Tasks 2, 5, 11. ✓
- `profiles` table with role enum + snapshots-irrelevant-here columns → Task 2. ✓
- RLS (own-row only) → Task 2 (pgTAP). ✓
- Localization-ready, French, no hardcoded strings → Task 6 (all UI text via ARB). ✓
- Role-based routing (customer/salon_owner/staff/admin) → Tasks 8, 11. ✓ (staff → salon home, per spec.)
- Feature-first structure, thin data layer → file structure + Tasks 3–9. ✓
- *Deferred to later plans (correctly not here):* salons/services/bookings/caisse/reviews, Edge Functions, FCM, admin moderation UI.

**Placeholder scan:** No TBD/TODO; every code step has complete code; commands have expected output. ✓

**Type consistency:** `UserRole` values (`customer/salonOwner/staff/admin`, `dbValue` snake_case) consistent across Tasks 3, 7, 8. `AuthRepository` method signatures used in Tasks 5, 9, 11 match. `resolveRedirect` signature matches between Task 8 impl and test. `currentProfileProvider`/`authStateChangesProvider` defined in Task 5, consumed in Task 8. ✓

**Note on Task 8/9 ordering:** Task 8's test exercises the pure `resolveRedirect` function, but the file imports the auth screens created in Task 9. If executing strictly in order and the analyzer blocks on the missing imports, implement Task 9's screen files first (empty `Scaffold` stubs are enough to compile), then complete Task 8. Flagged in Task 8 Step 5.
