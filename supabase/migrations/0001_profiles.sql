-- Roles available in the platform.
create type public.user_role as enum ('customer', 'salon_owner', 'staff', 'admin');

create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  role        public.user_role not null default 'customer',
  full_name   text,
  phone       text,
  avatar_url  text,
  language    text not null default 'fr',
  fcm_token   text,
  created_at  timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- Table-level privileges. RLS still restricts which rows are visible/editable;
-- these grants only let the authenticated role reach the table at all.
grant select, update on public.profiles to authenticated;

-- A user can read their own profile.
create policy "profiles_select_own"
  on public.profiles for select
  using (auth.uid() = id);

-- A user can update their own profile, but cannot change their role
-- (role changes happen server-side / by admin in a later plan).
create policy "profiles_update_own"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id and role = (select role from public.profiles where id = auth.uid()));

-- Auto-create a default profile when a new auth user is created.
create function public.handle_new_user()
  returns trigger
  language plpgsql
  security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, new.raw_user_meta_data ->> 'full_name');
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
