create type public.salon_status as enum ('pending', 'approved', 'rejected', 'suspended');

create table public.salons (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null references auth.users (id) on delete cascade,
  name         text not null,
  description  text,
  city         text not null,
  address      text,
  cover_url    text,
  status       public.salon_status not null default 'pending',
  show_prices  boolean not null default true,
  rating_avg   numeric(2,1) not null default 0,
  rating_count integer not null default 0,
  created_at   timestamptz not null default now()
);

create index salons_owner_idx on public.salons (owner_id);
create index salons_status_idx on public.salons (status);

alter table public.salons enable row level security;

-- Reads: anyone may read approved salons; an owner reads their own; admins read all.
-- Writes go exclusively through SECURITY DEFINER RPCs below (no write policies).
grant select on public.salons to anon, authenticated;

-- True when the current user has the admin role.
create function public.is_admin()
  returns boolean
  language sql
  security definer
  stable
  set search_path = public
as $$
  select exists (
    select 1 from public.profiles where id = auth.uid() and role = 'admin'
  );
$$;

create policy "salons_select_visible"
  on public.salons for select
  using (status = 'approved' or owner_id = auth.uid() or public.is_admin());

-- Register a salon for the caller and elevate them to salon_owner.
create function public.register_salon(
  p_name text,
  p_city text,
  p_description text default null,
  p_address text default null
)
  returns uuid
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  insert into public.salons (owner_id, name, city, description, address, status)
  values (auth.uid(), p_name, p_city, p_description, p_address, 'pending')
  returning id into v_id;

  update public.profiles
    set role = 'salon_owner'
    where id = auth.uid() and role = 'customer';

  return v_id;
end;
$$;

-- Owner edits their own salon profile. Never changes status.
create function public.update_my_salon(
  p_name text,
  p_description text,
  p_city text,
  p_address text,
  p_show_prices boolean
)
  returns void
  language plpgsql
  security definer
  set search_path = public
as $$
begin
  update public.salons
    set name = p_name,
        description = p_description,
        city = p_city,
        address = p_address,
        show_prices = p_show_prices
    where owner_id = auth.uid();
end;
$$;

-- Admin-only status transition (approve / reject / suspend).
create function public.set_salon_status(
  p_salon_id uuid,
  p_status public.salon_status
)
  returns void
  language plpgsql
  security definer
  set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'forbidden';
  end if;

  update public.salons set status = p_status where id = p_salon_id;
end;
$$;

grant execute on function public.register_salon(text, text, text, text) to authenticated;
grant execute on function public.update_my_salon(text, text, text, text, boolean) to authenticated;
grant execute on function public.set_salon_status(uuid, public.salon_status) to authenticated;
