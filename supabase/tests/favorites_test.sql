begin;
select plan(4);

insert into auth.users (id, email) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'owner@test.dev'),
  ('dddddddd-0000-0000-0000-000000000004', 'customer@test.dev');

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-0000-0000-000000000001","role":"authenticated"}';
select public.register_salon('Barber House', 'Tunis');
set local role postgres;
update public.salons set status = 'approved'
  where owner_id = 'aaaaaaaa-0000-0000-0000-000000000001';

-- Owner sets a cover.
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-0000-0000-000000000001","role":"authenticated"}';
select public.set_salon_cover('https://example.com/cover.jpg');
set local role postgres;
select is(
  (select cover_url from public.salons limit 1),
  'https://example.com/cover.jpg',
  'owner sets the salon cover');

-- Customer toggles a favorite on, then off.
set local role authenticated;
set local request.jwt.claims = '{"sub":"dddddddd-0000-0000-0000-000000000004","role":"authenticated"}';
select is(
  public.toggle_favorite((select id from public.salons limit 1)),
  true,
  'first toggle favorites the salon');
select is(
  (select count(*)::int from public.favorites), 1,
  'favorite row created');
select is(
  public.toggle_favorite((select id from public.salons limit 1)),
  false,
  'second toggle un-favorites the salon');

select * from finish();
rollback;
