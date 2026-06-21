# Working Hours & Availability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A salon owner sets each staff member's weekly working hours; the system computes the bookable time slots for a service on a date (server-side), correctly accounting for the staff member's hours and any existing bookings.

**Architecture:** Builds on Plans 1–3. Adds `working_hours` and `bookings` tables (the slot function must subtract existing bookings, so the bookings *schema* — enums, an overlap exclusion constraint, RLS — lands here; booking *write RPCs and UI* are Plan 5). Adds a `SECURITY DEFINER` SQL function `available_slots(...)` that generates open start times from working hours minus held/confirmed bookings, plus owner-only hours RPCs. Flutter adds a `WorkingHours` model, repositories, and an "Horaires" management tab.

**Tech Stack:** Flutter 3.35, Dart 3.9, `supabase_flutter` v2, `flutter_riverpod` v3, `go_router` v17, `mocktail`, Supabase CLI + Docker (pgTAP), Postgres `btree_gist`.

## Global Constraints

Carried over from Plans 1–3 (verified against the real codebase):

- **Riverpod 3.x:** `AsyncNotifier`/`AsyncNotifierProvider` (auto-dispose default). `AsyncValue.value` (no `valueOrNull`). The `Override` type is NOT importable by name — widget-test helpers take domain values and build the `ProviderScope` overrides internally.
- **Localization:** strings in `lib/l10n/app_fr.arb`; run `flutter gen-l10n` **from `barbershop/`** (cwd resets between shell calls); generated files committed. Import `package:barbershop/l10n/app_localizations.dart`. No hardcoded UI text. French only.
- **RLS + RPC writes:** tables enable RLS with `grant select` and a read policy; all writes go through `SECURITY DEFINER` RPCs guarded by `owns_salon()` (Plan 3). No write policy on the tables.
- **Testing PostgREST/RPC:** stub `client.rpc(...)` and query builders with `thenAnswer((_) => FakeFilterBuilder<dynamic>(value))` from `test/support/fake_postgrest.dart`. `thenReturn` is rejected for Futures.
- **Weekday convention:** `working_hours.weekday` is Postgres `extract(dow from date)` — **0 = Sunday … 6 = Saturday**. The UI presents days Monday-first but stores this dow value.
- **Time representation:** Postgres `time` serializes as `"HH:MM:SS"`. Dart models hold times as `String`; RPCs accept `"HH:MM"`/`"HH:MM:SS"` (Postgres casts).
- **Existing interfaces:** `supabaseClientProvider`; `Salon`/`SalonStatus`, `salonRepositoryProvider`, `mySalonProvider`; `Staff`, `staffProvider(salonId)`, `staffRepositoryProvider`; `Service`, `servicesProvider(salonId)`; SQL helpers `is_admin()`, `owns_salon(uuid)`; `SalonManageTabs` (3 tabs: Profil/Services/Équipe) in `lib/features/salon/presentation/salon_manage_tabs.dart`.
- **TDD:** failing test first; commit after each green step.
- **Working dir:** Flutter from `barbershop/`; `supabase` from repo root.

---

## File Structure

```
barbershop/
├── lib/features/salon/
│   ├── domain/working_hours.dart            # WorkingHours model
│   ├── data/working_hours_repository.dart   # repo + workingHoursProvider(staffId)
│   ├── data/availability_repository.dart     # availableSlots RPC wrapper
│   └── presentation/
│       ├── hours_tab.dart                     # pick staff -> weekly ranges add/delete
│       └── salon_manage_tabs.dart             # MODIFY: add 4th "Horaires" tab
├── lib/l10n/app_fr.arb                         # MODIFY: add strings
├── test/features/salon/...
└── supabase/
    ├── migrations/0004_hours_bookings.sql
    └── tests/availability_test.sql
```

---

## Task 1: Hours & bookings schema, RLS, RPCs, and `available_slots` (pgTAP)

**Files:**
- Create: `supabase/migrations/0004_hours_bookings.sql`, `supabase/tests/availability_test.sql`

**Interfaces:**
- Consumes: `salons`, `staff`, `services`, `owns_salon()`, `is_admin()`.
- Produces:
  - tables `public.working_hours`, `public.bookings`; enums `public.booking_status`, `public.booking_source`; an overlap exclusion constraint on confirmed/completed bookings.
  - `public.add_working_hours(p_staff_id uuid, p_weekday int, p_start time, p_end time) returns uuid`.
  - `public.delete_working_hours(p_hours_id uuid) returns void`.
  - `public.available_slots(p_salon_id uuid, p_service_id uuid, p_date date, p_staff_id uuid, p_slot_minutes int) returns setof time`.

- [ ] **Step 1: Write the migration.** Create `supabase/migrations/0004_hours_bookings.sql`:

```sql
create extension if not exists btree_gist;

create type public.booking_status as enum
  ('pending', 'confirmed', 'declined', 'cancelled', 'completed', 'no_show');
create type public.booking_source as enum ('online', 'walkin');

-- Weekly working-hours template per staff member.
-- weekday: 0=Sunday .. 6=Saturday (Postgres extract(dow)). Multiple rows per
-- (staff, weekday) express breaks (e.g. 09:00-12:00 and 14:00-18:00).
create table public.working_hours (
  id         uuid primary key default gen_random_uuid(),
  staff_id   uuid not null references public.staff (id) on delete cascade,
  weekday    int  not null check (weekday between 0 and 6),
  start_time time not null,
  end_time   time not null,
  created_at timestamptz not null default now(),
  check (start_time < end_time)
);
create index working_hours_staff_idx on public.working_hours (staff_id);

create table public.bookings (
  id                    uuid primary key default gen_random_uuid(),
  salon_id              uuid not null references public.salons (id) on delete cascade,
  customer_id           uuid references auth.users (id) on delete set null,
  staff_id              uuid references public.staff (id) on delete set null,
  service_id            uuid references public.services (id) on delete set null,
  service_name_snapshot text not null,
  price_default_snapshot numeric(8,2) not null,
  date                  date not null,
  start_time            time not null,
  end_time              time not null,
  status                public.booking_status not null default 'pending',
  source                public.booking_source not null default 'online',
  hold_expires_at       timestamptz,
  actual_price          numeric(8,2),
  created_by            uuid,
  created_at            timestamptz not null default now(),
  confirmed_at          timestamptz,
  completed_at          timestamptz
);
create index bookings_salon_idx on public.bookings (salon_id);
create index bookings_customer_idx on public.bookings (customer_id);
create index bookings_staff_date_idx on public.bookings (staff_id, date);

-- No two confirmed/completed bookings for the same staff member may overlap.
alter table public.bookings
  add constraint bookings_no_overlap
  exclude using gist (
    staff_id with =,
    tsrange((date + start_time), (date + end_time)) with &&
  ) where (status in ('confirmed', 'completed'));

alter table public.working_hours enable row level security;
alter table public.bookings enable row level security;

grant select on public.working_hours to anon, authenticated;
grant select on public.bookings to authenticated;

-- Working hours of an approved salon's staff are public; owner/admin always.
create policy "working_hours_select_visible"
  on public.working_hours for select
  using (exists (
    select 1 from public.staff st join public.salons s on s.id = st.salon_id
    where st.id = working_hours.staff_id
      and (s.status = 'approved' or s.owner_id = auth.uid() or public.is_admin())
  ));

-- A customer reads their own bookings; an owner reads their salon's; admin all.
create policy "bookings_select_visible"
  on public.bookings for select
  using (
    customer_id = auth.uid()
    or public.is_admin()
    or exists (
      select 1 from public.salons s
      where s.id = bookings.salon_id and s.owner_id = auth.uid()
    )
  );

-- Owner-only working-hours writes -----------------------------------------
create function public.add_working_hours(
  p_staff_id uuid, p_weekday int, p_start time, p_end time
)
  returns uuid language plpgsql security definer set search_path = public
as $$
declare v_id uuid; v_salon uuid;
begin
  select salon_id into v_salon from public.staff where id = p_staff_id;
  if v_salon is null or not public.owns_salon(v_salon) then
    raise exception 'forbidden';
  end if;
  insert into public.working_hours (staff_id, weekday, start_time, end_time)
  values (p_staff_id, p_weekday, p_start, p_end)
  returning id into v_id;
  return v_id;
end;
$$;

create function public.delete_working_hours(p_hours_id uuid)
  returns void language plpgsql security definer set search_path = public
as $$
begin
  delete from public.working_hours wh
  using public.staff st
  where wh.id = p_hours_id and st.id = wh.staff_id and public.owns_salon(st.salon_id);
end;
$$;

-- Available start times for a service on a date.
-- p_staff_id null => union across all active staff ("sans préférence").
-- Excludes confirmed/completed bookings and unexpired pending holds.
create function public.available_slots(
  p_salon_id uuid,
  p_service_id uuid,
  p_date date,
  p_staff_id uuid default null,
  p_slot_minutes int default 15
)
  returns setof time
  language sql
  stable
  security definer
  set search_path = public
as $$
  with svc as (
    select duration_min from public.services
    where id = p_service_id and salon_id = p_salon_id
  ),
  cand_staff as (
    select id from public.staff
    where salon_id = p_salon_id and active
      and (p_staff_id is null or id = p_staff_id)
  ),
  starts as (
    select cs.id as staff_id, gs::time as start_t
    from cand_staff cs
    join public.working_hours wh
      on wh.staff_id = cs.id and wh.weekday = extract(dow from p_date)::int
    cross join svc
    cross join lateral generate_series(
      (p_date + wh.start_time),
      (p_date + wh.end_time) - make_interval(mins => svc.duration_min),
      make_interval(mins => p_slot_minutes)
    ) gs
  )
  select distinct s.start_t
  from starts s
  cross join svc
  where not exists (
    select 1 from public.bookings b
    where b.staff_id = s.staff_id
      and b.date = p_date
      and (b.status in ('confirmed', 'completed')
           or (b.status = 'pending' and b.hold_expires_at > now()))
      and tsrange(p_date + b.start_time, p_date + b.end_time)
          && tsrange(p_date + s.start_t,
                     p_date + s.start_t + make_interval(mins => svc.duration_min))
  )
  order by s.start_t;
$$;

grant execute on function public.add_working_hours(uuid, int, time, time) to authenticated;
grant execute on function public.delete_working_hours(uuid) to authenticated;
grant execute on function public.available_slots(uuid, uuid, date, uuid, int) to anon, authenticated;
```

- [ ] **Step 2: Apply the migration.**

Run (repo root): `supabase db reset`
Expected: applies `0001`–`0004` with no error (note: `btree_gist` extension creates and the exclusion constraint is accepted).

- [ ] **Step 3: Write the failing pgTAP test.** Create `supabase/tests/availability_test.sql`:

```sql
begin;
select plan(4);

insert into auth.users (id, email) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'owner@test.dev');

-- Owner registers and (out of band) is approved.
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-0000-0000-000000000001","role":"authenticated"}';
select public.register_salon('Barber House', 'Tunis');
set local role postgres;
update public.salons set status = 'approved'
  where owner_id = 'aaaaaaaa-0000-0000-0000-000000000001';

-- Seed a staff member + a 30-min service.
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-0000-0000-000000000001","role":"authenticated"}';
select public.add_staff(
  (select id from public.salons where owner_id='aaaaaaaa-0000-0000-0000-000000000001'),
  'Karim', 'Dégradé');
select public.add_service(
  (select id from public.salons where owner_id='aaaaaaaa-0000-0000-0000-000000000001'),
  'Coupe homme', 30, 25);

-- Monday 2026-06-22 -> dow = 1. Working hours 09:00-11:00.
select public.add_working_hours(
  (select id from public.staff limit 1), 1, '09:00', '11:00');

-- 1. 30-min service, 15-min granularity, 09:00..10:30 fits => starts
--    09:00,09:15,...,10:30 = 7 slots.
select is(
  (select count(*)::int from public.available_slots(
     (select id from public.salons limit 1),
     (select id from public.services limit 1),
     date '2026-06-22'))::int,
  7,
  '7 open slots before any booking'
);

-- 2. The earliest slot is 09:00.
select is(
  (select min(s) from public.available_slots(
     (select id from public.salons limit 1),
     (select id from public.services limit 1),
     date '2026-06-22') s)::text,
  '09:00:00',
  'earliest open slot is 09:00'
);

-- 3. Insert a confirmed booking 10:00-10:30 for that staff.
set local role postgres;
insert into public.bookings
  (salon_id, staff_id, service_id, service_name_snapshot, price_default_snapshot,
   date, start_time, end_time, status, source)
values (
  (select id from public.salons limit 1),
  (select id from public.staff limit 1),
  (select id from public.services limit 1),
  'Coupe homme', 25, date '2026-06-22', '10:00', '10:30', 'confirmed', 'online');

-- Slots overlapping 10:00-10:30 are removed: 09:45, 10:00, 10:15, 10:30 gone -> 3 left.
select is(
  (select count(*)::int from public.available_slots(
     (select id from public.salons limit 1),
     (select id from public.services limit 1),
     date '2026-06-22'))::int,
  3,
  'overlapping slots removed after a confirmed booking'
);

-- 4. The overlap exclusion constraint rejects a second confirmed booking there.
select throws_ok(
  $$ insert into public.bookings
       (salon_id, staff_id, service_id, service_name_snapshot, price_default_snapshot,
        date, start_time, end_time, status, source)
     values (
       (select id from public.salons limit 1),
       (select id from public.staff limit 1),
       (select id from public.services limit 1),
       'Coupe homme', 25, date '2026-06-22', '10:15', '10:45', 'confirmed', 'online') $$,
  '23P01',
  'exclusion constraint rejects overlapping confirmed bookings'
);

select * from finish();
rollback;
```

- [ ] **Step 4: Run the pgTAP suite.**

Run (repo root): `supabase test db`
Expected: `availability_test.sql` passes all 4 assertions; existing suites still pass.

- [ ] **Step 5: Commit.**

```bash
git add supabase/migrations/0004_hours_bookings.sql supabase/tests/availability_test.sql
git commit -m "feat(db): working_hours + bookings schema, overlap guard, and available_slots"
```

---

## Task 2: WorkingHours model

**Files:**
- Create: `barbershop/lib/features/salon/domain/working_hours.dart`
- Test: `barbershop/test/features/salon/working_hours_test.dart`

**Interfaces:**
- Produces: `class WorkingHours { final String id; final String staffId; final int weekday; final String startTime; final String endTime; }` with `factory WorkingHours.fromMap(Map<String, dynamic>)` and a helper `String get startHm` / `String get endHm` returning `"HH:MM"` (trimming seconds).

- [ ] **Step 1: Write the failing test.** Create `barbershop/test/features/salon/working_hours_test.dart`:

```dart
import 'package:barbershop/features/salon/domain/working_hours.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WorkingHours.fromMap parses a row and trims seconds', () {
    final wh = WorkingHours.fromMap({
      'id': 'wh1',
      'staff_id': 'st1',
      'weekday': 1,
      'start_time': '09:00:00',
      'end_time': '12:00:00',
    });
    expect(wh.id, 'wh1');
    expect(wh.staffId, 'st1');
    expect(wh.weekday, 1);
    expect(wh.startHm, '09:00');
    expect(wh.endHm, '12:00');
  });
}
```

- [ ] **Step 2: Run it (RED).**

Run: `cd barbershop && flutter test test/features/salon/working_hours_test.dart`
Expected: FAIL — `working_hours.dart` does not exist.

- [ ] **Step 3: Implement the model.** Create `barbershop/lib/features/salon/domain/working_hours.dart`:

```dart
class WorkingHours {
  const WorkingHours({
    required this.id,
    required this.staffId,
    required this.weekday,
    required this.startTime,
    required this.endTime,
  });

  final String id;
  final String staffId;
  final int weekday;
  final String startTime;
  final String endTime;

  String get startHm => _hm(startTime);
  String get endHm => _hm(endTime);

  static String _hm(String t) => t.length >= 5 ? t.substring(0, 5) : t;

  factory WorkingHours.fromMap(Map<String, dynamic> map) {
    return WorkingHours(
      id: map['id'] as String,
      staffId: map['staff_id'] as String,
      weekday: map['weekday'] as int,
      startTime: map['start_time'] as String,
      endTime: map['end_time'] as String,
    );
  }
}
```

- [ ] **Step 4: Run it (GREEN).**

Run: `flutter test test/features/salon/working_hours_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git add barbershop/lib/features/salon/domain/working_hours.dart barbershop/test/features/salon/working_hours_test.dart
git commit -m "feat(salon): WorkingHours model"
```

---

## Task 3: WorkingHoursRepository

**Files:**
- Create: `barbershop/lib/features/salon/data/working_hours_repository.dart`
- Test: `barbershop/test/features/salon/working_hours_repository_test.dart`

**Interfaces:**
- Consumes: `supabaseClientProvider`; `WorkingHours` (Task 2).
- Produces:
  - `class WorkingHoursRepository` with:
    - `Future<List<WorkingHours>> fetchForStaff(String staffId)` → `from('working_hours').select().eq('staff_id', staffId).order('weekday')`.
    - `Future<String> addRange({required String staffId, required int weekday, required String start, required String end})` → `rpc('add_working_hours', ...)`.
    - `Future<void> deleteRange(String hoursId)` → `rpc('delete_working_hours', ...)`.
  - `final workingHoursRepositoryProvider = Provider<WorkingHoursRepository>(...)`.
  - `final workingHoursProvider = FutureProvider.family<List<WorkingHours>, String>(...)` keyed by staff id.

- [ ] **Step 1: Write the failing test.** Create `barbershop/test/features/salon/working_hours_repository_test.dart`:

```dart
import 'package:barbershop/features/salon/data/working_hours_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/fake_postgrest.dart';

class _MockClient extends Mock implements SupabaseClient {}

void main() {
  late _MockClient client;
  late WorkingHoursRepository repo;

  setUp(() {
    client = _MockClient();
    repo = WorkingHoursRepository(client);
  });

  test('addRange calls add_working_hours RPC and returns the id', () async {
    when(() => client.rpc('add_working_hours', params: any(named: 'params')))
        .thenAnswer((_) => FakeFilterBuilder<dynamic>('wh1'));

    final id = await repo.addRange(
      staffId: 'st1',
      weekday: 1,
      start: '09:00',
      end: '12:00',
    );

    expect(id, 'wh1');
    verify(() => client.rpc('add_working_hours', params: {
          'p_staff_id': 'st1',
          'p_weekday': 1,
          'p_start': '09:00',
          'p_end': '12:00',
        })).called(1);
  });

  test('deleteRange calls delete_working_hours RPC', () async {
    when(() => client.rpc('delete_working_hours', params: any(named: 'params')))
        .thenAnswer((_) => FakeFilterBuilder<dynamic>(null));

    await repo.deleteRange('wh1');

    verify(() => client.rpc('delete_working_hours', params: {
          'p_hours_id': 'wh1',
        })).called(1);
  });
}
```

- [ ] **Step 2: Run it (RED).**

Run: `cd barbershop && flutter test test/features/salon/working_hours_repository_test.dart`
Expected: FAIL — `working_hours_repository.dart` does not exist.

- [ ] **Step 3: Implement the repository.** Create `barbershop/lib/features/salon/data/working_hours_repository.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/working_hours.dart';

class WorkingHoursRepository {
  WorkingHoursRepository(this._client);

  final SupabaseClient _client;

  Future<List<WorkingHours>> fetchForStaff(String staffId) async {
    final rows = await _client
        .from('working_hours')
        .select()
        .eq('staff_id', staffId)
        .order('weekday');
    return (rows as List)
        .map((r) => WorkingHours.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<String> addRange({
    required String staffId,
    required int weekday,
    required String start,
    required String end,
  }) async {
    final id = await _client.rpc('add_working_hours', params: {
      'p_staff_id': staffId,
      'p_weekday': weekday,
      'p_start': start,
      'p_end': end,
    });
    return id as String;
  }

  Future<void> deleteRange(String hoursId) async {
    await _client.rpc('delete_working_hours', params: {
      'p_hours_id': hoursId,
    });
  }
}

final workingHoursRepositoryProvider =
    Provider<WorkingHoursRepository>((ref) {
  return WorkingHoursRepository(ref.watch(supabaseClientProvider));
});

final workingHoursProvider =
    FutureProvider.family<List<WorkingHours>, String>((ref, staffId) async {
  return ref.watch(workingHoursRepositoryProvider).fetchForStaff(staffId);
});
```

- [ ] **Step 4: Run it (GREEN).**

Run: `flutter test test/features/salon/working_hours_repository_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit.**

```bash
git add barbershop/lib/features/salon/data/working_hours_repository.dart barbershop/test/features/salon/working_hours_repository_test.dart
git commit -m "feat(salon): WorkingHoursRepository with add/delete RPCs and provider"
```

---

## Task 4: AvailabilityRepository

**Files:**
- Create: `barbershop/lib/features/salon/data/availability_repository.dart`
- Test: `barbershop/test/features/salon/availability_repository_test.dart`

**Interfaces:**
- Consumes: `supabaseClientProvider`.
- Produces:
  - `class AvailabilityRepository` with `Future<List<String>> availableSlots({required String salonId, required String serviceId, required String date, String? staffId})` → `rpc('available_slots', ...)` returning a list of `"HH:MM:SS"` strings (trimmed to `"HH:MM"`).
  - `final availabilityRepositoryProvider = Provider<AvailabilityRepository>(...)`.

- [ ] **Step 1: Write the failing test.** Create `barbershop/test/features/salon/availability_repository_test.dart`:

```dart
import 'package:barbershop/features/salon/data/availability_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/fake_postgrest.dart';

class _MockClient extends Mock implements SupabaseClient {}

void main() {
  late _MockClient client;
  late AvailabilityRepository repo;

  setUp(() {
    client = _MockClient();
    repo = AvailabilityRepository(client);
  });

  test('availableSlots calls the RPC and trims seconds', () async {
    when(() => client.rpc('available_slots', params: any(named: 'params')))
        .thenAnswer(
            (_) => FakeFilterBuilder<dynamic>(['09:00:00', '09:15:00']));

    final slots = await repo.availableSlots(
      salonId: 's1',
      serviceId: 'sv1',
      date: '2026-06-22',
    );

    expect(slots, ['09:00', '09:15']);
    verify(() => client.rpc('available_slots', params: {
          'p_salon_id': 's1',
          'p_service_id': 'sv1',
          'p_date': '2026-06-22',
          'p_staff_id': null,
        })).called(1);
  });
}
```

- [ ] **Step 2: Run it (RED).**

Run: `cd barbershop && flutter test test/features/salon/availability_repository_test.dart`
Expected: FAIL — `availability_repository.dart` does not exist.

- [ ] **Step 3: Implement the repository.** Create `barbershop/lib/features/salon/data/availability_repository.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';

class AvailabilityRepository {
  AvailabilityRepository(this._client);

  final SupabaseClient _client;

  Future<List<String>> availableSlots({
    required String salonId,
    required String serviceId,
    required String date,
    String? staffId,
  }) async {
    final rows = await _client.rpc('available_slots', params: {
      'p_salon_id': salonId,
      'p_service_id': serviceId,
      'p_date': date,
      'p_staff_id': staffId,
    });
    return (rows as List)
        .map((t) => (t as String).substring(0, 5))
        .toList();
  }
}

final availabilityRepositoryProvider =
    Provider<AvailabilityRepository>((ref) {
  return AvailabilityRepository(ref.watch(supabaseClientProvider));
});
```

- [ ] **Step 4: Run it (GREEN).**

Run: `flutter test test/features/salon/availability_repository_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git add barbershop/lib/features/salon/data/availability_repository.dart barbershop/test/features/salon/availability_repository_test.dart
git commit -m "feat(salon): AvailabilityRepository wrapping the available_slots RPC"
```

---

## Task 5: Localization strings

**Files:**
- Modify: `barbershop/lib/l10n/app_fr.arb`

**Interfaces:**
- Produces (added to `AppLocalizations`): `tabHours`, `selectStaffLabel`, `noStaffForHours`, `addRangeTitle`, `startTimeLabel`, `endTimeLabel`, `noHours`, `removeButton`, `dayMon`, `dayTue`, `dayWed`, `dayThu`, `dayFri`, `daySat`, `daySun`.

- [ ] **Step 1: Add the strings.** In `barbershop/lib/l10n/app_fr.arb`, add before the closing brace (ensure the preceding line ends with a comma):

```json
  "tabHours": "Horaires",
  "selectStaffLabel": "Coiffeur",
  "noStaffForHours": "Ajoutez d'abord un coiffeur",
  "addRangeTitle": "Ajouter une plage",
  "startTimeLabel": "Début",
  "endTimeLabel": "Fin",
  "noHours": "Aucune plage horaire",
  "removeButton": "Supprimer",
  "dayMon": "Lundi",
  "dayTue": "Mardi",
  "dayWed": "Mercredi",
  "dayThu": "Jeudi",
  "dayFri": "Vendredi",
  "daySat": "Samedi",
  "daySun": "Dimanche"
```

- [ ] **Step 2: Regenerate (from the project dir).**

Run: `cd barbershop && flutter gen-l10n`
Expected: regenerates `lib/l10n/app_localizations*.dart`; no errors.

- [ ] **Step 3: Verify it compiles.**

Run: `flutter analyze lib/l10n`
Expected: No issues found.

- [ ] **Step 4: Commit.**

```bash
git add barbershop/lib/l10n/
git commit -m "feat(l10n): working-hours editor strings"
```

---

## Task 6: Horaires management tab (and 4th tab wiring)

**Files:**
- Create: `barbershop/lib/features/salon/presentation/hours_tab.dart`
- Modify: `barbershop/lib/features/salon/presentation/salon_manage_tabs.dart`
- Test: `barbershop/test/features/salon/hours_tab_test.dart`

**Interfaces:**
- Consumes: `staffProvider(salonId)`, `workingHoursProvider(staffId)`, `workingHoursRepositoryProvider`, `WorkingHours`, `Staff`, `AppLocalizations`.
- Produces:
  - `class HoursTab extends ConsumerStatefulWidget` taking `salonId` — a staff dropdown; for the selected staff, the weekly ranges grouped by day (Monday-first) with a remove action per range and an "add range" affordance per day (a dialog with start/end + day). Mutations call the repository then invalidate `workingHoursProvider(staffId)`.
  - `SalonManageTabs` gains a 4th tab "Horaires" → `HoursTab(salonId: salon.id)`.

- [ ] **Step 1: Create the tab.** Create `barbershop/lib/features/salon/presentation/hours_tab.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../data/staff_repository.dart';
import '../data/working_hours_repository.dart';
import '../domain/staff.dart';
import '../domain/working_hours.dart';

// Monday-first display order mapped to Postgres dow (0=Sun..6=Sat).
const _dayOrder = [1, 2, 3, 4, 5, 6, 0];

String _dayLabel(AppLocalizations l10n, int dow) {
  switch (dow) {
    case 1:
      return l10n.dayMon;
    case 2:
      return l10n.dayTue;
    case 3:
      return l10n.dayWed;
    case 4:
      return l10n.dayThu;
    case 5:
      return l10n.dayFri;
    case 6:
      return l10n.daySat;
    default:
      return l10n.daySun;
  }
}

class HoursTab extends ConsumerStatefulWidget {
  const HoursTab({required this.salonId, super.key});

  final String salonId;

  @override
  ConsumerState<HoursTab> createState() => _HoursTabState();
}

class _HoursTabState extends ConsumerState<HoursTab> {
  String? _staffId;

  Future<void> _addRange(int weekday) async {
    final staffId = _staffId;
    if (staffId == null) return;
    final range = await showDialog<_RangeResult>(
      context: context,
      builder: (_) => const _RangeDialog(),
    );
    if (range == null) return;
    await ref.read(workingHoursRepositoryProvider).addRange(
          staffId: staffId,
          weekday: weekday,
          start: range.start,
          end: range.end,
        );
    ref.invalidate(workingHoursProvider(staffId));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final staffAsync = ref.watch(staffProvider(widget.salonId));

    return staffAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(e.toString())),
      data: (staff) {
        final active = staff.where((s) => s.active).toList();
        if (active.isEmpty) {
          return Center(child: Text(l10n.noStaffForHours));
        }
        final selected = _staffId ?? active.first.id;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: DropdownButtonFormField<String>(
                key: const Key('staffPicker'),
                initialValue: selected,
                decoration: InputDecoration(labelText: l10n.selectStaffLabel),
                items: [
                  for (final Staff s in active)
                    DropdownMenuItem(value: s.id, child: Text(s.displayName)),
                ],
                onChanged: (v) => setState(() => _staffId = v),
              ),
            ),
            Expanded(child: _HoursList(staffId: selected, onAdd: _addRange)),
          ],
        );
      },
    );
  }
}

class _HoursList extends ConsumerWidget {
  const _HoursList({required this.staffId, required this.onAdd});

  final String staffId;
  final void Function(int weekday) onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final hoursAsync = ref.watch(workingHoursProvider(staffId));

    return hoursAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(e.toString())),
      data: (hours) {
        return ListView(
          children: [
            for (final dow in _dayOrder)
              _DaySection(
                label: _dayLabel(l10n, dow),
                ranges: hours.where((h) => h.weekday == dow).toList(),
                onAdd: () => onAdd(dow),
                onRemove: (id) async {
                  await ref
                      .read(workingHoursRepositoryProvider)
                      .deleteRange(id);
                  ref.invalidate(workingHoursProvider(staffId));
                },
              ),
          ],
        );
      },
    );
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({
    required this.label,
    required this.ranges,
    required this.onAdd,
    required this.onRemove,
  });

  final String label;
  final List<WorkingHours> ranges;
  final VoidCallback onAdd;
  final void Function(String id) onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: Theme.of(context).textTheme.titleMedium),
              IconButton(icon: const Icon(Icons.add), onPressed: onAdd),
            ],
          ),
          for (final r in ranges)
            ListTile(
              dense: true,
              title: Text('${r.startHm} – ${r.endHm}'),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => onRemove(r.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _RangeResult {
  _RangeResult(this.start, this.end);
  final String start;
  final String end;
}

class _RangeDialog extends StatefulWidget {
  const _RangeDialog();

  @override
  State<_RangeDialog> createState() => _RangeDialogState();
}

class _RangeDialogState extends State<_RangeDialog> {
  final _start = TextEditingController(text: '09:00');
  final _end = TextEditingController(text: '17:00');

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.addRangeTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('rangeStart'),
            controller: _start,
            decoration: InputDecoration(labelText: l10n.startTimeLabel),
          ),
          TextField(
            key: const Key('rangeEnd'),
            controller: _end,
            decoration: InputDecoration(labelText: l10n.endTimeLabel),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _RangeResult(_start.text.trim(), _end.text.trim()),
          ),
          child: Text(l10n.addButton),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Add the 4th tab.** In `barbershop/lib/features/salon/presentation/salon_manage_tabs.dart`, import the new tab and extend the controller length and tab/view lists.

Add import:
```dart
import 'hours_tab.dart';
```

Change `length: 3` to `length: 4`. Add a tab after the Équipe tab:
```dart
              Tab(text: l10n.tabStaff),
              Tab(text: l10n.tabHours),
```
And add a view after `StaffTab`:
```dart
                StaffTab(salonId: salon.id),
                HoursTab(salonId: salon.id),
```

- [ ] **Step 3: Write a widget test.** Create `barbershop/test/features/salon/hours_tab_test.dart`:

```dart
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
```

- [ ] **Step 4: Run the suite and analyzer.**

Run: `cd barbershop && flutter test && flutter analyze`
Expected: all tests pass (Plans 1–4); analyzer clean.

- [ ] **Step 5: Commit.**

```bash
git add barbershop/lib/features/salon/presentation/hours_tab.dart \
        barbershop/lib/features/salon/presentation/salon_manage_tabs.dart \
        barbershop/test/features/salon/hours_tab_test.dart
git commit -m "feat(salon): working-hours editor tab (Horaires)"
```

---

## Task 7: End-to-end verification

**Files:** none (verification + README).

- [ ] **Step 1: Full analyzer + suite.**

Run: `cd barbershop && flutter analyze && flutter test`
Expected: analyzer clean; all tests pass. Note totals.

- [ ] **Step 2: pgTAP suite.**

Run (repo root): `supabase test db`
Expected: `profiles`, `salons`, `services_staff`, and `availability` suites all pass.

- [ ] **Step 3: Web build.**

Run:
```bash
cd barbershop && flutter build web \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<local publishable key>
```
Expected: `✓ Built build/web`.

- [ ] **Step 4: Live API check.** As an owner, set hours for a staff member, then call `available_slots` and confirm it returns slots.

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
  "update public.salons set status='approved' where id='$SALON';" >/dev/null
STAFF=$(curl -s -X POST "http://127.0.0.1:54321/rest/v1/rpc/add_staff" \
  -H "apikey: $KEY" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"p_salon_id\":\"$SALON\",\"p_display_name\":\"Karim\",\"p_specialty\":\"Dégradé\"}" | tr -d '"')
SERVICE=$(curl -s -X POST "http://127.0.0.1:54321/rest/v1/rpc/add_service" \
  -H "apikey: $KEY" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"p_salon_id\":\"$SALON\",\"p_name\":\"Coupe homme\",\"p_duration_min\":30,\"p_price\":25}" | tr -d '"')
curl -s -X POST "http://127.0.0.1:54321/rest/v1/rpc/add_working_hours" \
  -H "apikey: $KEY" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"p_staff_id\":\"$STAFF\",\"p_weekday\":1,\"p_start\":\"09:00\",\"p_end\":\"11:00\"}" >/dev/null
echo "=== available_slots for Monday 2026-06-22 ==="
curl -s -X POST "http://127.0.0.1:54321/rest/v1/rpc/available_slots" \
  -H "apikey: $KEY" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"p_salon_id\":\"$SALON\",\"p_service_id\":\"$SERVICE\",\"p_date\":\"2026-06-22\"}"
echo
```
Expected: a JSON array of 7 times (`09:00:00` … `10:30:00`).

- [ ] **Step 5: README + commit.** Append a "Working hours & availability (Plan 4)" section to `barbershop/README.md` describing the Horaires tab and the `available_slots` function, then:

```bash
git add barbershop/README.md
git commit -m "docs: working hours and availability"
```

---

## Self-Review

**Spec coverage (design §5 working_hours/bookings, §7 availability):**
- `working_hours` table (weekly template, multiple ranges/day for breaks) + owner CRUD → Tasks 1, 3, 6. ✓
- `bookings` schema + overlap exclusion guard (no two confirmed/completed bookings overlap per staff) → Task 1 + pgTAP. ✓
- Server-side slot generation from hours minus held/confirmed bookings; "sans préférence" union across active staff → Task 1 `available_slots` + pgTAP (count before/after a booking). ✓
- Public can read approved salons' hours and call `available_slots`; bookings readable only by customer/owner/admin → Task 1 RLS. ✓
- Owner-only hours writes via `owns_salon()`-guarded SECURITY DEFINER RPCs → Task 1. ✓
- Horaires editor in the salon dashboard → Task 6. ✓
- Localization-ready, French, no hardcoded text → Task 5. ✓
- *Deferred to Plan 5 (correct):* booking write RPCs (request/confirm/decline/cancel), soft-hold lifecycle + expiry job, the customer slot-picker flow, my-reservations, owner requests inbox. The bookings *schema* is here only because `available_slots` must subtract existing bookings.

**Placeholder scan:** No TBD/TODO; every code step has complete code; commands show expected output. ✓

**Type consistency:** RPC names/params match between Dart (Tasks 3, 4) and SQL (Task 1): `add_working_hours(p_staff_id,p_weekday,p_start,p_end)`, `delete_working_hours(p_hours_id)`, `available_slots(p_salon_id,p_service_id,p_date,p_staff_id,...)`. Weekday is dow (0=Sun..6=Sat) everywhere; the UI maps Monday-first display to dow via `_dayOrder`. `workingHoursProvider(staffId)`/`staffProvider(salonId)` families consumed in Task 6. `FakeFilterBuilder` and value-based widget-test helpers reused per Global Constraints. ✓
