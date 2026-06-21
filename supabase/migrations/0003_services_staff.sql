create table public.services (
  id           uuid primary key default gen_random_uuid(),
  salon_id     uuid not null references public.salons (id) on delete cascade,
  name         text not null,
  duration_min integer not null,
  price        numeric(8,2) not null default 0,
  active       boolean not null default true,
  created_at   timestamptz not null default now()
);

create table public.staff (
  id           uuid primary key default gen_random_uuid(),
  salon_id     uuid not null references public.salons (id) on delete cascade,
  profile_id   uuid references auth.users (id) on delete set null,
  display_name text not null,
  avatar_url   text,
  specialty    text,
  active       boolean not null default true,
  created_at   timestamptz not null default now()
);

create index services_salon_idx on public.services (salon_id);
create index staff_salon_idx on public.staff (salon_id);

alter table public.services enable row level security;
alter table public.staff enable row level security;

grant select on public.services to anon, authenticated;
grant select on public.staff to anon, authenticated;

-- Readable when the parent salon is approved, owned by the caller, or caller is admin.
create policy "services_select_visible"
  on public.services for select
  using (exists (
    select 1 from public.salons s
    where s.id = services.salon_id
      and (s.status = 'approved' or s.owner_id = auth.uid() or public.is_admin())
  ));

create policy "staff_select_visible"
  on public.staff for select
  using (exists (
    select 1 from public.salons s
    where s.id = staff.salon_id
      and (s.status = 'approved' or s.owner_id = auth.uid() or public.is_admin())
  ));

-- True when the caller owns the given salon.
create function public.owns_salon(p_salon_id uuid)
  returns boolean
  language sql
  security definer
  stable
  set search_path = public
as $$
  select exists (
    select 1 from public.salons where id = p_salon_id and owner_id = auth.uid()
  );
$$;

-- Services -----------------------------------------------------------------
create function public.add_service(
  p_salon_id uuid, p_name text, p_duration_min int, p_price numeric
)
  returns uuid language plpgsql security definer set search_path = public
as $$
declare v_id uuid;
begin
  if not public.owns_salon(p_salon_id) then raise exception 'forbidden'; end if;
  insert into public.services (salon_id, name, duration_min, price)
  values (p_salon_id, p_name, p_duration_min, p_price)
  returning id into v_id;
  return v_id;
end;
$$;

create function public.update_service(
  p_service_id uuid, p_name text, p_duration_min int, p_price numeric
)
  returns void language plpgsql security definer set search_path = public
as $$
begin
  update public.services se
    set name = p_name, duration_min = p_duration_min, price = p_price
    where se.id = p_service_id and public.owns_salon(se.salon_id);
end;
$$;

create function public.set_service_active(p_service_id uuid, p_active boolean)
  returns void language plpgsql security definer set search_path = public
as $$
begin
  update public.services se
    set active = p_active
    where se.id = p_service_id and public.owns_salon(se.salon_id);
end;
$$;

-- Staff --------------------------------------------------------------------
create function public.add_staff(
  p_salon_id uuid, p_display_name text, p_specialty text
)
  returns uuid language plpgsql security definer set search_path = public
as $$
declare v_id uuid;
begin
  if not public.owns_salon(p_salon_id) then raise exception 'forbidden'; end if;
  insert into public.staff (salon_id, display_name, specialty)
  values (p_salon_id, p_display_name, p_specialty)
  returning id into v_id;
  return v_id;
end;
$$;

create function public.update_staff(
  p_staff_id uuid, p_display_name text, p_specialty text
)
  returns void language plpgsql security definer set search_path = public
as $$
begin
  update public.staff st
    set display_name = p_display_name, specialty = p_specialty
    where st.id = p_staff_id and public.owns_salon(st.salon_id);
end;
$$;

create function public.set_staff_active(p_staff_id uuid, p_active boolean)
  returns void language plpgsql security definer set search_path = public
as $$
begin
  update public.staff st
    set active = p_active
    where st.id = p_staff_id and public.owns_salon(st.salon_id);
end;
$$;

grant execute on function public.owns_salon(uuid) to authenticated;
grant execute on function public.add_service(uuid, text, int, numeric) to authenticated;
grant execute on function public.update_service(uuid, text, int, numeric) to authenticated;
grant execute on function public.set_service_active(uuid, boolean) to authenticated;
grant execute on function public.add_staff(uuid, text, text) to authenticated;
grant execute on function public.update_staff(uuid, text, text) to authenticated;
grant execute on function public.set_staff_active(uuid, boolean) to authenticated;
