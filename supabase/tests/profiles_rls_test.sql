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
