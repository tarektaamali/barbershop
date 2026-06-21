# Salon Content Management (Services & Staff) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An approved salon owner can manage their **services** (name, duration, price) and **staff** (name, specialty, active) from the salon dashboard. The public can read the services and staff of approved salons.

**Architecture:** Builds on Plans 1–2. Adds `services` and `staff` tables, RLS for **reads** (services/staff of approved salons are public; owner/admin see their own), and `SECURITY DEFINER` RPCs for all **writes** (guarded by an `owns_salon()` helper so only the owning salon_owner can mutate). Flutter side adds `Service`/`Staff` models, `ServiceRepository`/`StaffRepository` (family providers keyed by salon id), and turns the approved-salon dashboard into a tabbed view (Profil / Services / Équipe).

**Tech Stack:** Flutter 3.35, Dart 3.9, `supabase_flutter` v2, `flutter_riverpod` v3, `go_router` v17, `mocktail`, Supabase CLI + Docker (pgTAP).

## Global Constraints

Carry over from Plans 1–2 (verified against the real codebase):

- **Riverpod 3.x:** `AsyncNotifier`/`AsyncNotifierProvider` (auto-dispose by default, no `AutoDispose*`). `AsyncValue.value` (no `valueOrNull`). The `Override` type is NOT importable by name in this build — in widget tests, write helpers that take domain values (e.g. a status or a list) and build the `ProviderScope` overrides internally, rather than a parameter typed `List<Override>`.
- **Localization:** strings live in `lib/l10n/app_fr.arb`; run `flutter gen-l10n` **from the `barbershop/` directory** (cwd resets between shell calls); generated files are committed. Import `package:barbershop/l10n/app_localizations.dart`. No hardcoded UI text. French only.
- **RLS + RPC writes:** tables enable RLS with `grant select to anon, authenticated` and a read policy; all writes go through `SECURITY DEFINER` RPCs (no write policy on the table). Mirror Plan 2's `salons` pattern.
- **Testing PostgREST/RPC:** `SupabaseClient.rpc(...)` returns a `PostgrestFilterBuilder` (Future-like), so unit tests stub it with `thenAnswer((_) => FakeFilterBuilder<dynamic>(value))` using the existing helper `test/support/fake_postgrest.dart`. `thenReturn` is rejected by mocktail for Futures.
- **Existing interfaces:** `supabaseClientProvider`; `currentProfileProvider`, `authRepositoryProvider`; `Salon`/`SalonStatus`, `salonRepositoryProvider`, `mySalonProvider`; `is_admin()` SQL helper; salon dashboard at `lib/features/salon/presentation/salon_dashboard_screen.dart` (renders `SalonProfileForm` when the salon is approved).
- **TDD:** failing test first; commit after each green step.
- **Working dir:** Flutter commands from `barbershop/`; `supabase` commands from repo root `/Users/macbook/Desktop/DEVCAMP`.

---

## File Structure

```
barbershop/
├── lib/features/salon/
│   ├── domain/service.dart                 # Service model
│   ├── domain/staff.dart                   # Staff model
│   ├── data/service_repository.dart        # ServiceRepository + servicesProvider(salonId)
│   ├── data/staff_repository.dart          # StaffRepository + staffProvider(salonId)
│   └── presentation/
│       ├── salon_manage_tabs.dart          # tabbed Profil/Services/Équipe (approved)
│       ├── services_tab.dart               # list + add/edit/deactivate services
│       └── staff_tab.dart                  # list + add/edit/deactivate staff
│   └── presentation/salon_dashboard_screen.dart   # MODIFY: approved -> SalonManageTabs
├── lib/l10n/app_fr.arb                      # MODIFY: add strings
├── test/features/salon/...                  # model + repo + widget tests
└── supabase/
    ├── migrations/0003_services_staff.sql
    └── tests/services_staff_rls_test.sql
```

---

## Task 1: Services & staff schema, RLS, and RPCs (pgTAP)

**Files:**
- Create: `supabase/migrations/0003_services_staff.sql`, `supabase/tests/services_staff_rls_test.sql`

**Interfaces:**
- Consumes: `public.salons`, `public.is_admin()` (Plan 2).
- Produces:
  - tables `public.services`, `public.staff`.
  - `public.owns_salon(p_salon_id uuid) returns boolean`.
  - `public.add_service(p_salon_id uuid, p_name text, p_duration_min int, p_price numeric) returns uuid`.
  - `public.update_service(p_service_id uuid, p_name text, p_duration_min int, p_price numeric) returns void`.
  - `public.set_service_active(p_service_id uuid, p_active boolean) returns void`.
  - `public.add_staff(p_salon_id uuid, p_display_name text, p_specialty text) returns uuid`.
  - `public.update_staff(p_staff_id uuid, p_display_name text, p_specialty text) returns void`.
  - `public.set_staff_active(p_staff_id uuid, p_active boolean) returns void`.

- [ ] **Step 1: Write the migration.** Create `supabase/migrations/0003_services_staff.sql`:

```sql
create table public.services (
  id           uuid primary key default gen_random_uuid(),
  salon_id     uuid not null references public.salons (id) on delete cascade,
  name         text not null,
  duration_min integer not null,
  price        numeric(8,2) not null default 0,
  active       boolean not null default true,
  created_at   timestamptz not null default now()
);

create table public.staff (
  id           uuid primary key default gen_random_uuid(),
  salon_id     uuid not null references public.salons (id) on delete cascade,
  profile_id   uuid references auth.users (id) on delete set null,
  display_name text not null,
  avatar_url   text,
  specialty    text,
  active       boolean not null default true,
  created_at   timestamptz not null default now()
);

create index services_salon_idx on public.services (salon_id);
create index staff_salon_idx on public.staff (salon_id);

alter table public.services enable row level security;
alter table public.staff enable row level security;

grant select on public.services to anon, authenticated;
grant select on public.staff to anon, authenticated;

-- Readable when the parent salon is approved, owned by the caller, or caller is admin.
create policy "services_select_visible"
  on public.services for select
  using (exists (
    select 1 from public.salons s
    where s.id = services.salon_id
      and (s.status = 'approved' or s.owner_id = auth.uid() or public.is_admin())
  ));

create policy "staff_select_visible"
  on public.staff for select
  using (exists (
    select 1 from public.salons s
    where s.id = staff.salon_id
      and (s.status = 'approved' or s.owner_id = auth.uid() or public.is_admin())
  ));

-- True when the caller owns the given salon.
create function public.owns_salon(p_salon_id uuid)
  returns boolean
  language sql
  security definer
  stable
  set search_path = public
as $$
  select exists (
    select 1 from public.salons where id = p_salon_id and owner_id = auth.uid()
  );
$$;

-- Services -----------------------------------------------------------------
create function public.add_service(
  p_salon_id uuid, p_name text, p_duration_min int, p_price numeric
)
  returns uuid language plpgsql security definer set search_path = public
as $$
declare v_id uuid;
begin
  if not public.owns_salon(p_salon_id) then raise exception 'forbidden'; end if;
  insert into public.services (salon_id, name, duration_min, price)
  values (p_salon_id, p_name, p_duration_min, p_price)
  returning id into v_id;
  return v_id;
end;
$$;

create function public.update_service(
  p_service_id uuid, p_name text, p_duration_min int, p_price numeric
)
  returns void language plpgsql security definer set search_path = public
as $$
begin
  update public.services se
    set name = p_name, duration_min = p_duration_min, price = p_price
    where se.id = p_service_id and public.owns_salon(se.salon_id);
end;
$$;

create function public.set_service_active(p_service_id uuid, p_active boolean)
  returns void language plpgsql security definer set search_path = public
as $$
begin
  update public.services se
    set active = p_active
    where se.id = p_service_id and public.owns_salon(se.salon_id);
end;
$$;

-- Staff --------------------------------------------------------------------
create function public.add_staff(
  p_salon_id uuid, p_display_name text, p_specialty text
)
  returns uuid language plpgsql security definer set search_path = public
as $$
declare v_id uuid;
begin
  if not public.owns_salon(p_salon_id) then raise exception 'forbidden'; end if;
  insert into public.staff (salon_id, display_name, specialty)
  values (p_salon_id, p_display_name, p_specialty)
  returning id into v_id;
  return v_id;
end;
$$;

create function public.update_staff(
  p_staff_id uuid, p_display_name text, p_specialty text
)
  returns void language plpgsql security definer set search_path = public
as $$
begin
  update public.staff st
    set display_name = p_display_name, specialty = p_specialty
    where st.id = p_staff_id and public.owns_salon(st.salon_id);
end;
$$;

create function public.set_staff_active(p_staff_id uuid, p_active boolean)
  returns void language plpgsql security definer set search_path = public
as $$
begin
  update public.staff st
    set active = p_active
    where st.id = p_staff_id and public.owns_salon(st.salon_id);
end;
$$;

grant execute on function public.owns_salon(uuid) to authenticated;
grant execute on function public.add_service(uuid, text, int, numeric) to authenticated;
grant execute on function public.update_service(uuid, text, int, numeric) to authenticated;
grant execute on function public.set_service_active(uuid, boolean) to authenticated;
grant execute on function public.add_staff(uuid, text, text) to authenticated;
grant execute on function public.update_staff(uuid, text, text) to authenticated;
grant execute on function public.set_staff_active(uuid, boolean) to authenticated;
```

- [ ] **Step 2: Apply the migration.**

Run (repo root): `supabase db reset`
Expected: applies `0001`, `0002`, `0003` with no error.

- [ ] **Step 3: Write the failing pgTAP test.** Create `supabase/tests/services_staff_rls_test.sql`:

```sql
begin;
select plan(5);

insert into auth.users (id, email) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'owner@test.dev'),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'stranger@test.dev');

-- Owner registers and gets an approved salon (approve directly as table owner).
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-0000-0000-000000000001","role":"authenticated"}';
select public.register_salon('Barber House', 'Tunis');

-- Approve the salon out-of-band (as the privileged test role).
set local role postgres;
update public.salons set status = 'approved'
  where owner_id = 'aaaaaaaa-0000-0000-0000-000000000001';

-- Back to the owner: add a service and a staff member via RPCs.
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-0000-0000-000000000001","role":"authenticated"}';

select lives_ok(
  $$ select public.add_service(
       (select id from public.salons where owner_id='aaaaaaaa-0000-0000-0000-000000000001'),
       'Coupe homme', 30, 25) $$,
  'owner can add a service'
);
select lives_ok(
  $$ select public.add_staff(
       (select id from public.salons where owner_id='aaaaaaaa-0000-0000-0000-000000000001'),
       'Karim', 'Dégradé') $$,
  'owner can add a staff member'
);

-- 1. A stranger CAN read services of an approved salon.
set local request.jwt.claims = '{"sub":"bbbbbbbb-0000-0000-0000-000000000002","role":"authenticated"}';
select is(
  (select count(*)::int from public.services),
  1,
  'services of an approved salon are publicly readable'
);

-- 2. A stranger CANNOT add a service to a salon they do not own.
select throws_ok(
  $$ select public.add_service(
       (select id from public.salons limit 1), 'Hack', 10, 5) $$,
  'forbidden',
  'non-owner cannot add a service'
);

-- 3. A stranger CANNOT deactivate another salon's staff (no-op, count unchanged).
select public.set_staff_active(
  (select id from public.staff limit 1), false);
set local role postgres;
select is(
  (select active from public.staff limit 1),
  true,
  'non-owner set_staff_active is a no-op'
);

select * from finish();
rollback;
```

- [ ] **Step 4: Run the pgTAP suite.**

Run (repo root): `supabase test db`
Expected: `services_staff_rls_test.sql` passes all 5 assertions; the existing suites still pass.

- [ ] **Step 5: Commit.**

```bash
git add supabase/migrations/0003_services_staff.sql supabase/tests/services_staff_rls_test.sql
git commit -m "feat(db): services and staff tables with RLS reads and owner-only write RPCs"
```

---

## Task 2: Service model

**Files:**
- Create: `barbershop/lib/features/salon/domain/service.dart`
- Test: `barbershop/test/features/salon/service_test.dart`

**Interfaces:**
- Produces: `class Service { final String id; final String salonId; final String name; final int durationMin; final double price; final bool active; }` with `factory Service.fromMap(Map<String, dynamic>)`.

- [ ] **Step 1: Write the failing test.** Create `barbershop/test/features/salon/service_test.dart`:

```dart
import 'package:barbershop/features/salon/domain/service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Service.fromMap builds from a services row', () {
    final s = Service.fromMap({
      'id': 'sv1',
      'salon_id': 's1',
      'name': 'Coupe homme',
      'duration_min': 30,
      'price': 25,
      'active': true,
    });
    expect(s.id, 'sv1');
    expect(s.salonId, 's1');
    expect(s.name, 'Coupe homme');
    expect(s.durationMin, 30);
    expect(s.price, 25.0);
    expect(s.active, true);
  });
}
```

- [ ] **Step 2: Run it (RED).**

Run: `cd barbershop && flutter test test/features/salon/service_test.dart`
Expected: FAIL — `service.dart` does not exist.

- [ ] **Step 3: Implement the model.** Create `barbershop/lib/features/salon/domain/service.dart`:

```dart
class Service {
  const Service({
    required this.id,
    required this.salonId,
    required this.name,
    required this.durationMin,
    required this.price,
    required this.active,
  });

  final String id;
  final String salonId;
  final String name;
  final int durationMin;
  final double price;
  final bool active;

  factory Service.fromMap(Map<String, dynamic> map) {
    return Service(
      id: map['id'] as String,
      salonId: map['salon_id'] as String,
      name: map['name'] as String,
      durationMin: map['duration_min'] as int,
      price: (map['price'] as num? ?? 0).toDouble(),
      active: map['active'] as bool? ?? true,
    );
  }
}
```

- [ ] **Step 4: Run it (GREEN).**

Run: `flutter test test/features/salon/service_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git add barbershop/lib/features/salon/domain/service.dart barbershop/test/features/salon/service_test.dart
git commit -m "feat(salon): Service model"
```

---

## Task 3: Staff model

**Files:**
- Create: `barbershop/lib/features/salon/domain/staff.dart`
- Test: `barbershop/test/features/salon/staff_test.dart`

**Interfaces:**
- Produces: `class Staff { final String id; final String salonId; final String displayName; final String? specialty; final String? avatarUrl; final bool active; }` with `factory Staff.fromMap(Map<String, dynamic>)`.

- [ ] **Step 1: Write the failing test.** Create `barbershop/test/features/salon/staff_test.dart`:

```dart
import 'package:barbershop/features/salon/domain/staff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Staff.fromMap builds from a staff row', () {
    final s = Staff.fromMap({
      'id': 'st1',
      'salon_id': 's1',
      'display_name': 'Karim',
      'specialty': 'Dégradé',
      'avatar_url': null,
      'active': true,
    });
    expect(s.id, 'st1');
    expect(s.salonId, 's1');
    expect(s.displayName, 'Karim');
    expect(s.specialty, 'Dégradé');
    expect(s.active, true);
  });
}
```

- [ ] **Step 2: Run it (RED).**

Run: `cd barbershop && flutter test test/features/salon/staff_test.dart`
Expected: FAIL — `staff.dart` does not exist.

- [ ] **Step 3: Implement the model.** Create `barbershop/lib/features/salon/domain/staff.dart`:

```dart
class Staff {
  const Staff({
    required this.id,
    required this.salonId,
    required this.displayName,
    required this.active,
    this.specialty,
    this.avatarUrl,
  });

  final String id;
  final String salonId;
  final String displayName;
  final String? specialty;
  final String? avatarUrl;
  final bool active;

  factory Staff.fromMap(Map<String, dynamic> map) {
    return Staff(
      id: map['id'] as String,
      salonId: map['salon_id'] as String,
      displayName: map['display_name'] as String,
      specialty: map['specialty'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      active: map['active'] as bool? ?? true,
    );
  }
}
```

- [ ] **Step 4: Run it (GREEN).**

Run: `flutter test test/features/salon/staff_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git add barbershop/lib/features/salon/domain/staff.dart barbershop/test/features/salon/staff_test.dart
git commit -m "feat(salon): Staff model"
```

---

## Task 4: ServiceRepository

**Files:**
- Create: `barbershop/lib/features/salon/data/service_repository.dart`
- Test: `barbershop/test/features/salon/service_repository_test.dart`

**Interfaces:**
- Consumes: `supabaseClientProvider`; `Service` (Task 2).
- Produces:
  - `class ServiceRepository` with:
    - `Future<List<Service>> fetchForSalon(String salonId)` → `from('services').select().eq('salon_id', salonId).order('created_at')`.
    - `Future<String> addService({required String salonId, required String name, required int durationMin, required double price})` → `rpc('add_service', ...)` returns id.
    - `Future<void> updateService({required String id, required String name, required int durationMin, required double price})` → `rpc('update_service', ...)`.
    - `Future<void> setActive(String id, bool active)` → `rpc('set_service_active', ...)`.
  - `final serviceRepositoryProvider = Provider<ServiceRepository>(...)`.
  - `final servicesProvider = FutureProvider.family<List<Service>, String>(...)` keyed by salon id.

- [ ] **Step 1: Write the failing test.** Create `barbershop/test/features/salon/service_repository_test.dart`:

```dart
import 'package:barbershop/features/salon/data/service_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/fake_postgrest.dart';

class _MockClient extends Mock implements SupabaseClient {}

void main() {
  late _MockClient client;
  late ServiceRepository repo;

  setUp(() {
    client = _MockClient();
    repo = ServiceRepository(client);
  });

  test('addService calls add_service RPC and returns the id', () async {
    when(() => client.rpc('add_service', params: any(named: 'params')))
        .thenAnswer((_) => FakeFilterBuilder<dynamic>('sv1'));

    final id = await repo.addService(
      salonId: 's1',
      name: 'Coupe homme',
      durationMin: 30,
      price: 25,
    );

    expect(id, 'sv1');
    verify(() => client.rpc('add_service', params: {
          'p_salon_id': 's1',
          'p_name': 'Coupe homme',
          'p_duration_min': 30,
          'p_price': 25.0,
        })).called(1);
  });

  test('setActive calls set_service_active RPC', () async {
    when(() => client.rpc('set_service_active', params: any(named: 'params')))
        .thenAnswer((_) => FakeFilterBuilder<dynamic>(null));

    await repo.setActive('sv1', false);

    verify(() => client.rpc('set_service_active', params: {
          'p_service_id': 'sv1',
          'p_active': false,
        })).called(1);
  });
}
```

- [ ] **Step 2: Run it (RED).**

Run: `cd barbershop && flutter test test/features/salon/service_repository_test.dart`
Expected: FAIL — `service_repository.dart` does not exist.

- [ ] **Step 3: Implement the repository.** Create `barbershop/lib/features/salon/data/service_repository.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/service.dart';

class ServiceRepository {
  ServiceRepository(this._client);

  final SupabaseClient _client;

  Future<List<Service>> fetchForSalon(String salonId) async {
    final rows = await _client
        .from('services')
        .select()
        .eq('salon_id', salonId)
        .order('created_at');
    return (rows as List)
        .map((r) => Service.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<String> addService({
    required String salonId,
    required String name,
    required int durationMin,
    required double price,
  }) async {
    final id = await _client.rpc('add_service', params: {
      'p_salon_id': salonId,
      'p_name': name,
      'p_duration_min': durationMin,
      'p_price': price,
    });
    return id as String;
  }

  Future<void> updateService({
    required String id,
    required String name,
    required int durationMin,
    required double price,
  }) async {
    await _client.rpc('update_service', params: {
      'p_service_id': id,
      'p_name': name,
      'p_duration_min': durationMin,
      'p_price': price,
    });
  }

  Future<void> setActive(String id, bool active) async {
    await _client.rpc('set_service_active', params: {
      'p_service_id': id,
      'p_active': active,
    });
  }
}

final serviceRepositoryProvider = Provider<ServiceRepository>((ref) {
  return ServiceRepository(ref.watch(supabaseClientProvider));
});

final servicesProvider =
    FutureProvider.family<List<Service>, String>((ref, salonId) async {
  return ref.watch(serviceRepositoryProvider).fetchForSalon(salonId);
});
```

- [ ] **Step 4: Run it (GREEN).**

Run: `flutter test test/features/salon/service_repository_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit.**

```bash
git add barbershop/lib/features/salon/data/service_repository.dart barbershop/test/features/salon/service_repository_test.dart
git commit -m "feat(salon): ServiceRepository with CRUD RPCs and servicesProvider"
```

---

## Task 5: StaffRepository

**Files:**
- Create: `barbershop/lib/features/salon/data/staff_repository.dart`
- Test: `barbershop/test/features/salon/staff_repository_test.dart`

**Interfaces:**
- Consumes: `supabaseClientProvider`; `Staff` (Task 3).
- Produces:
  - `class StaffRepository` with:
    - `Future<List<Staff>> fetchForSalon(String salonId)` → `from('staff').select().eq('salon_id', salonId).order('created_at')`.
    - `Future<String> addStaff({required String salonId, required String displayName, String? specialty})` → `rpc('add_staff', ...)`.
    - `Future<void> updateStaff({required String id, required String displayName, String? specialty})` → `rpc('update_staff', ...)`.
    - `Future<void> setActive(String id, bool active)` → `rpc('set_staff_active', ...)`.
  - `final staffRepositoryProvider = Provider<StaffRepository>(...)`.
  - `final staffProvider = FutureProvider.family<List<Staff>, String>(...)` keyed by salon id.

- [ ] **Step 1: Write the failing test.** Create `barbershop/test/features/salon/staff_repository_test.dart`:

```dart
import 'package:barbershop/features/salon/data/staff_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/fake_postgrest.dart';

class _MockClient extends Mock implements SupabaseClient {}

void main() {
  late _MockClient client;
  late StaffRepository repo;

  setUp(() {
    client = _MockClient();
    repo = StaffRepository(client);
  });

  test('addStaff calls add_staff RPC and returns the id', () async {
    when(() => client.rpc('add_staff', params: any(named: 'params')))
        .thenAnswer((_) => FakeFilterBuilder<dynamic>('st1'));

    final id = await repo.addStaff(
      salonId: 's1',
      displayName: 'Karim',
      specialty: 'Dégradé',
    );

    expect(id, 'st1');
    verify(() => client.rpc('add_staff', params: {
          'p_salon_id': 's1',
          'p_display_name': 'Karim',
          'p_specialty': 'Dégradé',
        })).called(1);
  });

  test('setActive calls set_staff_active RPC', () async {
    when(() => client.rpc('set_staff_active', params: any(named: 'params')))
        .thenAnswer((_) => FakeFilterBuilder<dynamic>(null));

    await repo.setActive('st1', false);

    verify(() => client.rpc('set_staff_active', params: {
          'p_staff_id': 'st1',
          'p_active': false,
        })).called(1);
  });
}
```

- [ ] **Step 2: Run it (RED).**

Run: `cd barbershop && flutter test test/features/salon/staff_repository_test.dart`
Expected: FAIL — `staff_repository.dart` does not exist.

- [ ] **Step 3: Implement the repository.** Create `barbershop/lib/features/salon/data/staff_repository.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/staff.dart';

class StaffRepository {
  StaffRepository(this._client);

  final SupabaseClient _client;

  Future<List<Staff>> fetchForSalon(String salonId) async {
    final rows = await _client
        .from('staff')
        .select()
        .eq('salon_id', salonId)
        .order('created_at');
    return (rows as List)
        .map((r) => Staff.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<String> addStaff({
    required String salonId,
    required String displayName,
    String? specialty,
  }) async {
    final id = await _client.rpc('add_staff', params: {
      'p_salon_id': salonId,
      'p_display_name': displayName,
      'p_specialty': specialty,
    });
    return id as String;
  }

  Future<void> updateStaff({
    required String id,
    required String displayName,
    String? specialty,
  }) async {
    await _client.rpc('update_staff', params: {
      'p_staff_id': id,
      'p_display_name': displayName,
      'p_specialty': specialty,
    });
  }

  Future<void> setActive(String id, bool active) async {
    await _client.rpc('set_staff_active', params: {
      'p_staff_id': id,
      'p_active': active,
    });
  }
}

final staffRepositoryProvider = Provider<StaffRepository>((ref) {
  return StaffRepository(ref.watch(supabaseClientProvider));
});

final staffProvider =
    FutureProvider.family<List<Staff>, String>((ref, salonId) async {
  return ref.watch(staffRepositoryProvider).fetchForSalon(salonId);
});
```

- [ ] **Step 4: Run it (GREEN).**

Run: `flutter test test/features/salon/staff_repository_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit.**

```bash
git add barbershop/lib/features/salon/data/staff_repository.dart barbershop/test/features/salon/staff_repository_test.dart
git commit -m "feat(salon): StaffRepository with CRUD RPCs and staffProvider"
```

---

## Task 6: Localization strings

**Files:**
- Modify: `barbershop/lib/l10n/app_fr.arb`

**Interfaces:**
- Produces (added to `AppLocalizations`): `tabProfile`, `tabServices`, `tabStaff`, `addServiceTitle`, `editServiceTitle`, `serviceNameLabel`, `serviceDurationLabel`, `servicePriceLabel`, `addStaffTitle`, `editStaffTitle`, `staffNameLabel`, `staffSpecialtyLabel`, `noServices`, `noStaff`, `addButton`, `deactivateButton`, `activateButton`, `minutesSuffix`.

- [ ] **Step 1: Add the strings.** In `barbershop/lib/l10n/app_fr.arb`, add these keys before the closing brace (ensure the preceding line ends with a comma):

```json
  "tabProfile": "Profil",
  "tabServices": "Services",
  "tabStaff": "Équipe",
  "addServiceTitle": "Ajouter un service",
  "editServiceTitle": "Modifier le service",
  "serviceNameLabel": "Nom du service",
  "serviceDurationLabel": "Durée (min)",
  "servicePriceLabel": "Prix (DT)",
  "addStaffTitle": "Ajouter un coiffeur",
  "editStaffTitle": "Modifier le coiffeur",
  "staffNameLabel": "Nom",
  "staffSpecialtyLabel": "Spécialité",
  "noServices": "Aucun service",
  "noStaff": "Aucun coiffeur",
  "addButton": "Ajouter",
  "deactivateButton": "Désactiver",
  "activateButton": "Activer",
  "minutesSuffix": "min"
```

- [ ] **Step 2: Regenerate localizations (from the project dir).**

Run: `cd barbershop && flutter gen-l10n`
Expected: regenerates `lib/l10n/app_localizations*.dart`; no errors.

- [ ] **Step 3: Verify it compiles.**

Run: `flutter analyze lib/l10n`
Expected: No issues found.

- [ ] **Step 4: Commit.**

```bash
git add barbershop/lib/l10n/
git commit -m "feat(l10n): services and staff management strings"
```

---

## Task 7: Tabbed salon dashboard (Profil / Services / Équipe)

**Files:**
- Create: `barbershop/lib/features/salon/presentation/salon_manage_tabs.dart`
- Modify: `barbershop/lib/features/salon/presentation/salon_dashboard_screen.dart`
- Test: `barbershop/test/features/salon/salon_manage_tabs_test.dart`

**Interfaces:**
- Consumes: `Salon` (Plan 2), `SalonProfileForm` (Plan 2), `ServicesTab`/`StaffTab` (Tasks 8–9, referenced here).
- Produces: `class SalonManageTabs extends StatelessWidget` taking a `Salon` — a `DefaultTabController` with three tabs (Profil → `SalonProfileForm`, Services → `ServicesTab(salonId)`, Équipe → `StaffTab(salonId)`). `SalonDashboardScreen` renders `SalonManageTabs(salon: salon)` instead of `SalonProfileForm` for an approved salon.

- [ ] **Step 1: Create the tabbed widget.** Create `barbershop/lib/features/salon/presentation/salon_manage_tabs.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/salon.dart';
import 'salon_profile_form.dart';
import 'services_tab.dart';
import 'staff_tab.dart';

class SalonManageTabs extends StatelessWidget {
  const SalonManageTabs({required this.salon, super.key});

  final Salon salon;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(text: l10n.tabProfile),
              Tab(text: l10n.tabServices),
              Tab(text: l10n.tabStaff),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                SalonProfileForm(salon: salon),
                ServicesTab(salonId: salon.id),
                StaffTab(salonId: salon.id),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Wire it into the dashboard.** In `barbershop/lib/features/salon/presentation/salon_dashboard_screen.dart`, replace the import of `salon_profile_form.dart` with `salon_manage_tabs.dart`:

Replace:
```dart
import 'salon_profile_form.dart';
```
with:
```dart
import 'salon_manage_tabs.dart';
```

And replace the approved case:
```dart
            case SalonStatus.approved:
              return SalonProfileForm(salon: salon);
```
with:
```dart
            case SalonStatus.approved:
              return SalonManageTabs(salon: salon);
```

- [ ] **Step 3: Write a widget test (after Tasks 8–9 exist this compiles; create the test now and it will pass once tabs render).** Create `barbershop/test/features/salon/salon_manage_tabs_test.dart`:

```dart
import 'package:barbershop/features/salon/data/service_repository.dart';
import 'package:barbershop/features/salon/data/staff_repository.dart';
import 'package:barbershop/features/salon/domain/salon.dart';
import 'package:barbershop/features/salon/presentation/salon_manage_tabs.dart';
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
  ratingAvg: 0,
  ratingCount: 0,
);

void main() {
  testWidgets('shows the three management tabs', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          servicesProvider('s1').overrideWith((ref) async => []),
          staffProvider('s1').overrideWith((ref) async => []),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: [Locale('fr')],
          home: Scaffold(body: SalonManageTabs(salon: _salon)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Profil'), findsOneWidget);
    expect(find.text('Services'), findsOneWidget);
    expect(find.text('Équipe'), findsOneWidget);
  });
}
```

- [ ] **Step 4: (Deferred run.)** This test needs `ServicesTab`/`StaffTab` from Tasks 8–9 to compile. Implement Tasks 8 and 9, then run it in Task 9 Step 4. Do not run in isolation now.

- [ ] **Step 5: Commit (after Tasks 8–9 make it compile — see Task 9).** Commit `salon_manage_tabs.dart`, the dashboard change, and the test together in Task 9's final commit. (No standalone commit here; the tabbed shell is meaningless without its tabs.)

> Implementation note: Tasks 7–9 form one coherent unit (the shell needs its tabs to compile). Build `salon_manage_tabs.dart` (Step 1) and the dashboard wiring (Step 2) now, then Tasks 8 and 9, then run the full set and commit once at the end of Task 9.

---

## Task 8: Services management tab

**Files:**
- Create: `barbershop/lib/features/salon/presentation/services_tab.dart`
- Test: `barbershop/test/features/salon/services_tab_test.dart`

**Interfaces:**
- Consumes: `servicesProvider` / `serviceRepositoryProvider` (Task 4); `Service`; `AppLocalizations`.
- Produces: `class ServicesTab extends ConsumerWidget` taking `salonId` — lists services (name, duration, price), an **Ajouter** button opening an add dialog (`_ServiceDialog`), tap-to-edit, and an activate/deactivate action. Mutations call the repository then invalidate `servicesProvider(salonId)`.

- [ ] **Step 1: Create the tab.** Create `barbershop/lib/features/salon/presentation/services_tab.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../data/service_repository.dart';
import '../domain/service.dart';

class ServicesTab extends ConsumerWidget {
  const ServicesTab({required this.salonId, super.key});

  final String salonId;

  Future<void> _openDialog(BuildContext context, WidgetRef ref,
      {Service? existing}) async {
    final result = await showDialog<_ServiceFormResult>(
      context: context,
      builder: (_) => _ServiceDialog(existing: existing),
    );
    if (result == null) return;
    final repo = ref.read(serviceRepositoryProvider);
    if (existing == null) {
      await repo.addService(
        salonId: salonId,
        name: result.name,
        durationMin: result.durationMin,
        price: result.price,
      );
    } else {
      await repo.updateService(
        id: existing.id,
        name: result.name,
        durationMin: result.durationMin,
        price: result.price,
      );
    }
    ref.invalidate(servicesProvider(salonId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final services = ref.watch(servicesProvider(salonId));

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openDialog(context, ref),
        icon: const Icon(Icons.add),
        label: Text(l10n.addButton),
      ),
      body: services.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (items) {
          if (items.isEmpty) {
            return Center(child: Text(l10n.noServices));
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final s = items[i];
              return ListTile(
                title: Text(s.name),
                subtitle: Text(
                  '${s.durationMin} ${l10n.minutesSuffix} · ${s.price.toStringAsFixed(0)} DT',
                ),
                onTap: () => _openDialog(context, ref, existing: s),
                trailing: TextButton(
                  onPressed: () async {
                    await ref
                        .read(serviceRepositoryProvider)
                        .setActive(s.id, !s.active);
                    ref.invalidate(servicesProvider(salonId));
                  },
                  child: Text(
                    s.active ? l10n.deactivateButton : l10n.activateButton,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ServiceFormResult {
  _ServiceFormResult(this.name, this.durationMin, this.price);
  final String name;
  final int durationMin;
  final double price;
}

class _ServiceDialog extends StatefulWidget {
  const _ServiceDialog({this.existing});
  final Service? existing;

  @override
  State<_ServiceDialog> createState() => _ServiceDialogState();
}

class _ServiceDialogState extends State<_ServiceDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _duration = TextEditingController(
      text: widget.existing?.durationMin.toString() ?? '');
  late final TextEditingController _price = TextEditingController(
      text: widget.existing?.price.toStringAsFixed(0) ?? '');

  @override
  void dispose() {
    _name.dispose();
    _duration.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(widget.existing == null
          ? l10n.addServiceTitle
          : l10n.editServiceTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('serviceName'),
            controller: _name,
            decoration: InputDecoration(labelText: l10n.serviceNameLabel),
          ),
          TextField(
            key: const Key('serviceDuration'),
            controller: _duration,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l10n.serviceDurationLabel),
          ),
          TextField(
            key: const Key('servicePrice'),
            controller: _price,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l10n.servicePriceLabel),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _ServiceFormResult(
              _name.text.trim(),
              int.tryParse(_duration.text.trim()) ?? 0,
              double.tryParse(_price.text.trim()) ?? 0,
            ),
          ),
          child: Text(l10n.addButton),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: (Run with Task 9.)** This compiles independently; its widget test is Step 3. Run after Task 9 alongside the rest of the suite (see Task 9 Step 4).

- [ ] **Step 3: Write a widget test.** Create `barbershop/test/features/salon/services_tab_test.dart`:

```dart
import 'package:barbershop/features/salon/data/service_repository.dart';
import 'package:barbershop/features/salon/domain/service.dart';
import 'package:barbershop/features/salon/presentation/services_tab.dart';
import 'package:barbershop/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(List<Service> services) => ProviderScope(
      overrides: [
        servicesProvider('s1').overrideWith((ref) async => services),
      ],
      child: const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [Locale('fr')],
        home: ServicesTab(salonId: 's1'),
      ),
    );

void main() {
  testWidgets('renders a service row', (tester) async {
    await tester.pumpWidget(_wrap(const [
      Service(
        id: 'sv1',
        salonId: 's1',
        name: 'Coupe homme',
        durationMin: 30,
        price: 25,
        active: true,
      ),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('Coupe homme'), findsOneWidget);
    expect(find.textContaining('30'), findsWidgets);
  });

  testWidgets('empty state shows no-services message', (tester) async {
    await tester.pumpWidget(_wrap(const []));
    await tester.pumpAndSettle();
    expect(find.text('Aucun service'), findsOneWidget);
  });
}
```

- [ ] **Step 4: (Run with Task 9.)** Run in Task 9 Step 4 with the full suite.

---

## Task 9: Staff management tab (and run/commit the Tasks 7–9 unit)

**Files:**
- Create: `barbershop/lib/features/salon/presentation/staff_tab.dart`
- Test: `barbershop/test/features/salon/staff_tab_test.dart`

**Interfaces:**
- Consumes: `staffProvider` / `staffRepositoryProvider` (Task 5); `Staff`; `AppLocalizations`.
- Produces: `class StaffTab extends ConsumerWidget` taking `salonId` — lists staff (name, specialty), an **Ajouter** button opening an add dialog, tap-to-edit, and an activate/deactivate action. Mirrors `ServicesTab` structure.

- [ ] **Step 1: Create the tab.** Create `barbershop/lib/features/salon/presentation/staff_tab.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../data/staff_repository.dart';
import '../domain/staff.dart';

class StaffTab extends ConsumerWidget {
  const StaffTab({required this.salonId, super.key});

  final String salonId;

  Future<void> _openDialog(BuildContext context, WidgetRef ref,
      {Staff? existing}) async {
    final result = await showDialog<_StaffFormResult>(
      context: context,
      builder: (_) => _StaffDialog(existing: existing),
    );
    if (result == null) return;
    final repo = ref.read(staffRepositoryProvider);
    if (existing == null) {
      await repo.addStaff(
        salonId: salonId,
        displayName: result.displayName,
        specialty: result.specialty,
      );
    } else {
      await repo.updateStaff(
        id: existing.id,
        displayName: result.displayName,
        specialty: result.specialty,
      );
    }
    ref.invalidate(staffProvider(salonId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final staff = ref.watch(staffProvider(salonId));

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openDialog(context, ref),
        icon: const Icon(Icons.add),
        label: Text(l10n.addButton),
      ),
      body: staff.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (items) {
          if (items.isEmpty) {
            return Center(child: Text(l10n.noStaff));
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final s = items[i];
              return ListTile(
                title: Text(s.displayName),
                subtitle: s.specialty == null ? null : Text(s.specialty!),
                onTap: () => _openDialog(context, ref, existing: s),
                trailing: TextButton(
                  onPressed: () async {
                    await ref
                        .read(staffRepositoryProvider)
                        .setActive(s.id, !s.active);
                    ref.invalidate(staffProvider(salonId));
                  },
                  child: Text(
                    s.active ? l10n.deactivateButton : l10n.activateButton,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _StaffFormResult {
  _StaffFormResult(this.displayName, this.specialty);
  final String displayName;
  final String? specialty;
}

class _StaffDialog extends StatefulWidget {
  const _StaffDialog({this.existing});
  final Staff? existing;

  @override
  State<_StaffDialog> createState() => _StaffDialogState();
}

class _StaffDialogState extends State<_StaffDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.displayName ?? '');
  late final TextEditingController _specialty =
      TextEditingController(text: widget.existing?.specialty ?? '');

  @override
  void dispose() {
    _name.dispose();
    _specialty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(
          widget.existing == null ? l10n.addStaffTitle : l10n.editStaffTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('staffName'),
            controller: _name,
            decoration: InputDecoration(labelText: l10n.staffNameLabel),
          ),
          TextField(
            key: const Key('staffSpecialty'),
            controller: _specialty,
            decoration: InputDecoration(labelText: l10n.staffSpecialtyLabel),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _StaffFormResult(
              _name.text.trim(),
              _specialty.text.trim().isEmpty ? null : _specialty.text.trim(),
            ),
          ),
          child: Text(l10n.addButton),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Write a widget test.** Create `barbershop/test/features/salon/staff_tab_test.dart`:

```dart
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
```

- [ ] **Step 3: Run the full suite and analyzer.**

Run: `cd barbershop && flutter test && flutter analyze`
Expected: all tests pass (Plans 1–3, including `salon_manage_tabs_test.dart`, `services_tab_test.dart`, `staff_tab_test.dart`); analyzer clean.

- [ ] **Step 4: Commit Tasks 7–9 together.**

```bash
git add barbershop/lib/features/salon/presentation/salon_manage_tabs.dart \
        barbershop/lib/features/salon/presentation/services_tab.dart \
        barbershop/lib/features/salon/presentation/staff_tab.dart \
        barbershop/lib/features/salon/presentation/salon_dashboard_screen.dart \
        barbershop/test/features/salon/salon_manage_tabs_test.dart \
        barbershop/test/features/salon/services_tab_test.dart \
        barbershop/test/features/salon/staff_tab_test.dart
git commit -m "feat(salon): tabbed dashboard with services and staff management"
```

---

## Task 10: End-to-end verification

**Files:** none (verification + README).

- [ ] **Step 1: Full analyzer + unit/widget suite.**

Run: `cd barbershop && flutter analyze && flutter test`
Expected: analyzer clean; all tests pass. Note totals.

- [ ] **Step 2: pgTAP suite.**

Run (repo root): `supabase test db`
Expected: `profiles`, `salons`, and `services_staff` suites all pass.

- [ ] **Step 3: Web build.**

Run:
```bash
cd barbershop && flutter build web \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<local publishable key>
```
Expected: `✓ Built build/web`.

- [ ] **Step 4: Live API check.** Sign up an owner, register + approve a salon, then add a service via the RPC and confirm it is publicly readable.

```bash
KEY="<local publishable key>"
EMAIL="owner_$(date +%s)@test.dev"
TOKEN=$(curl -s -X POST "http://127.0.0.1:54321/auth/v1/signup" \
  -H "apikey: $KEY" -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"secret123\"}" | jq -r '.access_token')
SALON=$(curl -s -X POST "http://127.0.0.1:54321/rest/v1/rpc/register_salon" \
  -H "apikey: $KEY" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"p_name":"E2E Salon","p_city":"Tunis"}' | tr -d '"')
CID=$(docker ps --filter "name=supabase_db" --format "{{.Names}}" | head -1)
docker exec -i "$CID" psql -U postgres -d postgres -c \
  "update public.salons set status='approved' where id='$SALON';"
curl -s -X POST "http://127.0.0.1:54321/rest/v1/rpc/add_service" \
  -H "apikey: $KEY" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"p_salon_id\":\"$SALON\",\"p_name\":\"Coupe homme\",\"p_duration_min\":30,\"p_price\":25}"
echo
docker exec -i "$CID" psql -U postgres -d postgres -c \
  "select name, duration_min, price, active from public.services where salon_id='$SALON';"
```
Expected: the `add_service` call returns a uuid; the query shows `Coupe homme | 30 | 25.00 | t`.

- [ ] **Step 5: README + commit.** Append a "Salon content management (Plan 3)" section to `barbershop/README.md` describing the Profil/Services/Équipe tabs and the owner-only write RPCs, then:

```bash
git add barbershop/README.md
git commit -m "docs: salon content management (services and staff)"
```

---

## Self-Review

**Spec coverage (design §5 services/staff, §6 salon side):**
- `services` table (name/duration/price/active) + owner CRUD → Tasks 1, 4, 8. ✓
- `staff` table (display_name/specialty/active, nullable profile link) + owner CRUD → Tasks 1, 5, 9. ✓
- Public reads of services/staff for approved salons; owner/admin otherwise → Task 1 RLS + pgTAP. ✓
- Owner-only writes (cannot mutate another salon) via `owns_salon()` + SECURITY DEFINER RPCs → Task 1 + pgTAP (non-owner add throws; non-owner deactivate is a no-op). ✓
- Management UI integrated into the salon dashboard (tabs) → Tasks 7–9. ✓
- Localization-ready, French, no hardcoded text → Task 6. ✓
- *Deferred (correct):* weekly working hours + daily roster (Plan 4, paired with booking availability); per-staff service assignment; avatar/photo upload; commission.

**Placeholder scan:** No TBD/TODO. The only cross-task deferral (Tasks 7–9 compile and commit as one unit because the tab shell needs its tabs) is stated explicitly in Task 7's note and Task 9's combined commit — not left implicit. ✓

**Type consistency:** RPC param names match between Dart repos (Tasks 4, 5) and SQL (Task 1): `add_service(p_salon_id,p_name,p_duration_min,p_price)`, `update_service(p_service_id,...)`, `set_service_active(p_service_id,p_active)`, and the staff equivalents. `servicesProvider(salonId)`/`staffProvider(salonId)` families defined in Tasks 4/5 and consumed in Tasks 7–9. `FakeFilterBuilder` reused from `test/support/fake_postgrest.dart` (Plan 2). Riverpod 3.x widget-test helpers take domain values (not `List<Override>` params), per Global Constraints. ✓
