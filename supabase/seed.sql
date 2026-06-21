-- Demo seed data for local development. Idempotent for the fixed demo ids.
-- Applied automatically by `supabase db reset`, or manually via psql.

-- Demo salon owners. Inserting into auth.users fires handle_new_user(), which
-- creates a default 'customer' profile; we elevate them to salon_owner below.
insert into auth.users (id, email) values
  ('a0000001-0000-0000-0000-000000000001', 'demo.owner1@barbershop.dev'),
  ('a0000002-0000-0000-0000-000000000002', 'demo.owner2@barbershop.dev'),
  ('a0000003-0000-0000-0000-000000000003', 'demo.owner3@barbershop.dev'),
  ('a0000004-0000-0000-0000-000000000004', 'demo.owner4@barbershop.dev')
on conflict (id) do nothing;

update public.profiles set role = 'salon_owner'
where id in (
  'a0000001-0000-0000-0000-000000000001',
  'a0000002-0000-0000-0000-000000000002',
  'a0000003-0000-0000-0000-000000000003',
  'a0000004-0000-0000-0000-000000000004'
);

-- Re-runnable: drop prior demo salons (cascades to services/staff/hours/bookings).
delete from public.salons where id in (
  '50000001-0000-0000-0000-000000000001',
  '50000002-0000-0000-0000-000000000002',
  '50000003-0000-0000-0000-000000000003',
  '50000004-0000-0000-0000-000000000004'
);

insert into public.salons
  (id, owner_id, name, description, city, address, cover_url, status, show_prices, rating_avg, rating_count)
values
  ('50000001-0000-0000-0000-000000000001', 'a0000001-0000-0000-0000-000000000001',
   'Barber House', 'Coupes et dégradés modernes', 'Tunis', 'Av. Habib Bourguiba',
   'https://images.unsplash.com/photo-1585747860715-2ba37e788b70?auto=format&fit=crop&w=900&q=80',
   'approved', true, 4.8, 87),
  ('50000002-0000-0000-0000-000000000002', 'a0000002-0000-0000-0000-000000000002',
   'Fade Studio', 'Spécialiste du dégradé', 'Ariana', 'Rue de l''Indépendance',
   'https://images.unsplash.com/photo-1503951914875-452162b0f3f1?auto=format&fit=crop&w=900&q=80',
   'approved', true, 4.6, 52),
  ('50000003-0000-0000-0000-000000000003', 'a0000003-0000-0000-0000-000000000003',
   'Salon Élégance', 'Coloration et soins', 'Sousse', 'Bd 14 Janvier',
   'https://images.unsplash.com/photo-1599351431202-1e0f0137899a?auto=format&fit=crop&w=900&q=80',
   'approved', true, 4.9, 120),
  ('50000004-0000-0000-0000-000000000004', 'a0000004-0000-0000-0000-000000000004',
   'Le Gentleman', 'Barbier traditionnel', 'Sfax', 'Av. Hedi Chaker',
   'https://images.unsplash.com/photo-1622286342621-4bd786c2447c?auto=format&fit=crop&w=900&q=80',
   'approved', false, 4.5, 33);

-- Services (3 per salon).
insert into public.services (salon_id, name, duration_min, price) values
  ('50000001-0000-0000-0000-000000000001', 'Coupe homme', 30, 25),
  ('50000001-0000-0000-0000-000000000001', 'Coupe + Barbe', 45, 35),
  ('50000001-0000-0000-0000-000000000001', 'Dégradé', 40, 30),
  ('50000002-0000-0000-0000-000000000002', 'Dégradé américain', 40, 32),
  ('50000002-0000-0000-0000-000000000002', 'Coupe enfant', 20, 18),
  ('50000002-0000-0000-0000-000000000002', 'Taille de barbe', 20, 15),
  ('50000003-0000-0000-0000-000000000003', 'Coloration', 90, 70),
  ('50000003-0000-0000-0000-000000000003', 'Brushing', 45, 40),
  ('50000003-0000-0000-0000-000000000003', 'Coupe femme', 60, 50),
  ('50000004-0000-0000-0000-000000000004', 'Coupe classique', 30, 22),
  ('50000004-0000-0000-0000-000000000004', 'Rasage traditionnel', 30, 28),
  ('50000004-0000-0000-0000-000000000004', 'Coupe + Barbe', 50, 38);

-- Staff (2 per salon), with avatar images.
insert into public.staff (id, salon_id, display_name, specialty, avatar_url) values
  ('57000001-0000-0000-0000-000000000001', '50000001-0000-0000-0000-000000000001',
   'Karim', 'Dégradé', 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?auto=format&fit=crop&w=200&q=80'),
  ('57000001-0000-0000-0000-000000000002', '50000001-0000-0000-0000-000000000001',
   'Sami', 'Barbe', 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=200&q=80'),
  ('57000002-0000-0000-0000-000000000001', '50000002-0000-0000-0000-000000000002',
   'Mehdi', 'Dégradé américain', 'https://images.unsplash.com/photo-1519345182560-3f2917c472ef?auto=format&fit=crop&w=200&q=80'),
  ('57000002-0000-0000-0000-000000000002', '50000002-0000-0000-0000-000000000002',
   'Yassine', 'Enfants', 'https://images.unsplash.com/photo-1488161628813-04466f872be2?auto=format&fit=crop&w=200&q=80'),
  ('57000003-0000-0000-0000-000000000001', '50000003-0000-0000-0000-000000000003',
   'Leïla', 'Coloration', 'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?auto=format&fit=crop&w=200&q=80'),
  ('57000003-0000-0000-0000-000000000002', '50000003-0000-0000-0000-000000000003',
   'Nadia', 'Brushing', 'https://images.unsplash.com/photo-1544005313-94ddf0286df2?auto=format&fit=crop&w=200&q=80'),
  ('57000004-0000-0000-0000-000000000001', '50000004-0000-0000-0000-000000000004',
   'Hatem', 'Rasage', 'https://images.unsplash.com/photo-1503443207922-dff7d543fd0e?auto=format&fit=crop&w=200&q=80'),
  ('57000004-0000-0000-0000-000000000002', '50000004-0000-0000-0000-000000000004',
   'Bilel', 'Coupe classique', 'https://images.unsplash.com/photo-1492562080023-ab3db95bfbce?auto=format&fit=crop&w=200&q=80');

-- Working hours: every demo staff member, Monday–Saturday (dow 1..6), 09:00–18:00.
insert into public.working_hours (staff_id, weekday, start_time, end_time)
select s.id, d.wd, '09:00', '18:00'
from public.staff s
cross join (values (1), (2), (3), (4), (5), (6)) as d(wd)
where s.salon_id in (
  '50000001-0000-0000-0000-000000000001',
  '50000002-0000-0000-0000-000000000002',
  '50000003-0000-0000-0000-000000000003',
  '50000004-0000-0000-0000-000000000004'
);
