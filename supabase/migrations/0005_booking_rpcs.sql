-- Customer requests a booking. Auto-assigns the chosen staff, or the first
-- active staff member who has working hours covering the interval and is free
-- (no overlapping confirmed/completed booking or unexpired pending hold).
-- Creates a pending booking holding the slot for 15 minutes.
create function public.request_booking(
  p_salon_id uuid,
  p_service_id uuid,
  p_date date,
  p_start_time time,
  p_staff_id uuid default null
)
  returns uuid language plpgsql security definer set search_path = public
as $$
declare
  v_dur int; v_end time; v_staff uuid; v_id uuid; v_name text; v_price numeric;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not exists (select 1 from public.salons
                 where id = p_salon_id and status = 'approved') then
    raise exception 'salon_unavailable';
  end if;

  select duration_min, name, price into v_dur, v_name, v_price
  from public.services
  where id = p_service_id and salon_id = p_salon_id and active;
  if v_dur is null then raise exception 'service_unavailable'; end if;

  v_end := p_start_time + make_interval(mins => v_dur);

  select st.id into v_staff
  from public.staff st
  where st.salon_id = p_salon_id and st.active
    and (p_staff_id is null or st.id = p_staff_id)
    and exists (
      select 1 from public.working_hours wh
      where wh.staff_id = st.id
        and wh.weekday = extract(dow from p_date)::int
        and wh.start_time <= p_start_time and wh.end_time >= v_end
    )
    and not exists (
      select 1 from public.bookings b
      where b.staff_id = st.id and b.date = p_date
        and (b.status in ('confirmed', 'completed')
             or (b.status = 'pending' and b.hold_expires_at > now()))
        and tsrange(p_date + b.start_time, p_date + b.end_time)
            && tsrange(p_date + p_start_time, p_date + v_end)
    )
  order by st.created_at
  limit 1;

  if v_staff is null then raise exception 'slot_unavailable'; end if;

  insert into public.bookings (
    salon_id, customer_id, staff_id, service_id, service_name_snapshot,
    price_default_snapshot, date, start_time, end_time, status, source,
    hold_expires_at, created_by
  ) values (
    p_salon_id, auth.uid(), v_staff, p_service_id, v_name, v_price,
    p_date, p_start_time, v_end, 'pending', 'online',
    now() + interval '15 minutes', auth.uid()
  ) returning id into v_id;

  return v_id;
end;
$$;

-- Owner confirms a pending request (optionally reassigning the staff member).
-- The overlap exclusion constraint rejects a conflicting confirmation (23P01).
create function public.confirm_booking(p_booking_id uuid, p_staff_id uuid default null)
  returns void language plpgsql security definer set search_path = public
as $$
declare v_salon uuid;
begin
  select salon_id into v_salon from public.bookings where id = p_booking_id;
  if v_salon is null or not public.owns_salon(v_salon) then
    raise exception 'forbidden';
  end if;
  update public.bookings
    set status = 'confirmed',
        staff_id = coalesce(p_staff_id, staff_id),
        confirmed_at = now(),
        hold_expires_at = null
    where id = p_booking_id and status = 'pending';
end;
$$;

create function public.decline_booking(p_booking_id uuid)
  returns void language plpgsql security definer set search_path = public
as $$
declare v_salon uuid;
begin
  select salon_id into v_salon from public.bookings where id = p_booking_id;
  if v_salon is null or not public.owns_salon(v_salon) then
    raise exception 'forbidden';
  end if;
  update public.bookings
    set status = 'declined', hold_expires_at = null
    where id = p_booking_id and status = 'pending';
end;
$$;

create function public.cancel_booking(p_booking_id uuid)
  returns void language plpgsql security definer set search_path = public
as $$
begin
  update public.bookings
    set status = 'cancelled', hold_expires_at = null
    where id = p_booking_id
      and customer_id = auth.uid()
      and status in ('pending', 'confirmed');
  if not found then raise exception 'forbidden'; end if;
end;
$$;

grant execute on function public.request_booking(uuid, uuid, date, time, uuid) to authenticated;
grant execute on function public.confirm_booking(uuid, uuid) to authenticated;
grant execute on function public.decline_booking(uuid) to authenticated;
grant execute on function public.cancel_booking(uuid) to authenticated;
