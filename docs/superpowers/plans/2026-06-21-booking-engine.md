# Booking Engine (Request → Confirm) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A customer browses approved salons, picks a service / optional coiffeur / date / open slot, and **requests** a booking (which soft-holds the slot for 15 minutes); the salon owner **confirms** or **declines** the request; the customer sees their reservations and can cancel.

**Architecture:** Builds on Plans 1–4. Adds `SECURITY DEFINER` booking RPCs over the Plan 4 `bookings` table + `available_slots`: `request_booking` (auto-assigns the chosen or first-free staff, status `pending`, `hold_expires_at = now()+15min`), `confirm_booking` / `decline_booking` (owner-only), `cancel_booking` (customer-only). The Plan 4 overlap exclusion constraint guarantees no two confirmed bookings collide even under a race. Flutter adds a `Booking` model, `BookingRepository`, a minimal approved-salons browse + booking flow, a "My reservations" screen, and an owner "Demandes" (requests) tab.

**Tech Stack:** Flutter 3.35, Dart 3.9, `supabase_flutter` v2, `flutter_riverpod` v3, `go_router` v17, `mocktail`, Supabase CLI + Docker (pgTAP).

## Global Constraints

Carried over from Plans 1–4 (verified against the codebase):

- **Riverpod 3.x:** `AsyncNotifier`/`AsyncNotifierProvider` (auto-dispose default). `AsyncValue.value` (no `valueOrNull`). The `Override` type is NOT importable by name — widget-test helpers take domain values and build `ProviderScope` overrides internally.
- **Localization:** strings in `lib/l10n/app_fr.arb`; run `flutter gen-l10n` **from `barbershop/`**; generated files committed; import `package:barbershop/l10n/app_localizations.dart`. No hardcoded UI text. French only.
- **RLS + RPC writes:** writes go through `SECURITY DEFINER` RPCs; `bookings` already has a select RLS policy (customer/owner/admin) and no write policy (Plan 4). Stub `client.rpc(...)` in tests with `thenAnswer((_) => FakeFilterBuilder<dynamic>(value))` from `test/support/fake_postgrest.dart`.
- **Time/date:** dates pass to RPCs as `"YYYY-MM-DD"`, times as `"HH:MM"`. `available_slots` returns `"HH:MM:SS"` (trimmed to `"HH:MM"` by `AvailabilityRepository`, Plan 4).
- **Existing interfaces:** `Salon`/`SalonStatus`, `salonRepositoryProvider`, `mySalonProvider`; `Service`/`servicesProvider(salonId)`; `Staff`/`staffProvider(salonId)`; `AvailabilityRepository.availableSlots(...)`/`availabilityRepositoryProvider`; `is_admin()`, `owns_salon(uuid)`; `SalonManageTabs` (4 tabs); `currentProfileProvider`, `authRepositoryProvider`; the `bookings` table + enums `booking_status`/`booking_source` + overlap constraint (Plan 4).
- **TDD:** failing test first; commit after each green step.
- **Working dir:** Flutter from `barbershop/`; `supabase` from repo root.

---

## File Structure

```
barbershop/
├── lib/features/
│   ├── booking/
│   │   ├── domain/booking.dart                  # Booking model + BookingStatus
│   │   ├── data/booking_repository.dart          # request/confirm/decline/cancel + providers
│   │   └── presentation/
│   │       ├── booking_screen.dart                # service/staff/date/slot -> request
│   │       ├── booking_controller.dart
│   │       └── my_reservations_screen.dart
│   ├── salon/
│   │   ├── data/salon_repository.dart             # MODIFY: fetchApproved + approvedSalonsProvider
│   │   └── presentation/
│   │       ├── browse_salons_screen.dart           # minimal approved-salons list (pre-feed)
│   │       └── requests_tab.dart                    # owner pending-requests inbox
│   │   └── presentation/salon_manage_tabs.dart     # MODIFY: add 5th "Demandes" tab
│   └── home/presentation/customer_home_screen.dart # MODIFY: browse + my-reservations entries
├── lib/core/router/app_router.dart                 # MODIFY: /book/:salonId, /reservations
├── lib/l10n/app_fr.arb                              # MODIFY
└── supabase/
    ├── migrations/0005_booking_rpcs.sql
    └── tests/booking_test.sql
```

---

## Task 1: Booking RPCs (request / confirm / decline / cancel) + pgTAP

**Files:**
- Create: `supabase/migrations/0005_booking_rpcs.sql`, `supabase/tests/booking_test.sql`

**Interfaces:**
- Consumes: `bookings`, `services`, `staff`, `working_hours`, `salons`, `owns_salon()`.
- Produces:
  - `public.request_booking(p_salon_id uuid, p_service_id uuid, p_date date, p_start_time time, p_staff_id uuid) returns uuid`.
  - `public.confirm_booking(p_booking_id uuid, p_staff_id uuid) returns void`.
  - `public.decline_booking(p_booking_id uuid) returns void`.
  - `public.cancel_booking(p_booking_id uuid) returns void`.

- [ ] **Step 1: Write the migration.** Create `supabase/migrations/0005_booking_rpcs.sql`:

```sql
-- Customer requests a booking. Auto-assigns the chosen staff, or the first
-- active staff member who has working hours covering the interval and is free
-- (no overlapping confirmed/completed booking or unexpired pending hold).
-- Creates a pending booking holding the slot for 15 minutes.
create function public.request_booking(
  p_salon_id uuid,
  p_service_id uuid,
  p_date date,
  p_start_time time,
  p_staff_id uuid default null
)
  returns uuid language plpgsql security definer set search_path = public
as $$
declare
  v_dur int; v_end time; v_staff uuid; v_id uuid; v_name text; v_price numeric;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not exists (select 1 from public.salons
                 where id = p_salon_id and status = 'approved') then
    raise exception 'salon_unavailable';
  end if;

  select duration_min, name, price into v_dur, v_name, v_price
  from public.services
  where id = p_service_id and salon_id = p_salon_id and active;
  if v_dur is null then raise exception 'service_unavailable'; end if;

  v_end := p_start_time + make_interval(mins => v_dur);

  select st.id into v_staff
  from public.staff st
  where st.salon_id = p_salon_id and st.active
    and (p_staff_id is null or st.id = p_staff_id)
    and exists (
      select 1 from public.working_hours wh
      where wh.staff_id = st.id
        and wh.weekday = extract(dow from p_date)::int
        and wh.start_time <= p_start_time and wh.end_time >= v_end
    )
    and not exists (
      select 1 from public.bookings b
      where b.staff_id = st.id and b.date = p_date
        and (b.status in ('confirmed', 'completed')
             or (b.status = 'pending' and b.hold_expires_at > now()))
        and tsrange(p_date + b.start_time, p_date + b.end_time)
            && tsrange(p_date + p_start_time, p_date + v_end)
    )
  order by st.created_at
  limit 1;

  if v_staff is null then raise exception 'slot_unavailable'; end if;

  insert into public.bookings (
    salon_id, customer_id, staff_id, service_id, service_name_snapshot,
    price_default_snapshot, date, start_time, end_time, status, source,
    hold_expires_at, created_by
  ) values (
    p_salon_id, auth.uid(), v_staff, p_service_id, v_name, v_price,
    p_date, p_start_time, v_end, 'pending', 'online',
    now() + interval '15 minutes', auth.uid()
  ) returning id into v_id;

  return v_id;
end;
$$;

-- Owner confirms a pending request (optionally reassigning the staff member).
-- The overlap exclusion constraint rejects a conflicting confirmation (23P01).
create function public.confirm_booking(p_booking_id uuid, p_staff_id uuid default null)
  returns void language plpgsql security definer set search_path = public
as $$
declare v_salon uuid;
begin
  select salon_id into v_salon from public.bookings where id = p_booking_id;
  if v_salon is null or not public.owns_salon(v_salon) then
    raise exception 'forbidden';
  end if;
  update public.bookings
    set status = 'confirmed',
        staff_id = coalesce(p_staff_id, staff_id),
        confirmed_at = now(),
        hold_expires_at = null
    where id = p_booking_id and status = 'pending';
end;
$$;

create function public.decline_booking(p_booking_id uuid)
  returns void language plpgsql security definer set search_path = public
as $$
declare v_salon uuid;
begin
  select salon_id into v_salon from public.bookings where id = p_booking_id;
  if v_salon is null or not public.owns_salon(v_salon) then
    raise exception 'forbidden';
  end if;
  update public.bookings
    set status = 'declined', hold_expires_at = null
    where id = p_booking_id and status = 'pending';
end;
$$;

create function public.cancel_booking(p_booking_id uuid)
  returns void language plpgsql security definer set search_path = public
as $$
begin
  update public.bookings
    set status = 'cancelled', hold_expires_at = null
    where id = p_booking_id
      and customer_id = auth.uid()
      and status in ('pending', 'confirmed');
  if not found then raise exception 'forbidden'; end if;
end;
$$;

grant execute on function public.request_booking(uuid, uuid, date, time, uuid) to authenticated;
grant execute on function public.confirm_booking(uuid, uuid) to authenticated;
grant execute on function public.decline_booking(uuid) to authenticated;
grant execute on function public.cancel_booking(uuid) to authenticated;
```

- [ ] **Step 2: Apply the migration.**

Run (repo root): `supabase db reset`
Expected: applies `0001`–`0005` with no error.

- [ ] **Step 3: Write the failing pgTAP test.** Create `supabase/tests/booking_test.sql`:

```sql
begin;
select plan(6);

insert into auth.users (id, email) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'owner@test.dev'),
  ('dddddddd-0000-0000-0000-000000000004', 'customer@test.dev');

-- Owner sets up an approved salon, a staff member, a service, and hours.
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-0000-0000-000000000001","role":"authenticated"}';
select public.register_salon('Barber House', 'Tunis');
set local role postgres;
update public.salons set status = 'approved'
  where owner_id = 'aaaaaaaa-0000-0000-0000-000000000001';
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-0000-0000-000000000001","role":"authenticated"}';
select public.add_staff(
  (select id from public.salons limit 1), 'Karim', 'Dégradé');
select public.add_service(
  (select id from public.salons limit 1), 'Coupe homme', 30, 25);
select public.add_working_hours(
  (select id from public.staff limit 1), 1, '09:00', '12:00');

-- Customer requests a booking on Monday 2026-06-22 at 09:00.
set local request.jwt.claims = '{"sub":"dddddddd-0000-0000-0000-000000000004","role":"authenticated"}';
select lives_ok(
  $$ select public.request_booking(
       (select id from public.salons limit 1),
       (select id from public.services limit 1),
       date '2026-06-22', '09:00') $$,
  'customer can request a booking'
);

-- 1. The booking exists as pending with a live hold and an assigned staff.
set local role postgres;
select is(
  (select status::text from public.bookings limit 1), 'pending',
  'requested booking is pending');
select ok(
  (select hold_expires_at > now() and staff_id is not null from public.bookings limit 1),
  'pending booking holds the slot and has an assigned staff');

-- 2. The held 09:00 slot is no longer available to others.
select is(
  (select count(*)::int from public.available_slots(
     (select id from public.salons limit 1),
     (select id from public.services limit 1),
     date '2026-06-22') s where s = '09:00:00'),
  0,
  'held slot is removed from availability');

-- 3. A non-owner cannot confirm.
set local request.jwt.claims = '{"sub":"dddddddd-0000-0000-0000-000000000004","role":"authenticated"}';
select throws_ok(
  $$ select public.confirm_booking((select id from public.bookings limit 1), null) $$,
  'forbidden', null, 'non-owner cannot confirm a booking');

-- 4. The owner confirms.
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-0000-0000-000000000001","role":"authenticated"}';
select public.confirm_booking((select id from public.bookings limit 1), null);
set local role postgres;
select is(
  (select status::text from public.bookings limit 1), 'confirmed',
  'owner confirms the booking');

-- 5. The customer cancels.
set local role authenticated;
set local request.jwt.claims = '{"sub":"dddddddd-0000-0000-0000-000000000004","role":"authenticated"}';
select public.cancel_booking((select id from public.bookings limit 1));
set local role postgres;
select is(
  (select status::text from public.bookings limit 1), 'cancelled',
  'customer cancels the booking');

select * from finish();
rollback;
```

- [ ] **Step 4: Run the pgTAP suite.**

Run (repo root): `supabase test db`
Expected: `booking_test.sql` passes all 6 assertions; existing suites still pass.

- [ ] **Step 5: Commit.**

```bash
git add supabase/migrations/0005_booking_rpcs.sql supabase/tests/booking_test.sql
git commit -m "feat(db): booking RPCs - request (soft-hold), confirm, decline, cancel"
```

---

## Task 2: Booking model

**Files:**
- Create: `barbershop/lib/features/booking/domain/booking.dart`
- Test: `barbershop/test/features/booking/booking_test.dart`

**Interfaces:**
- Produces:
  - `enum BookingStatus { pending, confirmed, declined, cancelled, completed, noShow }` with `BookingStatus.fromDb(String)` and `String get dbValue` (note: `no_show` ↔ `noShow`).
  - `class Booking { final String id; final String salonId; final String? staffId; final String serviceName; final String date; final String startTime; final String endTime; final BookingStatus status; final double priceDefault; }` with `factory Booking.fromMap(Map<String, dynamic>)` and `String get startHm`/`String get endHm` (trim seconds).

- [ ] **Step 1: Write the failing test.** Create `barbershop/test/features/booking/booking_test.dart`:

```dart
import 'package:barbershop/features/booking/domain/booking.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BookingStatus', () {
    test('maps no_show both ways', () {
      expect(BookingStatus.fromDb('no_show'), BookingStatus.noShow);
      expect(BookingStatus.noShow.dbValue, 'no_show');
    });

    test('unknown falls back to pending', () {
      expect(BookingStatus.fromDb('weird'), BookingStatus.pending);
    });
  });

  test('Booking.fromMap parses a row and trims time seconds', () {
    final b = Booking.fromMap({
      'id': 'b1',
      'salon_id': 's1',
      'staff_id': 'st1',
      'service_name_snapshot': 'Coupe homme',
      'price_default_snapshot': 25,
      'date': '2026-06-22',
      'start_time': '09:00:00',
      'end_time': '09:30:00',
      'status': 'confirmed',
    });
    expect(b.id, 'b1');
    expect(b.salonId, 's1');
    expect(b.staffId, 'st1');
    expect(b.serviceName, 'Coupe homme');
    expect(b.priceDefault, 25.0);
    expect(b.date, '2026-06-22');
    expect(b.startHm, '09:00');
    expect(b.endHm, '09:30');
    expect(b.status, BookingStatus.confirmed);
  });
}
```

- [ ] **Step 2: Run it (RED).**

Run: `cd barbershop && flutter test test/features/booking/booking_test.dart`
Expected: FAIL — `booking.dart` does not exist.

- [ ] **Step 3: Implement the model.** Create `barbershop/lib/features/booking/domain/booking.dart`:

```dart
enum BookingStatus {
  pending('pending'),
  confirmed('confirmed'),
  declined('declined'),
  cancelled('cancelled'),
  completed('completed'),
  noShow('no_show');

  const BookingStatus(this.dbValue);

  final String dbValue;

  static BookingStatus fromDb(String value) {
    return BookingStatus.values.firstWhere(
      (s) => s.dbValue == value,
      orElse: () => BookingStatus.pending,
    );
  }
}

class Booking {
  const Booking({
    required this.id,
    required this.salonId,
    required this.serviceName,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.status,
    required this.priceDefault,
    this.staffId,
  });

  final String id;
  final String salonId;
  final String? staffId;
  final String serviceName;
  final String date;
  final String startTime;
  final String endTime;
  final BookingStatus status;
  final double priceDefault;

  String get startHm => _hm(startTime);
  String get endHm => _hm(endTime);

  static String _hm(String t) => t.length >= 5 ? t.substring(0, 5) : t;

  factory Booking.fromMap(Map<String, dynamic> map) {
    return Booking(
      id: map['id'] as String,
      salonId: map['salon_id'] as String,
      staffId: map['staff_id'] as String?,
      serviceName: map['service_name_snapshot'] as String,
      date: map['date'] as String,
      startTime: map['start_time'] as String,
      endTime: map['end_time'] as String,
      status: BookingStatus.fromDb(map['status'] as String? ?? 'pending'),
      priceDefault: (map['price_default_snapshot'] as num? ?? 0).toDouble(),
    );
  }
}
```

- [ ] **Step 4: Run it (GREEN).**

Run: `flutter test test/features/booking/booking_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git add barbershop/lib/features/booking/domain/booking.dart barbershop/test/features/booking/booking_test.dart
git commit -m "feat(booking): Booking model and BookingStatus enum"
```

---

## Task 3: BookingRepository

**Files:**
- Create: `barbershop/lib/features/booking/data/booking_repository.dart`
- Test: `barbershop/test/features/booking/booking_repository_test.dart`

**Interfaces:**
- Consumes: `supabaseClientProvider`; `Booking` (Task 2); `currentProfileProvider`.
- Produces:
  - `class BookingRepository` with:
    - `Future<String> requestBooking({required String salonId, required String serviceId, required String date, required String startTime, String? staffId})` → `rpc('request_booking', ...)`.
    - `Future<void> confirm(String bookingId, {String? staffId})` → `rpc('confirm_booking', {'p_booking_id':..., 'p_staff_id':...})`.
    - `Future<void> decline(String bookingId)` → `rpc('decline_booking', ...)`.
    - `Future<void> cancel(String bookingId)` → `rpc('cancel_booking', ...)`.
    - `Future<List<Booking>> fetchMine(String customerId)` → `from('bookings').select().eq('customer_id', customerId).order('date', ascending: false)`.
    - `Future<List<Booking>> fetchPendingForSalon(String salonId)` → `from('bookings').select().eq('salon_id', salonId).eq('status','pending').order('date')`.
  - `final bookingRepositoryProvider = Provider<BookingRepository>(...)`.
  - `final myBookingsProvider = FutureProvider<List<Booking>>(...)` (watches `currentProfileProvider`).
  - `final pendingBookingsProvider = FutureProvider.family<List<Booking>, String>(...)` keyed by salon id.

- [ ] **Step 1: Write the failing test.** Create `barbershop/test/features/booking/booking_repository_test.dart`:

```dart
import 'package:barbershop/features/booking/data/booking_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/fake_postgrest.dart';

class _MockClient extends Mock implements SupabaseClient {}

void main() {
  late _MockClient client;
  late BookingRepository repo;

  setUp(() {
    client = _MockClient();
    repo = BookingRepository(client);
  });

  test('requestBooking calls request_booking RPC and returns the id', () async {
    when(() => client.rpc('request_booking', params: any(named: 'params')))
        .thenAnswer((_) => FakeFilterBuilder<dynamic>('b1'));

    final id = await repo.requestBooking(
      salonId: 's1',
      serviceId: 'sv1',
      date: '2026-06-22',
      startTime: '09:00',
    );

    expect(id, 'b1');
    verify(() => client.rpc('request_booking', params: {
          'p_salon_id': 's1',
          'p_service_id': 'sv1',
          'p_date': '2026-06-22',
          'p_start_time': '09:00',
          'p_staff_id': null,
        })).called(1);
  });

  test('confirm calls confirm_booking RPC', () async {
    when(() => client.rpc('confirm_booking', params: any(named: 'params')))
        .thenAnswer((_) => FakeFilterBuilder<dynamic>(null));

    await repo.confirm('b1', staffId: 'st2');

    verify(() => client.rpc('confirm_booking', params: {
          'p_booking_id': 'b1',
          'p_staff_id': 'st2',
        })).called(1);
  });

  test('cancel calls cancel_booking RPC', () async {
    when(() => client.rpc('cancel_booking', params: any(named: 'params')))
        .thenAnswer((_) => FakeFilterBuilder<dynamic>(null));

    await repo.cancel('b1');

    verify(() => client.rpc('cancel_booking', params: {
          'p_booking_id': 'b1',
        })).called(1);
  });
}
```

- [ ] **Step 2: Run it (RED).**

Run: `cd barbershop && flutter test test/features/booking/booking_repository_test.dart`
Expected: FAIL — `booking_repository.dart` does not exist.

- [ ] **Step 3: Implement the repository.** Create `barbershop/lib/features/booking/data/booking_repository.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/booking.dart';

class BookingRepository {
  BookingRepository(this._client);

  final SupabaseClient _client;

  Future<String> requestBooking({
    required String salonId,
    required String serviceId,
    required String date,
    required String startTime,
    String? staffId,
  }) async {
    final id = await _client.rpc('request_booking', params: {
      'p_salon_id': salonId,
      'p_service_id': serviceId,
      'p_date': date,
      'p_start_time': startTime,
      'p_staff_id': staffId,
    });
    return id as String;
  }

  Future<void> confirm(String bookingId, {String? staffId}) async {
    await _client.rpc('confirm_booking', params: {
      'p_booking_id': bookingId,
      'p_staff_id': staffId,
    });
  }

  Future<void> decline(String bookingId) async {
    await _client.rpc('decline_booking', params: {
      'p_booking_id': bookingId,
    });
  }

  Future<void> cancel(String bookingId) async {
    await _client.rpc('cancel_booking', params: {
      'p_booking_id': bookingId,
    });
  }

  Future<List<Booking>> fetchMine(String customerId) async {
    final rows = await _client
        .from('bookings')
        .select()
        .eq('customer_id', customerId)
        .order('date', ascending: false);
    return (rows as List)
        .map((r) => Booking.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<Booking>> fetchPendingForSalon(String salonId) async {
    final rows = await _client
        .from('bookings')
        .select()
        .eq('salon_id', salonId)
        .eq('status', 'pending')
        .order('date');
    return (rows as List)
        .map((r) => Booking.fromMap(r as Map<String, dynamic>))
        .toList();
  }
}

final bookingRepositoryProvider = Provider<BookingRepository>((ref) {
  return BookingRepository(ref.watch(supabaseClientProvider));
});

final myBookingsProvider = FutureProvider<List<Booking>>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile == null) return [];
  return ref.watch(bookingRepositoryProvider).fetchMine(profile.id);
});

final pendingBookingsProvider =
    FutureProvider.family<List<Booking>, String>((ref, salonId) async {
  return ref.watch(bookingRepositoryProvider).fetchPendingForSalon(salonId);
});
```

- [ ] **Step 4: Run it (GREEN).**

Run: `flutter test test/features/booking/booking_repository_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit.**

```bash
git add barbershop/lib/features/booking/data/booking_repository.dart barbershop/test/features/booking/booking_repository_test.dart
git commit -m "feat(booking): BookingRepository with request/confirm/decline/cancel and providers"
```

---

## Task 4: Approved-salons listing on SalonRepository

**Files:**
- Modify: `barbershop/lib/features/salon/data/salon_repository.dart`
- Modify: `barbershop/test/features/salon/salon_repository_test.dart`

**Interfaces:**
- Produces (added):
  - `Future<List<Salon>> fetchApproved()` on `SalonRepository` → `from('salons').select().eq('status','approved').order('rating_avg', ascending: false)`.
  - `final approvedSalonsProvider = FutureProvider<List<Salon>>(...)`.

- [ ] **Step 1: Add a failing test.** In `barbershop/test/features/salon/salon_repository_test.dart`, add a test that `fetchApproved` issues the right query. Because `from().select().eq().order()` is a builder chain, assert via a fake builder that resolves to rows. Add at the end of `main()`:

```dart
  test('fetchApproved maps approved salon rows', () async {
    final builder = FakeFilterBuilder<List<Map<String, dynamic>>>([
      {
        'id': 's1',
        'owner_id': 'u1',
        'name': 'Barber House',
        'city': 'Tunis',
        'status': 'approved',
        'show_prices': true,
        'rating_avg': 4.5,
        'rating_count': 3,
      },
    ]);
    final from = _MockQueryBuilder();
    when(() => client.from('salons')).thenReturn(from);
    when(() => from.select()).thenReturn(builder);

    final salons = await repo.fetchApproved();

    expect(salons, hasLength(1));
    expect(salons.first.name, 'Barber House');
  });
```

Add the mock class near the top of the file (after `_MockClient`):

```dart
class _MockQueryBuilder extends Mock implements SupabaseQueryBuilder {}
```

And extend `FakeFilterBuilder` chain calls used here by making `select()`/`eq()`/`order()` return the same fake. Update `test/support/fake_postgrest.dart` to add these chainable no-ops (Step 2 below covers the helper change).

- [ ] **Step 2: Extend the fake helper to chain.** In `barbershop/test/support/fake_postgrest.dart`, add chainable methods so a single `FakeFilterBuilder` can stand in for `.select().eq().order()`:

```dart
  @override
  PostgrestFilterBuilder<T> select([String columns = '*']) => this;

  @override
  PostgrestFilterBuilder<T> eq(String column, Object value) => this;

  @override
  PostgrestTransformBuilder<T> order(String column, {bool ascending = false,
      bool nullsFirst = false, String? referencedTable}) => this;
```

(Place these inside the `FakeFilterBuilder` class. `PostgrestTransformBuilder` is a supertype the chain returns; returning `this` keeps the fake awaitable.)

- [ ] **Step 3: Run it (RED).**

Run: `cd barbershop && flutter test test/features/salon/salon_repository_test.dart`
Expected: FAIL — `fetchApproved` not defined.

- [ ] **Step 4: Implement `fetchApproved` + provider.** In `barbershop/lib/features/salon/data/salon_repository.dart`, add the method to `SalonRepository`:

```dart
  Future<List<Salon>> fetchApproved() async {
    final rows = await _client
        .from('salons')
        .select()
        .eq('status', 'approved')
        .order('rating_avg', ascending: false);
    return (rows as List)
        .map((r) => Salon.fromMap(r as Map<String, dynamic>))
        .toList();
  }
```

And add, at the bottom of the file:

```dart
final approvedSalonsProvider = FutureProvider<List<Salon>>((ref) async {
  return ref.watch(salonRepositoryProvider).fetchApproved();
});
```

- [ ] **Step 5: Run it (GREEN).**

Run: `flutter test test/features/salon/salon_repository_test.dart`
Expected: PASS (all tests, including the new one).

- [ ] **Step 6: Commit.**

```bash
git add barbershop/lib/features/salon/data/salon_repository.dart barbershop/test/features/salon/salon_repository_test.dart barbershop/test/support/fake_postgrest.dart
git commit -m "feat(salon): fetchApproved + approvedSalonsProvider for browsing"
```

---

## Task 5: Localization strings

**Files:**
- Modify: `barbershop/lib/l10n/app_fr.arb`

**Interfaces:**
- Produces (added): `browseSalonsTitle`, `myReservationsTitle`, `noSalons`, `noReservations`, `bookTitle`, `chooseServiceLabel`, `chooseStaffLabel`, `noPreference`, `chooseDateLabel`, `chooseSlotLabel`, `noSlots`, `requestSlotButton`, `requestSentTitle`, `requestSentBody`, `cancelButton`, `tabRequests`, `noRequests`, `confirmButton`, `declineButton`, `statusPending`, `statusConfirmed`, `statusDeclined`, `statusCancelled`, `statusCompleted`, `statusNoShow`.

- [ ] **Step 1: Add the strings.** In `barbershop/lib/l10n/app_fr.arb`, add before the closing brace (preceding line gets a comma):

```json
  "browseSalonsTitle": "Salons",
  "myReservationsTitle": "Mes réservations",
  "noSalons": "Aucun salon disponible",
  "noReservations": "Aucune réservation",
  "bookTitle": "Réserver",
  "chooseServiceLabel": "Service",
  "chooseStaffLabel": "Coiffeur",
  "noPreference": "Sans préférence",
  "chooseDateLabel": "Date",
  "chooseSlotLabel": "Créneau",
  "noSlots": "Aucun créneau disponible",
  "requestSlotButton": "Demander ce créneau",
  "requestSentTitle": "Demande envoyée",
  "requestSentBody": "En attente de confirmation du salon.",
  "cancelButton": "Annuler",
  "tabRequests": "Demandes",
  "noRequests": "Aucune demande",
  "confirmButton": "Confirmer",
  "declineButton": "Refuser",
  "statusPending": "En attente",
  "statusConfirmed": "Confirmée",
  "statusDeclined": "Refusée",
  "statusCancelled": "Annulée",
  "statusCompleted": "Terminée",
  "statusNoShow": "Absence"
```

- [ ] **Step 2: Regenerate.**

Run: `cd barbershop && flutter gen-l10n`
Expected: regenerates; no errors.

- [ ] **Step 3: Verify.**

Run: `flutter analyze lib/l10n`
Expected: No issues found.

- [ ] **Step 4: Commit.**

```bash
git add barbershop/lib/l10n/
git commit -m "feat(l10n): booking flow, reservations, and requests strings"
```

---

## Task 6: Customer booking flow (browse → book → request)

**Files:**
- Create: `barbershop/lib/features/salon/presentation/browse_salons_screen.dart`, `barbershop/lib/features/booking/presentation/booking_controller.dart`, `barbershop/lib/features/booking/presentation/booking_screen.dart`
- Test: `barbershop/test/features/booking/booking_screen_test.dart`

**Interfaces:**
- Consumes: `approvedSalonsProvider` (Task 4), `servicesProvider`/`staffProvider` (Plan 3), `availabilityRepositoryProvider` (Plan 4), `bookingRepositoryProvider` (Task 3).
- Produces:
  - `class BrowseSalonsScreen extends ConsumerWidget` — lists approved salons; tap → `context.go('/book/${salon.id}')`.
  - `class BookingController extends AsyncNotifier<void>` with `Future<void> requestSlot({required String salonId, required String serviceId, required String date, required String startTime, String? staffId})`.
  - `final bookingControllerProvider = AsyncNotifierProvider<BookingController, void>(BookingController.new)`.
  - `class BookingScreen extends ConsumerStatefulWidget` taking `salonId` — service dropdown, optional staff dropdown (default "Sans préférence"), a date field (text `YYYY-MM-DD` for simplicity / a `showDatePicker`), a fetched slot list, and a request action that on success shows a confirmation.

- [ ] **Step 1: Create the browse screen.** Create `barbershop/lib/features/salon/presentation/browse_salons_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../data/salon_repository.dart';

class BrowseSalonsScreen extends ConsumerWidget {
  const BrowseSalonsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final salons = ref.watch(approvedSalonsProvider);
    return salons.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(e.toString())),
      data: (items) {
        if (items.isEmpty) return Center(child: Text(l10n.noSalons));
        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final s = items[i];
            return ListTile(
              title: Text(s.name),
              subtitle: Text(s.city),
              trailing: Text('★ ${s.ratingAvg.toStringAsFixed(1)}'),
              onTap: () => context.go('/book/${s.id}'),
            );
          },
        );
      },
    );
  }
}
```

- [ ] **Step 2: Create the controller.** Create `barbershop/lib/features/booking/presentation/booking_controller.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/booking_repository.dart';

class BookingController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> requestSlot({
    required String salonId,
    required String serviceId,
    required String date,
    required String startTime,
    String? staffId,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(bookingRepositoryProvider).requestBooking(
            salonId: salonId,
            serviceId: serviceId,
            date: date,
            startTime: startTime,
            staffId: staffId,
          ),
    );
  }
}

final bookingControllerProvider =
    AsyncNotifierProvider<BookingController, void>(BookingController.new);
```

- [ ] **Step 3: Create the booking screen.** Create `barbershop/lib/features/booking/presentation/booking_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../salon/data/availability_repository.dart';
import '../../salon/data/service_repository.dart';
import '../../salon/data/staff_repository.dart';
import 'booking_controller.dart';

class BookingScreen extends ConsumerStatefulWidget {
  const BookingScreen({required this.salonId, super.key});

  final String salonId;

  @override
  ConsumerState<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends ConsumerState<BookingScreen> {
  String? _serviceId;
  String? _staffId; // null => sans préférence
  DateTime _date = DateTime(2026, 6, 22);
  List<String> _slots = [];
  bool _loadingSlots = false;

  String get _dateStr =>
      '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

  Future<void> _loadSlots() async {
    final serviceId = _serviceId;
    if (serviceId == null) return;
    setState(() => _loadingSlots = true);
    final slots = await ref.read(availabilityRepositoryProvider).availableSlots(
          salonId: widget.salonId,
          serviceId: serviceId,
          date: _dateStr,
          staffId: _staffId,
        );
    if (mounted) {
      setState(() {
        _slots = slots;
        _loadingSlots = false;
      });
    }
  }

  Future<void> _request(String slot) async {
    final serviceId = _serviceId;
    if (serviceId == null) return;
    await ref.read(bookingControllerProvider.notifier).requestSlot(
          salonId: widget.salonId,
          serviceId: serviceId,
          date: _dateStr,
          startTime: slot,
          staffId: _staffId,
        );
    final state = ref.read(bookingControllerProvider);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    if (state.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.error.toString())),
      );
    } else {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(l10n.requestSentTitle),
          content: Text(l10n.requestSentBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      await _loadSlots();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final services = ref.watch(servicesProvider(widget.salonId));
    final staff = ref.watch(staffProvider(widget.salonId));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.bookTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          services.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text(e.toString()),
            data: (items) {
              final active = items.where((s) => s.active).toList();
              return DropdownButtonFormField<String>(
                key: const Key('servicePicker'),
                initialValue: _serviceId,
                decoration: InputDecoration(labelText: l10n.chooseServiceLabel),
                items: [
                  for (final s in active)
                    DropdownMenuItem(
                      value: s.id,
                      child: Text('${s.name} · ${s.durationMin} ${l10n.minutesSuffix}'),
                    ),
                ],
                onChanged: (v) {
                  setState(() => _serviceId = v);
                  _loadSlots();
                },
              );
            },
          ),
          const SizedBox(height: 12),
          staff.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => Text(e.toString()),
            data: (items) {
              final active = items.where((s) => s.active).toList();
              return DropdownButtonFormField<String?>(
                key: const Key('staffPicker'),
                initialValue: _staffId,
                decoration: InputDecoration(labelText: l10n.chooseStaffLabel),
                items: [
                  DropdownMenuItem(value: null, child: Text(l10n.noPreference)),
                  for (final s in active)
                    DropdownMenuItem(value: s.id, child: Text(s.displayName)),
                ],
                onChanged: (v) {
                  setState(() => _staffId = v);
                  _loadSlots();
                },
              );
            },
          ),
          const SizedBox(height: 12),
          ListTile(
            key: const Key('datePicker'),
            title: Text(l10n.chooseDateLabel),
            subtitle: Text(_dateStr),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2026, 1, 1),
                lastDate: DateTime(2027, 12, 31),
              );
              if (picked != null) {
                setState(() => _date = picked);
                _loadSlots();
              }
            },
          ),
          const Divider(),
          Text(l10n.chooseSlotLabel,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_loadingSlots)
            const Center(child: CircularProgressIndicator())
          else if (_serviceId == null)
            const SizedBox.shrink()
          else if (_slots.isEmpty)
            Text(l10n.noSlots)
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final slot in _slots)
                  OutlinedButton(
                    onPressed: () => _request(slot),
                    child: Text(slot),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Write a widget test.** Create `barbershop/test/features/booking/booking_screen_test.dart`:

```dart
import 'package:barbershop/features/booking/presentation/booking_screen.dart';
import 'package:barbershop/features/salon/data/service_repository.dart';
import 'package:barbershop/features/salon/data/staff_repository.dart';
import 'package:barbershop/features/salon/domain/service.dart';
import 'package:barbershop/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the service picker and slot heading', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          servicesProvider('s1').overrideWith((ref) async => const [
                Service(
                  id: 'sv1',
                  salonId: 's1',
                  name: 'Coupe homme',
                  durationMin: 30,
                  price: 25,
                  active: true,
                ),
              ]),
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
          home: BookingScreen(salonId: 's1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('servicePicker')), findsOneWidget);
    expect(find.text('Créneau'), findsOneWidget);
  });
}
```

- [ ] **Step 5: Run the widget test.**

Run: `cd barbershop && flutter test test/features/booking/booking_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit.**

```bash
git add barbershop/lib/features/salon/presentation/browse_salons_screen.dart \
        barbershop/lib/features/booking/presentation/booking_controller.dart \
        barbershop/lib/features/booking/presentation/booking_screen.dart \
        barbershop/test/features/booking/booking_screen_test.dart
git commit -m "feat(booking): customer browse-and-book flow with slot picker"
```

---

## Task 7: My reservations screen

**Files:**
- Create: `barbershop/lib/features/booking/presentation/my_reservations_screen.dart`
- Test: `barbershop/test/features/booking/my_reservations_screen_test.dart`

**Interfaces:**
- Consumes: `myBookingsProvider`, `bookingRepositoryProvider` (Task 3); `Booking`/`BookingStatus`; `AppLocalizations`.
- Produces: `class MyReservationsScreen extends ConsumerWidget` — lists the customer's bookings (service, date, time, localized status); a pending/confirmed booking shows a **Annuler** action that calls `cancel` then invalidates `myBookingsProvider`.

- [ ] **Step 1: Create a status-label helper + the screen.** Create `barbershop/lib/features/booking/presentation/my_reservations_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../data/booking_repository.dart';
import '../domain/booking.dart';

String bookingStatusLabel(AppLocalizations l10n, BookingStatus s) {
  switch (s) {
    case BookingStatus.pending:
      return l10n.statusPending;
    case BookingStatus.confirmed:
      return l10n.statusConfirmed;
    case BookingStatus.declined:
      return l10n.statusDeclined;
    case BookingStatus.cancelled:
      return l10n.statusCancelled;
    case BookingStatus.completed:
      return l10n.statusCompleted;
    case BookingStatus.noShow:
      return l10n.statusNoShow;
  }
}

class MyReservationsScreen extends ConsumerWidget {
  const MyReservationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final bookings = ref.watch(myBookingsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.myReservationsTitle)),
      body: bookings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (items) {
          if (items.isEmpty) return Center(child: Text(l10n.noReservations));
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final b = items[i];
              final cancellable = b.status == BookingStatus.pending ||
                  b.status == BookingStatus.confirmed;
              return ListTile(
                title: Text(b.serviceName),
                subtitle: Text('${b.date} · ${b.startHm} – ${b.endHm}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(bookingStatusLabel(l10n, b.status)),
                    if (cancellable)
                      TextButton(
                        onPressed: () async {
                          await ref
                              .read(bookingRepositoryProvider)
                              .cancel(b.id);
                          ref.invalidate(myBookingsProvider);
                        },
                        child: Text(l10n.cancelButton),
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

- [ ] **Step 2: Write a widget test.** Create `barbershop/test/features/booking/my_reservations_screen_test.dart`:

```dart
import 'package:barbershop/features/booking/data/booking_repository.dart';
import 'package:barbershop/features/booking/domain/booking.dart';
import 'package:barbershop/features/booking/presentation/my_reservations_screen.dart';
import 'package:barbershop/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
  testWidgets('lists a reservation with a localized status', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myBookingsProvider.overrideWith((ref) async => const [_booking]),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: [Locale('fr')],
          home: MyReservationsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Coupe homme'), findsOneWidget);
    expect(find.text('En attente'), findsOneWidget);
    expect(find.text('Annuler'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run the widget test.**

Run: `cd barbershop && flutter test test/features/booking/my_reservations_screen_test.dart`
Expected: PASS.

- [ ] **Step 4: Commit.**

```bash
git add barbershop/lib/features/booking/presentation/my_reservations_screen.dart barbershop/test/features/booking/my_reservations_screen_test.dart
git commit -m "feat(booking): my reservations screen with cancel"
```

---

## Task 8: Owner requests inbox (Demandes tab)

**Files:**
- Create: `barbershop/lib/features/salon/presentation/requests_tab.dart`
- Modify: `barbershop/lib/features/salon/presentation/salon_manage_tabs.dart`
- Test: `barbershop/test/features/salon/requests_tab_test.dart`

**Interfaces:**
- Consumes: `pendingBookingsProvider(salonId)`, `bookingRepositoryProvider` (Task 3); `Booking`; `AppLocalizations`.
- Produces:
  - `class RequestsTab extends ConsumerWidget` taking `salonId` — lists pending bookings (service, date, time) with **Confirmer** / **Refuser** actions that call `confirm`/`decline` then invalidate `pendingBookingsProvider(salonId)`. Shows `noRequests` when empty.
  - `SalonManageTabs` gains a 5th tab "Demandes" → `RequestsTab(salonId: salon.id)`.

- [ ] **Step 1: Create the tab.** Create `barbershop/lib/features/salon/presentation/requests_tab.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../booking/data/booking_repository.dart';

class RequestsTab extends ConsumerWidget {
  const RequestsTab({required this.salonId, super.key});

  final String salonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final pending = ref.watch(pendingBookingsProvider(salonId));

    return pending.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(e.toString())),
      data: (items) {
        if (items.isEmpty) return Center(child: Text(l10n.noRequests));
        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final b = items[i];
            return ListTile(
              title: Text(b.serviceName),
              subtitle: Text('${b.date} · ${b.startHm} – ${b.endHm}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () async {
                      await ref.read(bookingRepositoryProvider).confirm(b.id);
                      ref.invalidate(pendingBookingsProvider(salonId));
                    },
                    child: Text(l10n.confirmButton),
                  ),
                  TextButton(
                    onPressed: () async {
                      await ref.read(bookingRepositoryProvider).decline(b.id);
                      ref.invalidate(pendingBookingsProvider(salonId));
                    },
                    child: Text(l10n.declineButton),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
```

- [ ] **Step 2: Add the 5th tab.** In `barbershop/lib/features/salon/presentation/salon_manage_tabs.dart`: add `import 'requests_tab.dart';`, change `length: 4` to `length: 5`, add `Tab(text: l10n.tabRequests)` after the Horaires tab, and `RequestsTab(salonId: salon.id)` after `HoursTab` in the views.

- [ ] **Step 3: Write a widget test.** Create `barbershop/test/features/salon/requests_tab_test.dart`:

```dart
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
          pendingBookingsProvider('s1').overrideWith((ref) async => const [_booking]),
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
```

- [ ] **Step 4: Run the widget test + full analyze.**

Run: `cd barbershop && flutter test test/features/salon/requests_tab_test.dart && flutter analyze`
Expected: PASS; analyzer clean.

- [ ] **Step 5: Commit.**

```bash
git add barbershop/lib/features/salon/presentation/requests_tab.dart \
        barbershop/lib/features/salon/presentation/salon_manage_tabs.dart \
        barbershop/test/features/salon/requests_tab_test.dart
git commit -m "feat(salon): owner requests inbox (Demandes tab) with confirm/decline"
```

---

## Task 9: Routing and customer-home entries

**Files:**
- Modify: `barbershop/lib/core/router/app_router.dart`, `barbershop/lib/features/home/presentation/customer_home_screen.dart`

**Interfaces:**
- Produces: routes `/book/:salonId` → `BookingScreen`, `/reservations` → `MyReservationsScreen`; the customer home shows the `BrowseSalonsScreen` list plus app-bar actions to open "Mes réservations" and "Inscrire mon salon".

- [ ] **Step 1: Add routes.** In `barbershop/lib/core/router/app_router.dart`, add imports:

```dart
import '../../features/booking/presentation/booking_screen.dart';
import '../../features/booking/presentation/my_reservations_screen.dart';
```

Add routes after the `/home` route:

```dart
      GoRoute(
        path: '/book/:salonId',
        builder: (_, state) =>
            BookingScreen(salonId: state.pathParameters['salonId']!),
      ),
      GoRoute(
        path: '/reservations',
        builder: (_, __) => const MyReservationsScreen(),
      ),
```

(`/book/:salonId` and `/reservations` are not public routes and not `/`, so `resolveRedirect` already leaves logged-in customers on them — no redirect change needed.)

- [ ] **Step 2: Rebuild the customer home around browsing.** Replace `barbershop/lib/features/home/presentation/customer_home_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../auth/data/auth_repository.dart';
import '../../salon/presentation/browse_salons_screen.dart';

class CustomerHomeScreen extends ConsumerWidget {
  const CustomerHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.browseSalonsTitle),
        actions: [
          IconButton(
            tooltip: l10n.myReservationsTitle,
            icon: const Icon(Icons.event_note),
            onPressed: () => context.go('/reservations'),
          ),
          IconButton(
            tooltip: l10n.registerSalonButton,
            icon: const Icon(Icons.add_business),
            onPressed: () => context.go('/salon/register'),
          ),
          IconButton(
            tooltip: l10n.signOutButton,
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
          ),
        ],
      ),
      body: const BrowseSalonsScreen(),
    );
  }
}
```

- [ ] **Step 3: Full analyze + suite.**

Run: `cd barbershop && flutter analyze && flutter test`
Expected: analyzer clean; all tests pass (Plans 1–5).

- [ ] **Step 4: Commit.**

```bash
git add barbershop/lib/core/router/app_router.dart barbershop/lib/features/home/presentation/customer_home_screen.dart
git commit -m "feat(router): booking and reservations routes; browse-first customer home"
```

---

## Task 10: End-to-end verification

**Files:** none (verification + README).

- [ ] **Step 1: Full analyzer + suite.** Run: `cd barbershop && flutter analyze && flutter test`. Expected: clean; all pass. Note totals.

- [ ] **Step 2: pgTAP suite.** Run (repo root): `supabase test db`. Expected: all five suites pass.

- [ ] **Step 3: Web build.**

Run:
```bash
cd barbershop && flutter build web \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<local publishable key>
```
Expected: `✓ Built build/web`.

- [ ] **Step 4: Live request → confirm flow.** Set up a salon (owner), then as a customer request a slot, confirm it as the owner, and verify the booking is confirmed.

```bash
KEY="<local publishable key>"
# Owner
OEMAIL="owner_$(date +%s)@test.dev"
OTOKEN=$(curl -s -X POST "http://127.0.0.1:54321/auth/v1/signup" -H "apikey: $KEY" -H "Content-Type: application/json" -d "{\"email\":\"$OEMAIL\",\"password\":\"secret123\"}" | jq -r '.access_token')
SALON=$(curl -s -X POST "http://127.0.0.1:54321/rest/v1/rpc/register_salon" -H "apikey: $KEY" -H "Authorization: Bearer $OTOKEN" -H "Content-Type: application/json" -d '{"p_name":"E2E Salon","p_city":"Tunis"}' | tr -d '"')
CID=$(docker ps --filter "name=supabase_db" --format "{{.Names}}" | head -1)
docker exec -i "$CID" psql -U postgres -d postgres -c "update public.salons set status='approved' where id='$SALON';" >/dev/null
STAFF=$(curl -s -X POST "http://127.0.0.1:54321/rest/v1/rpc/add_staff" -H "apikey: $KEY" -H "Authorization: Bearer $OTOKEN" -H "Content-Type: application/json" -d "{\"p_salon_id\":\"$SALON\",\"p_display_name\":\"Karim\",\"p_specialty\":\"Dégradé\"}" | tr -d '"')
SERVICE=$(curl -s -X POST "http://127.0.0.1:54321/rest/v1/rpc/add_service" -H "apikey: $KEY" -H "Authorization: Bearer $OTOKEN" -H "Content-Type: application/json" -d "{\"p_salon_id\":\"$SALON\",\"p_name\":\"Coupe homme\",\"p_duration_min\":30,\"p_price\":25}" | tr -d '"')
curl -s -X POST "http://127.0.0.1:54321/rest/v1/rpc/add_working_hours" -H "apikey: $KEY" -H "Authorization: Bearer $OTOKEN" -H "Content-Type: application/json" -d "{\"p_staff_id\":\"$STAFF\",\"p_weekday\":1,\"p_start\":\"09:00\",\"p_end\":\"12:00\"}" >/dev/null
# Customer requests
CEMAIL="cust_$(date +%s)@test.dev"
CTOKEN=$(curl -s -X POST "http://127.0.0.1:54321/auth/v1/signup" -H "apikey: $KEY" -H "Content-Type: application/json" -d "{\"email\":\"$CEMAIL\",\"password\":\"secret123\"}" | jq -r '.access_token')
BOOKING=$(curl -s -X POST "http://127.0.0.1:54321/rest/v1/rpc/request_booking" -H "apikey: $KEY" -H "Authorization: Bearer $CTOKEN" -H "Content-Type: application/json" -d "{\"p_salon_id\":\"$SALON\",\"p_service_id\":\"$SERVICE\",\"p_date\":\"2026-06-22\",\"p_start_time\":\"09:00\"}" | tr -d '"')
echo "booking id: $BOOKING"
# Owner confirms
curl -s -X POST "http://127.0.0.1:54321/rest/v1/rpc/confirm_booking" -H "apikey: $KEY" -H "Authorization: Bearer $OTOKEN" -H "Content-Type: application/json" -d "{\"p_booking_id\":\"$BOOKING\",\"p_staff_id\":null}" >/dev/null
docker exec -i "$CID" psql -U postgres -d postgres -c "select status, staff_id is not null as has_staff from public.bookings where id='$BOOKING';"
```
Expected: one row — `confirmed | t`.

- [ ] **Step 5: README + commit.** Append a "Booking engine (Plan 5)" section to `barbershop/README.md` describing the request→confirm flow, the 15-minute soft-hold, and the screens, then:

```bash
git add barbershop/README.md
git commit -m "docs: booking engine (request -> confirm)"
```

---

## Self-Review

**Spec coverage (design §3 booking, §7 booking logic):**
- Request → confirm model: customer requests (pending), owner confirms/declines → Tasks 1, 6, 8. ✓
- 15-minute soft-hold that blocks the slot for others → Task 1 (`hold_expires_at`), verified by pgTAP "held slot removed from availability". ✓
- Optional coiffeur ("Sans préférence") with auto-assignment of a free staff member; owner can reassign at confirm → Task 1 (`request_booking` staff selection, `confirm_booking` coalesce), Task 6 (staff dropdown defaulting to null). ✓
- Slots from `available_slots`; request validates fit & freedom → Tasks 1, 6. ✓
- Customer cancels own pending/confirmed booking → Tasks 1, 7. ✓
- Race safety: no two confirmed bookings overlap (Plan 4 exclusion constraint; `confirm_booking` surfaces 23P01) → Task 1 relies on it. ✓
- Owner-only confirm/decline; customer-only cancel → Task 1 (`owns_salon`/`auth.uid()` guards) + pgTAP (non-owner confirm forbidden). ✓
- Localization-ready, French, no hardcoded text → Task 5. ✓
- *Deferred (correct):* push/in-app notifications (Plan: notifications); the polished visual story feed replaces the minimal browse list (Plan: discovery); walk-ins, completion, no-show, and caisse (Plan: ops & caisse); a cron job to proactively expire stale holds (the time check already frees slots; cleanup job is a later refinement).

**Placeholder scan:** No TBD/TODO; every code step has complete code; commands show expected output. ✓

**Type consistency:** RPC names/params align between Dart (`BookingRepository`, Task 3) and SQL (Task 1): `request_booking(p_salon_id,p_service_id,p_date,p_start_time,p_staff_id)`, `confirm_booking(p_booking_id,p_staff_id)`, `decline_booking(p_booking_id)`, `cancel_booking(p_booking_id)`. `BookingStatus.dbValue` matches the `booking_status` enum (incl. `no_show`). `myBookingsProvider`/`pendingBookingsProvider(salonId)`/`approvedSalonsProvider`/`bookingControllerProvider` defined in Tasks 3/4/6 and consumed in Tasks 6–9. The `FakeFilterBuilder` chain extension (Task 4) is reused by `fetchApproved`/`fetchMine`/`fetchPendingForSalon` tests. `SalonManageTabs` grows from 4 to 5 tabs (Task 8). Booking screen reuses `servicesProvider`/`staffProvider`/`availabilityRepositoryProvider`. ✓
