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

-- Slots overlapping 10:00-10:30 are removed: 09:45, 10:00, 10:15 gone.
-- 09:30 ends exactly at 10:00 (adjacent, not overlapping) and 10:30 starts at
-- the booking's end, so both stay -> 09:00, 09:15, 09:30, 10:30 = 4 left.
select is(
  (select count(*)::int from public.available_slots(
     (select id from public.salons limit 1),
     (select id from public.services limit 1),
     date '2026-06-22'))::int,
  4,
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
  null,
  'exclusion constraint rejects overlapping confirmed bookings'
);

select * from finish();
rollback;
