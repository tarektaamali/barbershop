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
