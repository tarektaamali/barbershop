begin;
select plan(7);

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
  'forbidden', 'non-owner cannot confirm a booking');

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
