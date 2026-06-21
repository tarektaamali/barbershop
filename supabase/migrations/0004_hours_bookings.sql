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
