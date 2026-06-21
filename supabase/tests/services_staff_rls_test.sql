begin;
select plan(5);

insert into auth.users (id, email) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'owner@test.dev'),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'stranger@test.dev');

-- Owner registers a salon.
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

-- 3. A stranger CANNOT deactivate another salon's staff (no-op, unchanged).
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
