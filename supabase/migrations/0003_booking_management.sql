-- ARCEUZ BEAUTY OS — 0003: cancelar/reagendar por link seguro, consulta pública da reserva, lista de espera
create table public.waitlist_entries (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  branch_id uuid not null references public.branches(id),
  client_id uuid not null references public.clients(id),
  service_ids uuid[] not null,
  want_date date not null,
  from_time time not null default '00:00',
  to_time time not null default '23:59',
  status text not null default 'waiting' check (status in ('waiting','offered','booked','expired','cancelled')),
  created_at timestamptz not null default now(),
  offer_expires_at timestamptz
);
create index on public.waitlist_entries (tenant_id, want_date) where status = 'waiting';
alter table public.waitlist_entries enable row level security;
create policy wl_read on public.waitlist_entries for select to authenticated using (has_perm(tenant_id,'appointments.read'));
create policy wl_write on public.waitlist_entries for update to authenticated
  using (has_perm(tenant_id,'appointments.write')) with check (has_perm(tenant_id,'appointments.write'));

create or replace function public._appt_by_token(p_token text) returns appointments
language sql stable security definer set search_path = public, extensions as $$
  select * from appointments where manage_token_hash = digest(p_token,'sha256') limit 1
$$;

create or replace function public.get_booking(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare a appointments;
begin
  a := _appt_by_token(p_token);
  if a.id is null then return null; end if;
  return jsonb_build_object('id', a.id, 'status', a.status, 'starts_at', a.starts_at, 'ends_at', a.ends_at,
    'total_cents', a.total_cents, 'reschedule_count', a.reschedule_count,
    'services', (select jsonb_agg(jsonb_build_object('name', s.name, 'staff', st.name, 'starts_at', x.starts_at) order by x.position)
                   from appointment_services x join services s on s.id = x.service_id join staff st on st.id = x.staff_id
                  where x.appointment_id = a.id));
end $$;

create or replace function public.cancel_booking(p_token text, p_reason text default null) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare a appointments; ts tenant_settings;
begin
  a := _appt_by_token(p_token);
  if a.id is null then raise exception 'not_found'; end if;
  if a.status not in ('scheduled','confirmed') then raise exception 'not_cancellable'; end if;
  select * into ts from tenant_settings where tenant_id = a.tenant_id;
  if a.starts_at < now() + make_interval(hours => ts.cancel_deadline_hours) then raise exception 'too_late'; end if;
  update appointments set status = 'cancelled', cancel_reason = p_reason where id = a.id;
  -- vaga liberada: quem está na lista de espera para esse dia passa a ser elegível para aviso (sem confirmar sozinho)
  update waitlist_entries set status = 'offered', offer_expires_at = now() + interval '30 minutes'
   where tenant_id = a.tenant_id and branch_id = a.branch_id and status = 'waiting'
     and want_date = (a.starts_at at time zone ts.timezone)::date;
end $$;

create or replace function public.reschedule_booking(p_token text, p_new_start timestamptz) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare a appointments; ts tenant_settings; v_services uuid[]; v_staff uuid[]; v_plan jsonb; el jsonb;
begin
  a := _appt_by_token(p_token);
  if a.id is null then raise exception 'not_found'; end if;
  if a.status not in ('scheduled','confirmed') then raise exception 'not_reschedulable'; end if;
  select * into ts from tenant_settings where tenant_id = a.tenant_id;
  if a.reschedule_count >= ts.max_reschedules then raise exception 'reschedule_limit'; end if;
  if a.starts_at < now() + make_interval(hours => ts.cancel_deadline_hours) then raise exception 'too_late'; end if;
  if p_new_start < now() + make_interval(mins => ts.min_notice_minutes) then raise exception 'too_soon'; end if;

  select array_agg(service_id order by position), array_agg(staff_id order by position)
    into v_services, v_staff from appointment_services where appointment_id = a.id;

  update appointment_services set active = false where appointment_id = a.id;   -- libera o próprio horário
  v_plan := plan_chain(a.tenant_id, a.branch_id, p_new_start, v_services, v_staff);
  if v_plan is null then raise exception 'slot_unavailable'; end if;               -- aborta e reverte tudo

  delete from appointment_services where appointment_id = a.id;
  begin
    for el in select * from jsonb_array_elements(v_plan) loop
      insert into appointment_services(tenant_id, appointment_id, service_id, staff_id, position,
        starts_at, ends_at, blocked_until, price_cents, duration_min)
      values (a.tenant_id, a.id, (el->>'service_id')::uuid, (el->>'staff_id')::uuid, (el->>'position')::int,
        (el->>'starts_at')::timestamptz, (el->>'ends_at')::timestamptz, (el->>'blocked_until')::timestamptz,
        (el->>'price_cents')::int, (el->>'duration_min')::int);
    end loop;
  exception when exclusion_violation then raise exception 'slot_unavailable';
  end;
  update appointments set starts_at = p_new_start,
         ends_at = (select max(ends_at) from appointment_services where appointment_id = a.id),
         reschedule_count = reschedule_count + 1 where id = a.id;
  insert into appointment_history(tenant_id, appointment_id, event, detail)
  values (a.tenant_id, a.id, 'rescheduled', jsonb_build_object('from', a.starts_at, 'to', p_new_start));
  return jsonb_build_object('appointment_id', a.id);
end $$;

create or replace function public.join_waitlist(p_tenant uuid, p_branch uuid, p_name text, p_phone text,
  p_services uuid[], p_date date, p_from time default '00:00', p_to time default '23:59') returns uuid
language plpgsql security definer set search_path = public as $$
declare v_client uuid; v_id uuid;
begin
  insert into clients(tenant_id, name, phone) values (p_tenant, p_name, p_phone)
  on conflict (tenant_id, phone) do update set name = excluded.name returning id into v_client;
  insert into waitlist_entries(tenant_id, branch_id, client_id, service_ids, want_date, from_time, to_time)
  values (p_tenant, p_branch, v_client, p_services, p_date, p_from, p_to) returning id into v_id;
  return v_id;
end $$;

do $$ declare f text; begin
  foreach f in array array['get_booking(text)','cancel_booking(text,text)','reschedule_booking(text,timestamptz)',
    'join_waitlist(uuid,uuid,text,text,uuid[],date,time,time)','_appt_by_token(text)'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
    execute format('grant execute on function public.%s to service_role', f);
  end loop; end $$;
