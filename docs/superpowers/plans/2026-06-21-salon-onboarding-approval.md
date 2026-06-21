# Salon Onboarding & Admin Approval Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A logged-in customer can register their salon (status → `pending`), an admin approves or rejects it, the owner can edit the salon profile (including the "show prices" toggle), and approved salons become publicly readable.

**Architecture:** Builds on Plan 1 (Foundation). Adds a `salons` table secured by RLS for **reads** only; all **writes** go through `SECURITY DEFINER` Postgres RPCs (`register_salon`, `update_my_salon`, `set_salon_status`) so business rules are server-enforced — owners cannot self-approve and role elevation (customer → salon_owner) happens atomically with salon creation. Flutter side adds `SalonRepository`, `AdminRepository`, a registration flow, a salon dashboard (pending vs approved), and an admin approvals screen.

**Tech Stack:** Flutter 3.35, Dart 3.9, `supabase_flutter` v2, `flutter_riverpod` v3, `go_router` v17, `mocktail`, Supabase CLI + Docker (pgTAP).

## Global Constraints

These carry over from Plan 1 and are binding (verified against the real codebase):

- **Riverpod 3.x API:** use `AsyncNotifier` / `AsyncNotifierProvider` (NOT `AutoDispose*` — providers are auto-dispose by default). `AsyncValue` exposes `.value` (nullable); there is no `valueOrNull`.
- **Localization:** Flutter 3.35 source-generates l10n into `lib/l10n/`. Import `package:barbershop/l10n/app_localizations.dart`. Add new strings to `lib/l10n/app_fr.arb`, then run `flutter gen-l10n`. **No hardcoded UI text.** French only.
- **Supabase init:** app uses `publishableKey` (env `SUPABASE_PUBLISHABLE_KEY`), not the deprecated `anonKey`.
- **RLS + grants:** every table has RLS enabled AND explicit `grant`s to `authenticated`/`anon` as needed (RLS filters rows; grants permit reaching the table). Writes to `salons` are performed ONLY via `SECURITY DEFINER` RPCs — the table has no insert/update/delete policy, so direct client writes are denied.
- **Roles:** `profiles.role` ∈ {`customer`,`salon_owner`,`staff`,`admin`}. A customer becomes `salon_owner` only via `register_salon`.
- **Existing interfaces (Plan 1):** `supabaseClientProvider` (`lib/core/supabase/supabase_providers.dart`); `AuthRepository`, `authRepositoryProvider`, `currentProfileProvider`, `authStateChangesProvider` (`lib/features/auth/data/auth_repository.dart`); `UserRole`, `AppUser` (`lib/features/auth/domain/app_user.dart`); `resolveRedirect`, `goRouterProvider` (`lib/core/router/app_router.dart`); home screens under `lib/features/home/presentation/`.
- **TDD:** failing test first for every behavior; commit after each green step.
- **Working dir:** Flutter commands run from `barbershop/`; `supabase` commands from repo root `/Users/macbook/Desktop/DEVCAMP`.

---

## File Structure

```
barbershop/
├── lib/
│   ├── core/router/app_router.dart                # MODIFY: add salon/admin routes + redirect
│   └── features/
│       ├── salon/
│       │   ├── domain/salon.dart                  # Salon model + SalonStatus enum
│       │   ├── data/salon_repository.dart         # SalonRepository + providers
│       │   └── presentation/
│       │       ├── salon_registration_controller.dart
│       │       ├── salon_registration_screen.dart
│       │       ├── salon_dashboard_screen.dart     # replaces salon_home placeholder
│       │       └── salon_profile_form.dart         # edit profile + show_prices
│       └── admin/
│           ├── data/admin_repository.dart          # AdminRepository + providers
│           └── presentation/admin_approvals_screen.dart
│   ├── l10n/app_fr.arb                              # MODIFY: add strings
│   └── features/home/presentation/customer_home_screen.dart  # MODIFY: "register salon" entry
├── test/features/salon/...                         # model + repo + widget tests
├── test/features/admin/...
└── supabase/
    ├── migrations/0002_salons.sql                  # salons + enum + RLS + RPCs + is_admin
    └── tests/salons_rls_test.sql                    # pgTAP
```

---

## Task 1: Salon schema, RLS, and RPCs (with pgTAP tests)

**Files:**
- Create: `supabase/migrations/0002_salons.sql`, `supabase/tests/salons_rls_test.sql`

**Interfaces:**
- Consumes: `public.profiles`, `public.user_role` (Plan 1).
- Produces:
  - `public.salon_status` enum (`pending`,`approved`,`rejected`,`suspended`).
  - `public.salons` table.
  - `public.is_admin() returns boolean`.
  - `public.register_salon(p_name text, p_city text, p_description text, p_address text) returns uuid`.
  - `public.update_my_salon(p_name text, p_description text, p_city text, p_address text, p_show_prices boolean) returns void`.
  - `public.set_salon_status(p_salon_id uuid, p_status public.salon_status) returns void`.

- [ ] **Step 1: Write the migration.** Create `supabase/migrations/0002_salons.sql`:

```sql
create type public.salon_status as enum ('pending', 'approved', 'rejected', 'suspended');

create table public.salons (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null references auth.users (id) on delete cascade,
  name         text not null,
  description  text,
  city         text not null,
  address      text,
  cover_url    text,
  status       public.salon_status not null default 'pending',
  show_prices  boolean not null default true,
  rating_avg   numeric(2,1) not null default 0,
  rating_count integer not null default 0,
  created_at   timestamptz not null default now()
);

create index salons_owner_idx on public.salons (owner_id);
create index salons_status_idx on public.salons (status);

alter table public.salons enable row level security;

-- Reads: anyone may read approved salons; an owner reads their own; admins read all.
-- Writes go exclusively through SECURITY DEFINER RPCs below (no write policies).
grant select on public.salons to anon, authenticated;

-- True when the current user has the admin role.
create function public.is_admin()
  returns boolean
  language sql
  security definer
  stable
  set search_path = public
as $$
  select exists (
    select 1 from public.profiles where id = auth.uid() and role = 'admin'
  );
$$;

create policy "salons_select_visible"
  on public.salons for select
  using (status = 'approved' or owner_id = auth.uid() or public.is_admin());

-- Register a salon for the caller and elevate them to salon_owner.
create function public.register_salon(
  p_name text,
  p_city text,
  p_description text default null,
  p_address text default null
)
  returns uuid
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  insert into public.salons (owner_id, name, city, description, address, status)
  values (auth.uid(), p_name, p_city, p_description, p_address, 'pending')
  returning id into v_id;

  update public.profiles
    set role = 'salon_owner'
    where id = auth.uid() and role = 'customer';

  return v_id;
end;
$$;

-- Owner edits their own salon profile. Never changes status.
create function public.update_my_salon(
  p_name text,
  p_description text,
  p_city text,
  p_address text,
  p_show_prices boolean
)
  returns void
  language plpgsql
  security definer
  set search_path = public
as $$
begin
  update public.salons
    set name = p_name,
        description = p_description,
        city = p_city,
        address = p_address,
        show_prices = p_show_prices
    where owner_id = auth.uid();
end;
$$;

-- Admin-only status transition (approve / reject / suspend).
create function public.set_salon_status(
  p_salon_id uuid,
  p_status public.salon_status
)
  returns void
  language plpgsql
  security definer
  set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'forbidden';
  end if;

  update public.salons set status = p_status where id = p_salon_id;
end;
$$;

grant execute on function public.register_salon(text, text, text, text) to authenticated;
grant execute on function public.update_my_salon(text, text, text, text, boolean) to authenticated;
grant execute on function public.set_salon_status(uuid, public.salon_status) to authenticated;
```

- [ ] **Step 2: Apply the migration.**

Run (from repo root): `supabase db reset`
Expected: applies `0001` then `0002` with no error.

- [ ] **Step 3: Write the failing pgTAP test.** Create `supabase/tests/salons_rls_test.sql`:

```sql
begin;
select plan(6);

-- Seed three auth users: owner, stranger, admin (trigger makes customer profiles).
insert into auth.users (id, email) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'owner@test.dev'),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'stranger@test.dev'),
  ('cccccccc-0000-0000-0000-000000000003', 'admin@test.dev');
update public.profiles set role = 'admin'
  where id = 'cccccccc-0000-0000-0000-000000000003';

-- Act as the owner and register a salon via the RPC.
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-0000-0000-000000000001","role":"authenticated"}';

select lives_ok(
  $$ select public.register_salon('Barber House', 'Tunis', 'Best fades', 'Rue 1') $$,
  'owner can register a salon'
);

-- 1. The owner was elevated to salon_owner.
select is(
  (select role::text from public.profiles where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  'salon_owner',
  'register_salon elevates caller to salon_owner'
);

-- 2. The new salon is pending and visible to its owner.
select is(
  (select status::text from public.salons where owner_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  'pending',
  'registered salon is pending'
);

-- 3. A stranger cannot see a pending salon (RLS hides it).
set local request.jwt.claims = '{"sub":"bbbbbbbb-0000-0000-0000-000000000002","role":"authenticated"}';
select is(
  (select count(*)::int from public.salons),
  0,
  'stranger cannot see a pending salon'
);

-- 4. A non-admin cannot change status.
select throws_ok(
  $$ select public.set_salon_status(
       (select id from public.salons limit 1), 'approved') $$,
  'forbidden',
  'non-admin cannot set salon status'
);

-- 5. An admin can approve, after which the stranger can see it.
set local request.jwt.claims = '{"sub":"cccccccc-0000-0000-0000-000000000003","role":"authenticated"}';
select public.set_salon_status(
  (select id from public.salons where status = 'pending' limit 1), 'approved');

set local request.jwt.claims = '{"sub":"bbbbbbbb-0000-0000-0000-000000000002","role":"authenticated"}';
select is(
  (select count(*)::int from public.salons where status = 'approved'),
  1,
  'approved salon is publicly visible'
);

select * from finish();
rollback;
```

- [ ] **Step 4: Run the pgTAP test and verify it passes.**

Run (from repo root): `supabase test db`
Expected: `salons_rls_test.sql .. ok`, all 6 assertions pass.

- [ ] **Step 5: Commit.**

```bash
git add supabase/migrations/0002_salons.sql supabase/tests/salons_rls_test.sql
git commit -m "feat(db): salons table with RLS reads and SECURITY DEFINER write RPCs"
```

---

## Task 2: Salon domain model

**Files:**
- Create: `barbershop/lib/features/salon/domain/salon.dart`
- Test: `barbershop/test/features/salon/salon_test.dart`

**Interfaces:**
- Produces:
  - `enum SalonStatus { pending, approved, rejected, suspended }` with `SalonStatus.fromDb(String)` and `String get dbValue`.
  - `class Salon { final String id; final String ownerId; final String name; final String? description; final String city; final String? address; final String? coverUrl; final SalonStatus status; final bool showPrices; final double ratingAvg; final int ratingCount; }` with `factory Salon.fromMap(Map<String, dynamic>)`.

- [ ] **Step 1: Write the failing test.** Create `barbershop/test/features/salon/salon_test.dart`:

```dart
import 'package:barbershop/features/salon/domain/salon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SalonStatus', () {
    test('maps db value to enum and back', () {
      expect(SalonStatus.fromDb('approved'), SalonStatus.approved);
      expect(SalonStatus.suspended.dbValue, 'suspended');
    });

    test('unknown status falls back to pending', () {
      expect(SalonStatus.fromDb('weird'), SalonStatus.pending);
    });
  });

  group('Salon.fromMap', () {
    test('builds from a salons row', () {
      final s = Salon.fromMap({
        'id': 's1',
        'owner_id': 'u1',
        'name': 'Barber House',
        'description': 'Best fades',
        'city': 'Tunis',
        'address': 'Rue 1',
        'cover_url': null,
        'status': 'pending',
        'show_prices': true,
        'rating_avg': 4.5,
        'rating_count': 12,
      });
      expect(s.id, 's1');
      expect(s.ownerId, 'u1');
      expect(s.name, 'Barber House');
      expect(s.city, 'Tunis');
      expect(s.status, SalonStatus.pending);
      expect(s.showPrices, true);
      expect(s.ratingAvg, 4.5);
      expect(s.ratingCount, 12);
    });

    test('coerces integer rating_avg to double', () {
      final s = Salon.fromMap({
        'id': 's1',
        'owner_id': 'u1',
        'name': 'X',
        'city': 'Sfax',
        'status': 'approved',
        'show_prices': false,
        'rating_avg': 0,
        'rating_count': 0,
      });
      expect(s.ratingAvg, 0.0);
      expect(s.showPrices, false);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails.**

Run: `cd barbershop && flutter test test/features/salon/salon_test.dart`
Expected: FAIL — `salon.dart` does not exist.

- [ ] **Step 3: Implement the model.** Create `barbershop/lib/features/salon/domain/salon.dart`:

```dart
enum SalonStatus {
  pending('pending'),
  approved('approved'),
  rejected('rejected'),
  suspended('suspended');

  const SalonStatus(this.dbValue);

  final String dbValue;

  static SalonStatus fromDb(String value) {
    return SalonStatus.values.firstWhere(
      (s) => s.dbValue == value,
      orElse: () => SalonStatus.pending,
    );
  }
}

class Salon {
  const Salon({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.city,
    required this.status,
    required this.showPrices,
    required this.ratingAvg,
    required this.ratingCount,
    this.description,
    this.address,
    this.coverUrl,
  });

  final String id;
  final String ownerId;
  final String name;
  final String? description;
  final String city;
  final String? address;
  final String? coverUrl;
  final SalonStatus status;
  final bool showPrices;
  final double ratingAvg;
  final int ratingCount;

  factory Salon.fromMap(Map<String, dynamic> map) {
    return Salon(
      id: map['id'] as String,
      ownerId: map['owner_id'] as String,
      name: map['name'] as String,
      description: map['description'] as String?,
      city: map['city'] as String,
      address: map['address'] as String?,
      coverUrl: map['cover_url'] as String?,
      status: SalonStatus.fromDb(map['status'] as String? ?? 'pending'),
      showPrices: map['show_prices'] as bool? ?? true,
      ratingAvg: (map['rating_avg'] as num? ?? 0).toDouble(),
      ratingCount: map['rating_count'] as int? ?? 0,
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes.**

Run: `flutter test test/features/salon/salon_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit.**

```bash
git add barbershop/lib/features/salon/domain/salon.dart barbershop/test/features/salon/salon_test.dart
git commit -m "feat(salon): Salon model and SalonStatus enum"
```

---

## Task 3: SalonRepository

**Files:**
- Create: `barbershop/lib/features/salon/data/salon_repository.dart`
- Test: `barbershop/test/features/salon/salon_repository_test.dart`

**Interfaces:**
- Consumes: `supabaseClientProvider`; `Salon` (Task 2); `currentProfileProvider` (Plan 1).
- Produces:
  - `class SalonRepository` with:
    - `Future<String> registerSalon({required String name, required String city, String? description, String? address})` → calls `rpc('register_salon', ...)`, returns new salon id.
    - `Future<Salon?> fetchMySalon(String ownerId)` → `from('salons').select().eq('owner_id', ownerId).maybeSingle()`.
    - `Future<void> updateMySalon({required String name, required String? description, required String city, required String? address, required bool showPrices})` → `rpc('update_my_salon', ...)`.
  - `final salonRepositoryProvider = Provider<SalonRepository>(...)`.
  - `final mySalonProvider = FutureProvider<Salon?>(...)` — resolves the current user's salon (watches `currentProfileProvider`).

- [ ] **Step 1: Write the failing test.** Create `barbershop/test/features/salon/salon_repository_test.dart`:

```dart
import 'package:barbershop/features/salon/data/salon_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockClient extends Mock implements SupabaseClient {}

void main() {
  late _MockClient client;
  late SalonRepository repo;

  setUp(() {
    client = _MockClient();
    repo = SalonRepository(client);
  });

  test('registerSalon calls the register_salon RPC and returns the id', () async {
    when(() => client.rpc('register_salon', params: any(named: 'params')))
        .thenAnswer((_) async => 'new-salon-id');

    final id = await repo.registerSalon(name: 'Barber House', city: 'Tunis');

    expect(id, 'new-salon-id');
    verify(() => client.rpc('register_salon', params: {
          'p_name': 'Barber House',
          'p_city': 'Tunis',
          'p_description': null,
          'p_address': null,
        })).called(1);
  });

  test('updateMySalon calls the update_my_salon RPC with all fields', () async {
    when(() => client.rpc('update_my_salon', params: any(named: 'params')))
        .thenAnswer((_) async => null);

    await repo.updateMySalon(
      name: 'New Name',
      description: 'desc',
      city: 'Sfax',
      address: null,
      showPrices: false,
    );

    verify(() => client.rpc('update_my_salon', params: {
          'p_name': 'New Name',
          'p_description': 'desc',
          'p_city': 'Sfax',
          'p_address': null,
          'p_show_prices': false,
        })).called(1);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails.**

Run: `cd barbershop && flutter test test/features/salon/salon_repository_test.dart`
Expected: FAIL — `salon_repository.dart` does not exist.

- [ ] **Step 3: Implement the repository.** Create `barbershop/lib/features/salon/data/salon_repository.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/salon.dart';

class SalonRepository {
  SalonRepository(this._client);

  final SupabaseClient _client;

  Future<String> registerSalon({
    required String name,
    required String city,
    String? description,
    String? address,
  }) async {
    final id = await _client.rpc('register_salon', params: {
      'p_name': name,
      'p_city': city,
      'p_description': description,
      'p_address': address,
    });
    return id as String;
  }

  Future<Salon?> fetchMySalon(String ownerId) async {
    final row = await _client
        .from('salons')
        .select()
        .eq('owner_id', ownerId)
        .maybeSingle();
    if (row == null) return null;
    return Salon.fromMap(row);
  }

  Future<void> updateMySalon({
    required String name,
    required String? description,
    required String city,
    required String? address,
    required bool showPrices,
  }) async {
    await _client.rpc('update_my_salon', params: {
      'p_name': name,
      'p_description': description,
      'p_city': city,
      'p_address': address,
      'p_show_prices': showPrices,
    });
  }
}

final salonRepositoryProvider = Provider<SalonRepository>((ref) {
  return SalonRepository(ref.watch(supabaseClientProvider));
});

/// The current user's salon (if they own one). Recomputes when the profile
/// changes (e.g. right after registration elevates them to salon_owner).
final mySalonProvider = FutureProvider<Salon?>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile == null) return null;
  return ref.watch(salonRepositoryProvider).fetchMySalon(profile.id);
});
```

- [ ] **Step 4: Run the test to verify it passes.**

Run: `flutter test test/features/salon/salon_repository_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit.**

```bash
git add barbershop/lib/features/salon/data/salon_repository.dart barbershop/test/features/salon/salon_repository_test.dart
git commit -m "feat(salon): SalonRepository with register/fetch/update and mySalon provider"
```

---

## Task 4: AdminRepository

**Files:**
- Create: `barbershop/lib/features/admin/data/admin_repository.dart`
- Test: `barbershop/test/features/admin/admin_repository_test.dart`

**Interfaces:**
- Consumes: `supabaseClientProvider`; `Salon`, `SalonStatus` (Task 2).
- Produces:
  - `class AdminRepository` with:
    - `Future<List<Salon>> fetchPendingSalons()` → `from('salons').select().eq('status','pending').order('created_at')`.
    - `Future<void> setStatus(String salonId, SalonStatus status)` → `rpc('set_salon_status', ...)`.
  - `final adminRepositoryProvider = Provider<AdminRepository>(...)`.
  - `final pendingSalonsProvider = FutureProvider<List<Salon>>(...)`.

- [ ] **Step 1: Write the failing test.** Create `barbershop/test/features/admin/admin_repository_test.dart`:

```dart
import 'package:barbershop/features/admin/data/admin_repository.dart';
import 'package:barbershop/features/salon/domain/salon.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockClient extends Mock implements SupabaseClient {}

void main() {
  late _MockClient client;
  late AdminRepository repo;

  setUp(() {
    client = _MockClient();
    repo = AdminRepository(client);
  });

  test('setStatus calls set_salon_status with the db value', () async {
    when(() => client.rpc('set_salon_status', params: any(named: 'params')))
        .thenAnswer((_) async => null);

    await repo.setStatus('salon-1', SalonStatus.approved);

    verify(() => client.rpc('set_salon_status', params: {
          'p_salon_id': 'salon-1',
          'p_status': 'approved',
        })).called(1);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails.**

Run: `cd barbershop && flutter test test/features/admin/admin_repository_test.dart`
Expected: FAIL — `admin_repository.dart` does not exist.

- [ ] **Step 3: Implement the repository.** Create `barbershop/lib/features/admin/data/admin_repository.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../salon/domain/salon.dart';

class AdminRepository {
  AdminRepository(this._client);

  final SupabaseClient _client;

  Future<List<Salon>> fetchPendingSalons() async {
    final rows = await _client
        .from('salons')
        .select()
        .eq('status', 'pending')
        .order('created_at');
    return (rows as List)
        .map((r) => Salon.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> setStatus(String salonId, SalonStatus status) async {
    await _client.rpc('set_salon_status', params: {
      'p_salon_id': salonId,
      'p_status': status.dbValue,
    });
  }
}

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AdminRepository(ref.watch(supabaseClientProvider));
});

final pendingSalonsProvider = FutureProvider<List<Salon>>((ref) async {
  return ref.watch(adminRepositoryProvider).fetchPendingSalons();
});
```

- [ ] **Step 4: Run the test to verify it passes.**

Run: `flutter test test/features/admin/admin_repository_test.dart`
Expected: PASS (1 test).

- [ ] **Step 5: Commit.**

```bash
git add barbershop/lib/features/admin/data/admin_repository.dart barbershop/test/features/admin/admin_repository_test.dart
git commit -m "feat(admin): AdminRepository with pending list and status RPC"
```

---

## Task 5: Localization strings

**Files:**
- Modify: `barbershop/lib/l10n/app_fr.arb`

**Interfaces:**
- Produces (added to `AppLocalizations`): `registerSalonButton`, `salonRegistrationTitle`, `salonNameLabel`, `salonCityLabel`, `salonDescriptionLabel`, `salonAddressLabel`, `submitButton`, `saveButton`, `showPricesLabel`, `pendingApprovalTitle`, `pendingApprovalBody`, `rejectedTitle`, `suspendedTitle`, `salonProfileTitle`, `adminApprovalsTitle`, `noPendingSalons`, `approveButton`, `rejectButton`.

- [ ] **Step 1: Add the strings.** In `barbershop/lib/l10n/app_fr.arb`, add these keys before the closing brace (keep existing keys; ensure the preceding line ends with a comma):

```json
  "registerSalonButton": "Inscrire mon salon",
  "salonRegistrationTitle": "Inscription du salon",
  "salonNameLabel": "Nom du salon",
  "salonCityLabel": "Ville",
  "salonDescriptionLabel": "Description",
  "salonAddressLabel": "Adresse",
  "submitButton": "Envoyer",
  "saveButton": "Enregistrer",
  "showPricesLabel": "Afficher les prix",
  "pendingApprovalTitle": "En attente de validation",
  "pendingApprovalBody": "Votre salon est en cours de validation par l'administrateur.",
  "rejectedTitle": "Inscription refusée",
  "suspendedTitle": "Salon suspendu",
  "salonProfileTitle": "Profil du salon",
  "adminApprovalsTitle": "Salons à valider",
  "noPendingSalons": "Aucun salon en attente",
  "approveButton": "Valider",
  "rejectButton": "Refuser"
```

- [ ] **Step 2: Regenerate localizations.**

Run: `cd barbershop && flutter gen-l10n`
Expected: regenerates `lib/l10n/app_localizations*.dart` with the new getters; no errors.

- [ ] **Step 3: Verify it compiles.**

Run: `flutter analyze lib/l10n`
Expected: No issues found.

- [ ] **Step 4: Commit.**

```bash
git add barbershop/lib/l10n/
git commit -m "feat(l10n): salon onboarding, profile, and admin approval strings"
```

---

## Task 6: Salon registration flow

**Files:**
- Create: `barbershop/lib/features/salon/presentation/salon_registration_controller.dart`, `.../salon_registration_screen.dart`
- Test: `barbershop/test/features/salon/salon_registration_screen_test.dart`

**Interfaces:**
- Consumes: `salonRepositoryProvider` (Task 3); `currentProfileProvider`, `mySalonProvider`; `AppLocalizations`.
- Produces:
  - `class SalonRegistrationController extends AsyncNotifier<void>` with `Future<void> submit({required String name, required String city, String? description, String? address})` that calls `registerSalon`, then invalidates `currentProfileProvider` and `mySalonProvider` so the router re-routes to the salon dashboard.
  - `final salonRegistrationControllerProvider = AsyncNotifierProvider<SalonRegistrationController, void>(SalonRegistrationController.new)`.
  - `class SalonRegistrationScreen extends ConsumerStatefulWidget`.

- [ ] **Step 1: Create the controller.** Create `barbershop/lib/features/salon/presentation/salon_registration_controller.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../data/salon_repository.dart';

class SalonRegistrationController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> submit({
    required String name,
    required String city,
    String? description,
    String? address,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(salonRepositoryProvider).registerSalon(
            name: name,
            city: city,
            description: description,
            address: address,
          );
      // Role changed to salon_owner and a salon now exists — refresh both so
      // the router redirects to the salon dashboard.
      ref.invalidate(currentProfileProvider);
      ref.invalidate(mySalonProvider);
    });
  }
}

final salonRegistrationControllerProvider =
    AsyncNotifierProvider<SalonRegistrationController, void>(
  SalonRegistrationController.new,
);
```

- [ ] **Step 2: Create the screen.** Create `barbershop/lib/features/salon/presentation/salon_registration_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import 'salon_registration_controller.dart';

class SalonRegistrationScreen extends ConsumerStatefulWidget {
  const SalonRegistrationScreen({super.key});

  @override
  ConsumerState<SalonRegistrationScreen> createState() =>
      _SalonRegistrationScreenState();
}

class _SalonRegistrationScreenState
    extends ConsumerState<SalonRegistrationScreen> {
  final _name = TextEditingController();
  final _city = TextEditingController();
  final _description = TextEditingController();
  final _address = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _description.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(salonRegistrationControllerProvider);
    final busy = state.isLoading;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.salonRegistrationTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              TextField(
                key: const Key('salonName'),
                controller: _name,
                decoration: InputDecoration(labelText: l10n.salonNameLabel),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('salonCity'),
                controller: _city,
                decoration: InputDecoration(labelText: l10n.salonCityLabel),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('salonDescription'),
                controller: _description,
                decoration:
                    InputDecoration(labelText: l10n.salonDescriptionLabel),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('salonAddress'),
                controller: _address,
                decoration: InputDecoration(labelText: l10n.salonAddressLabel),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: busy
                    ? null
                    : () => ref
                        .read(salonRegistrationControllerProvider.notifier)
                        .submit(
                          name: _name.text.trim(),
                          city: _city.text.trim(),
                          description: _description.text.trim().isEmpty
                              ? null
                              : _description.text.trim(),
                          address: _address.text.trim().isEmpty
                              ? null
                              : _address.text.trim(),
                        ),
                child: Text(l10n.submitButton),
              ),
              if (state.hasError)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    state.error.toString(),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
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

- [ ] **Step 3: Write a widget test.** Create `barbershop/test/features/salon/salon_registration_screen_test.dart`:

```dart
import 'package:barbershop/features/salon/data/salon_repository.dart';
import 'package:barbershop/features/salon/presentation/salon_registration_screen.dart';
import 'package:barbershop/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockSalonRepository extends Mock implements SalonRepository {}

void main() {
  testWidgets('submitting calls registerSalon with name and city',
      (tester) async {
    final repo = _MockSalonRepository();
    when(() => repo.registerSalon(
          name: any(named: 'name'),
          city: any(named: 'city'),
          description: any(named: 'description'),
          address: any(named: 'address'),
        )).thenAnswer((_) async => 'id');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [salonRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: [Locale('fr')],
          home: SalonRegistrationScreen(),
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('salonName')), 'Barber House');
    await tester.enterText(find.byKey(const Key('salonCity')), 'Tunis');
    await tester.tap(find.text('Envoyer'));
    await tester.pump();

    verify(() => repo.registerSalon(
          name: 'Barber House',
          city: 'Tunis',
          description: null,
          address: null,
        )).called(1);
  });
}
```

- [ ] **Step 4: Run the widget test.**

Run: `cd barbershop && flutter test test/features/salon/salon_registration_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git add barbershop/lib/features/salon/presentation/salon_registration_controller.dart barbershop/lib/features/salon/presentation/salon_registration_screen.dart barbershop/test/features/salon/salon_registration_screen_test.dart
git commit -m "feat(salon): salon registration flow with role elevation refresh"
```

---

## Task 7: Salon dashboard (pending vs approved + profile editor)

**Files:**
- Create: `barbershop/lib/features/salon/presentation/salon_dashboard_screen.dart`, `.../salon_profile_form.dart`
- Modify: `barbershop/lib/features/home/presentation/salon_home_screen.dart` (delegate to dashboard) — OR replace its usage in the router (Task 9). For this task, build the dashboard as a standalone widget.
- Test: `barbershop/test/features/salon/salon_dashboard_screen_test.dart`

**Interfaces:**
- Consumes: `mySalonProvider` (Task 3), `salonRepositoryProvider`, `authRepositoryProvider`, `AppLocalizations`, `Salon`/`SalonStatus`.
- Produces:
  - `class SalonDashboardScreen extends ConsumerWidget` — watches `mySalonProvider`; shows a loading spinner, a pending/rejected/suspended banner, or (when approved) the `SalonProfileForm`. Has a sign-out action.
  - `class SalonProfileForm extends ConsumerStatefulWidget` — pre-filled editable form (name, description, city, address, `show_prices` switch) that calls `updateMySalon` and refreshes `mySalonProvider`.

- [ ] **Step 1: Create the profile form.** Create `barbershop/lib/features/salon/presentation/salon_profile_form.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../data/salon_repository.dart';
import '../domain/salon.dart';

class SalonProfileForm extends ConsumerStatefulWidget {
  const SalonProfileForm({required this.salon, super.key});

  final Salon salon;

  @override
  ConsumerState<SalonProfileForm> createState() => _SalonProfileFormState();
}

class _SalonProfileFormState extends ConsumerState<SalonProfileForm> {
  late final TextEditingController _name =
      TextEditingController(text: widget.salon.name);
  late final TextEditingController _description =
      TextEditingController(text: widget.salon.description ?? '');
  late final TextEditingController _city =
      TextEditingController(text: widget.salon.city);
  late final TextEditingController _address =
      TextEditingController(text: widget.salon.address ?? '');
  late bool _showPrices = widget.salon.showPrices;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _city.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(salonRepositoryProvider).updateMySalon(
            name: _name.text.trim(),
            description:
                _description.text.trim().isEmpty ? null : _description.text.trim(),
            city: _city.text.trim(),
            address: _address.text.trim().isEmpty ? null : _address.text.trim(),
            showPrices: _showPrices,
          );
      ref.invalidate(mySalonProvider);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        TextField(
          key: const Key('profileName'),
          controller: _name,
          decoration: InputDecoration(labelText: l10n.salonNameLabel),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _city,
          decoration: InputDecoration(labelText: l10n.salonCityLabel),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _description,
          decoration: InputDecoration(labelText: l10n.salonDescriptionLabel),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _address,
          decoration: InputDecoration(labelText: l10n.salonAddressLabel),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          key: const Key('showPricesSwitch'),
          title: Text(l10n.showPricesLabel),
          value: _showPrices,
          onChanged: (v) => setState(() => _showPrices = v),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(l10n.saveButton),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Create the dashboard.** Create `barbershop/lib/features/salon/presentation/salon_dashboard_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../auth/data/auth_repository.dart';
import '../data/salon_repository.dart';
import '../domain/salon.dart';
import 'salon_profile_form.dart';

class SalonDashboardScreen extends ConsumerWidget {
  const SalonDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final salonAsync = ref.watch(mySalonProvider);

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
      body: salonAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (salon) {
          if (salon == null) {
            return Center(child: Text(l10n.pendingApprovalBody));
          }
          switch (salon.status) {
            case SalonStatus.approved:
              return SalonProfileForm(salon: salon);
            case SalonStatus.pending:
              return _Banner(
                icon: Icons.hourglass_top,
                title: l10n.pendingApprovalTitle,
                body: l10n.pendingApprovalBody,
              );
            case SalonStatus.rejected:
              return _Banner(
                icon: Icons.cancel,
                title: l10n.rejectedTitle,
                body: l10n.pendingApprovalBody,
              );
            case SalonStatus.suspended:
              return _Banner(
                icon: Icons.pause_circle,
                title: l10n.suspendedTitle,
                body: l10n.pendingApprovalBody,
              );
          }
        },
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(body, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Write a widget test.** Create `barbershop/test/features/salon/salon_dashboard_screen_test.dart`:

```dart
import 'package:barbershop/features/salon/data/salon_repository.dart';
import 'package:barbershop/features/salon/domain/salon.dart';
import 'package:barbershop/features/salon/presentation/salon_dashboard_screen.dart';
import 'package:barbershop/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [Locale('fr')],
        home: SalonDashboardScreen(),
      ),
    );

Salon _salon(SalonStatus status) => Salon(
      id: 's1',
      ownerId: 'u1',
      name: 'Barber House',
      city: 'Tunis',
      status: status,
      showPrices: true,
      ratingAvg: 0,
      ratingCount: 0,
    );

void main() {
  testWidgets('pending salon shows the pending banner', (tester) async {
    await tester.pumpWidget(_wrap([
      mySalonProvider.overrideWith((ref) async => _salon(SalonStatus.pending)),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('En attente de validation'), findsOneWidget);
  });

  testWidgets('approved salon shows the editable profile form',
      (tester) async {
    await tester.pumpWidget(_wrap([
      mySalonProvider.overrideWith((ref) async => _salon(SalonStatus.approved)),
    ]));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profileName')), findsOneWidget);
    expect(find.byKey(const Key('showPricesSwitch')), findsOneWidget);
  });
}
```

- [ ] **Step 4: Run the widget test.**

Run: `cd barbershop && flutter test test/features/salon/salon_dashboard_screen_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit.**

```bash
git add barbershop/lib/features/salon/presentation/salon_dashboard_screen.dart barbershop/lib/features/salon/presentation/salon_profile_form.dart barbershop/test/features/salon/salon_dashboard_screen_test.dart
git commit -m "feat(salon): salon dashboard with status banner and profile editor"
```

---

## Task 8: Admin approvals screen

**Files:**
- Create: `barbershop/lib/features/admin/presentation/admin_approvals_screen.dart`
- Test: `barbershop/test/features/admin/admin_approvals_screen_test.dart`

**Interfaces:**
- Consumes: `pendingSalonsProvider`, `adminRepositoryProvider` (Task 4); `authRepositoryProvider`; `AppLocalizations`; `Salon`/`SalonStatus`.
- Produces:
  - `class AdminApprovalsScreen extends ConsumerWidget` — lists pending salons with **Valider** / **Refuser** buttons that call `setStatus` then invalidate `pendingSalonsProvider`. Shows `noPendingSalons` when empty. Has a sign-out action.

- [ ] **Step 1: Create the screen.** Create `barbershop/lib/features/admin/presentation/admin_approvals_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../auth/data/auth_repository.dart';
import '../../salon/domain/salon.dart';
import '../data/admin_repository.dart';

class AdminApprovalsScreen extends ConsumerWidget {
  const AdminApprovalsScreen({super.key});

  Future<void> _set(WidgetRef ref, String id, SalonStatus status) async {
    await ref.read(adminRepositoryProvider).setStatus(id, status);
    ref.invalidate(pendingSalonsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final pending = ref.watch(pendingSalonsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminApprovalsTitle),
        actions: [
          IconButton(
            tooltip: l10n.signOutButton,
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
          ),
        ],
      ),
      body: pending.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (salons) {
          if (salons.isEmpty) {
            return Center(child: Text(l10n.noPendingSalons));
          }
          return ListView.separated(
            itemCount: salons.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final s = salons[i];
              return ListTile(
                title: Text(s.name),
                subtitle: Text(s.city),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () =>
                          _set(ref, s.id, SalonStatus.approved),
                      child: Text(l10n.approveButton),
                    ),
                    TextButton(
                      onPressed: () =>
                          _set(ref, s.id, SalonStatus.rejected),
                      child: Text(l10n.rejectButton),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 2: Write a widget test.** Create `barbershop/test/features/admin/admin_approvals_screen_test.dart`:

```dart
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

    final salon = Salon(
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
```

- [ ] **Step 3: Run the widget test.**

Run: `cd barbershop && flutter test test/features/admin/admin_approvals_screen_test.dart`
Expected: PASS.

- [ ] **Step 4: Commit.**

```bash
git add barbershop/lib/features/admin/presentation/admin_approvals_screen.dart barbershop/test/features/admin/admin_approvals_screen_test.dart
git commit -m "feat(admin): pending-salon approvals screen"
```

---

## Task 9: Wire routes and the customer "register salon" entry

**Files:**
- Modify: `barbershop/lib/core/router/app_router.dart`, `barbershop/lib/features/home/presentation/customer_home_screen.dart`
- Test: `barbershop/test/features/auth/role_routing_test.dart` (extend)

**Interfaces:**
- Consumes: `SalonRegistrationScreen` (Task 6), `SalonDashboardScreen` (Task 7), `AdminApprovalsScreen` (Task 8).
- Produces: routes `/salon/register` (registration), `/salon` now renders `SalonDashboardScreen`, `/admin` now renders `AdminApprovalsScreen`; `resolveRedirect` unchanged in signature (still routes by role). Customer home gains an "Inscrire mon salon" button that navigates to `/salon/register`.

- [ ] **Step 1: Add a regression test for the registration route staying reachable by a customer.** In `barbershop/test/features/auth/role_routing_test.dart`, add inside the `group('resolveRedirect', ...)`:

```dart
    test('customer is not redirected away from /salon/register', () {
      expect(
        resolveRedirect(
          isLoggedIn: true,
          role: UserRole.customer,
          location: '/salon/register',
        ),
        isNull,
      );
    });
```

- [ ] **Step 2: Run it to verify it fails.**

Run: `cd barbershop && flutter test test/features/auth/role_routing_test.dart`
Expected: FAIL — a customer on `/salon/register` is currently redirected to `/home` (the test expects `isNull`).

- [ ] **Step 3: Update `resolveRedirect` to treat `/salon/register` as allowed for any logged-in user.** In `barbershop/lib/core/router/app_router.dart`, change the public-routes handling so the registration path is exempt from role redirects. Replace the constant and the post-login block:

Replace:
```dart
const _publicRoutes = {'/login', '/signup'};
```
with:
```dart
const _publicRoutes = {'/login', '/signup'};

// Logged-in users may visit these regardless of their role/home.
const _neutralRoutes = {'/salon/register'};
```

Replace:
```dart
  final target = _homeFor(role);
  if (onPublicRoute || location == '/') return target;
  return null;
```
with:
```dart
  if (_neutralRoutes.contains(location)) return null;

  final target = _homeFor(role);
  if (onPublicRoute || location == '/') return target;
  return null;
```

- [ ] **Step 4: Wire the new screens and route.** In `barbershop/lib/core/router/app_router.dart`, update imports and routes. Replace the home-screen imports:

```dart
import '../../features/home/presentation/admin_home_screen.dart';
import '../../features/home/presentation/customer_home_screen.dart';
import '../../features/home/presentation/salon_home_screen.dart';
```
with:
```dart
import '../../features/admin/presentation/admin_approvals_screen.dart';
import '../../features/home/presentation/customer_home_screen.dart';
import '../../features/salon/presentation/salon_dashboard_screen.dart';
import '../../features/salon/presentation/salon_registration_screen.dart';
```

Then replace the `/salon`, `/admin` routes and add `/salon/register`:

```dart
      GoRoute(path: '/home', builder: (_, __) => const CustomerHomeScreen()),
      GoRoute(
        path: '/salon/register',
        builder: (_, __) => const SalonRegistrationScreen(),
      ),
      GoRoute(path: '/salon', builder: (_, __) => const SalonDashboardScreen()),
      GoRoute(path: '/admin', builder: (_, __) => const AdminApprovalsScreen()),
```

(Leave `/`, `/login`, `/signup` as-is. The old `salon_home_screen.dart`/`admin_home_screen.dart` are now unused; leave the files in place — they are removed in a later cleanup task to keep this diff focused.)

- [ ] **Step 5: Add the "register salon" entry to the customer home.** In `barbershop/lib/features/home/presentation/customer_home_screen.dart`, add a go_router import and a button. Replace the file body's import block and `body:` with:

Add import after the existing imports:
```dart
import 'package:go_router/go_router.dart';
```

Replace:
```dart
      body: Center(child: Text(l10n.customerHomeTitle)),
```
with:
```dart
      body: Center(
        child: FilledButton.tonal(
          onPressed: () => context.go('/salon/register'),
          child: Text(l10n.registerSalonButton),
        ),
      ),
```

- [ ] **Step 6: Run routing tests and analyze.**

Run: `flutter test test/features/auth/role_routing_test.dart && flutter analyze lib/core/router lib/features/home lib/features/salon lib/features/admin`
Expected: routing tests PASS (8 now); analyzer clean.

- [ ] **Step 7: Commit.**

```bash
git add barbershop/lib/core/router/app_router.dart barbershop/lib/features/home/presentation/customer_home_screen.dart barbershop/test/features/auth/role_routing_test.dart
git commit -m "feat(router): salon registration/dashboard and admin approvals routes"
```

---

## Task 10: End-to-end verification

**Files:** none (verification + optional cleanup commit).

**Interfaces:** consumes the running local Supabase.

- [ ] **Step 1: Full analyzer + unit/widget suite.**

Run: `cd barbershop && flutter analyze && flutter test`
Expected: analyzer clean; all tests pass (Plan 1 + Plan 2). Note the totals.

- [ ] **Step 2: RLS / RPC pgTAP suite.**

Run (from repo root): `supabase test db`
Expected: both `profiles_rls_test.sql` and `salons_rls_test.sql` pass.

- [ ] **Step 3: Web build.**

Run:
```bash
cd barbershop && flutter build web \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<local publishable key>
```
Expected: `✓ Built build/web`.

- [ ] **Step 4: Live API check of the onboarding → approval flow.** Against the local stack, sign up a user, call `register_salon` as that user, confirm the salon is `pending` and the profile is now `salon_owner`, then approve it as an admin and confirm it is visible. Use the project's Postgres container for the role/admin setup:

```bash
# Sign up a future owner (captures the access token for RPC calls)
KEY="<local publishable key>"
EMAIL="owner_$(date +%s)@test.dev"
RESP=$(curl -s -X POST "http://127.0.0.1:54321/auth/v1/signup" \
  -H "apikey: $KEY" -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"secret123\"}")
TOKEN=$(echo "$RESP" | jq -r '.access_token')

# Register a salon as that user via the RPC (PostgREST exposes it at /rest/v1/rpc)
curl -s -X POST "http://127.0.0.1:54321/rest/v1/rpc/register_salon" \
  -H "apikey: $KEY" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"p_name":"E2E Salon","p_city":"Tunis"}'

# Confirm via the container: salon pending + owner role elevated
CID=$(docker ps --filter "name=supabase_db" --format "{{.Names}}" | head -1)
docker exec -i "$CID" psql -U postgres -d postgres -c \
  "select s.name, s.status, p.role from public.salons s join public.profiles p on p.id=s.owner_id order by s.created_at desc limit 1;"
```
Expected: one row — `E2E Salon | pending | salon_owner`.

- [ ] **Step 5: Document the result.** Append a short "Plan 2" section to `barbershop/README.md` noting the onboarding→approval flow and that owners manage their profile from the salon dashboard. Commit:

```bash
git add barbershop/README.md
git commit -m "docs: salon onboarding and approval flow"
```

---

## Self-Review

**Spec coverage (design §5 salons, §6 salon side, §6 admin, §9 security):**
- `salons` table with status + `show_prices` + rating fields → Task 1. ✓
- Owner self-registration with admin approval; role elevation customer→salon_owner → Tasks 1 (RPC), 6 (flow). ✓
- Admin approve/reject → Tasks 1 (`set_salon_status`, `is_admin`), 4, 8. ✓
- Owner edits salon profile incl. show-prices toggle → Tasks 3, 7. ✓
- Public reads approved salons; pending/own/admin-only visibility → Task 1 RLS + pgTAP. ✓
- Owners cannot self-approve (writes via SECURITY DEFINER RPCs; no write policy; `update_my_salon` never touches status) → Task 1. ✓
- Localization-ready, French, no hardcoded text → Task 5. ✓
- *Deferred to later plans (correct):* services/staff/working-hours management (Plan 3), salon_media/photos + visual feed (discovery plan), bookings/caisse/reviews, cover-image upload via Storage.

**Placeholder scan:** No TBD/TODO; every code step has complete code; commands have expected output. The only intentionally deferred item (removing the now-unused `salon_home_screen.dart`/`admin_home_screen.dart`) is explicitly called out in Task 9 Step 4, not left implicit. ✓

**Type consistency:** RPC param names match between Dart repos (Tasks 3, 4) and the SQL functions (Task 1): `register_salon(p_name,p_city,p_description,p_address)`, `update_my_salon(p_name,p_description,p_city,p_address,p_show_prices)`, `set_salon_status(p_salon_id,p_status)`. `SalonStatus.dbValue` strings match the `salon_status` enum. `mySalonProvider`/`pendingSalonsProvider` defined in Tasks 3/4 and consumed in Tasks 6–9. Riverpod 3.x API (`AsyncNotifier`, `AsyncValue.isLoading/.hasError/.error`, `.overrideWith` returning a Future) consistent with Plan 1. ✓
