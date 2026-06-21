create table public.favorites (
  id          uuid primary key default gen_random_uuid(),
  customer_id uuid not null references auth.users (id) on delete cascade,
  salon_id    uuid not null references public.salons (id) on delete cascade,
  created_at  timestamptz not null default now(),
  unique (customer_id, salon_id)
);
create index favorites_customer_idx on public.favorites (customer_id);

alter table public.favorites enable row level security;
grant select on public.favorites to authenticated;

-- A customer sees only their own favorites.
create policy "favorites_select_own"
  on public.favorites for select
  using (customer_id = auth.uid());

-- Toggle a favorite for the current user; returns true if now favorited.
create function public.toggle_favorite(p_salon_id uuid)
  returns boolean language plpgsql security definer set search_path = public
as $$
declare v_deleted int;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  delete from public.favorites
    where customer_id = auth.uid() and salon_id = p_salon_id;
  get diagnostics v_deleted = row_count;
  if v_deleted > 0 then
    return false;
  end if;
  insert into public.favorites (customer_id, salon_id)
    values (auth.uid(), p_salon_id);
  return true;
end;
$$;

-- Owner sets their salon's cover image URL.
create function public.set_salon_cover(p_cover_url text)
  returns void language plpgsql security definer set search_path = public
as $$
begin
  update public.salons set cover_url = p_cover_url where owner_id = auth.uid();
end;
$$;

grant execute on function public.toggle_favorite(uuid) to authenticated;
grant execute on function public.set_salon_cover(text) to authenticated;
