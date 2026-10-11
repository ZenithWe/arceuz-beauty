-- ARCEUZ BEAUTY OS — 0002 Agendamento: serviços, equipe, escalas, clientes, agenda, disponibilidade
-- Dinheiro sempre em centavos (integer). Horários em timestamptz; escalas em hora local do tenant.

-- ───────── Catálogo ─────────
create table public.service_categories (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  name text not null,
  position int not null default 0
);

create table public.services (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  category_id uuid references public.service_categories(id) on delete set null,
  name text not null,
  description text,
  image_url text,
  price_cents int not null check (price_cents >= 0),
  duration_min int not null check (duration_min > 0),
  buffer_min int not null default 0 check (buffer_min >= 0),   -- preparo/limpeza
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create index on public.services (tenant_id) where active;

-- Histórico de preços (preço novo nunca altera atendimentos já registrados)
create table public.service_prices (
  id bigint generated always as identity primary key,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  service_id uuid not null references public.services(id) on delete cascade,
  price_cents int not null,
  valid_from timestamptz not null default now()
);
create or replace function public.log_service_price() returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' or new.price_cents is distinct from old.price_cents then
    insert into service_prices(tenant_id, service_id, price_cents) values (new.tenant_id, new.id, new.price_cents);
  end if;
  return new;
end $$;
create trigger trg_service_price after insert or update on public.services
  for each row execute function public.log_service_price();

-- ───────── Equipe e escalas ─────────
create table public.staff (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  branch_id uuid not null references public.branches(id),
  user_id uuid references auth.users(id) on delete set null,
  name text not null,
  role_title text,
  photo_url text,
  active boolean not null default true
);
create index on public.staff (tenant_id, branch_id) where active;

create table public.staff_services (
  staff_id uuid references public.staff(id) on delete cascade,
  service_id uuid references public.services(id) on delete cascade,
  primary key (staff_id, service_id)
);

create table public.staff_schedules (            -- expediente semanal (hora local)
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  staff_id uuid not null references public.staff(id) on delete cascade,
  weekday smallint not null check (weekday between 0 and 6),   -- 0 = domingo
  start_time time not null,
  end_time time not null,
  check (end_time > start_time)
);
create index on public.staff_schedules (staff_id, weekday);

create table public.staff_breaks (               -- almoço/pausas (hora local)
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  staff_id uuid not null references public.staff(id) on delete cascade,
  weekday smallint not null check (weekday between 0 and 6),
  start_time time not null,
  end_time time not null,
  check (end_time > start_time)
);

create table public.staff_absences (             -- férias, faltas, atestados
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  staff_id uuid not null references public.staff(id) on delete cascade,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  reason text,
  check (ends_at > starts_at)
);

create table public.schedule_blocks (            -- bloqueios manuais; staff_id nulo = salão todo (feriado)
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  staff_id uuid references public.staff(id) on delete cascade,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  reason text,
  check (ends_at > starts_at)
);

-- ───────── Clientes ─────────
create table public.clients (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  name text not null,
  phone text,                                    -- normalizado (E.164) pela aplicação
  email text,
  birthday date,
  marketing_consent boolean not null default false,
  consent_at timestamptz,
  created_at timestamptz not null default now(),
  unique (tenant_id, phone)
);
create index on public.clients (tenant_id, name);

-- ───────── Agenda ─────────
create table public.appointments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  branch_id uuid not null references public.branches(id),
  client_id uuid not null references public.clients(id),
  status text not null default 'scheduled'
    check (status in ('scheduled','confirmed','checked_in','in_service','completed','cancelled','no_show')),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  total_cents int not null,                      -- snapshot do valor na reserva
  total_minutes int not null,
  source text not null default 'public' check (source in ('public','admin','api')),
  manage_token_hash bytea,                       -- link seguro do cliente (só o hash é guardado)
  cancel_reason text,
  reschedule_count int not null default 0,
  created_by uuid,
  created_at timestamptz not null default now(),
  check (ends_at > starts_at)
);
create index on public.appointments (tenant_id, starts_at);
create index on public.appointments (client_id);

create table public.appointment_services (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  appointment_id uuid not null references public.appointments(id) on delete cascade,
  service_id uuid not null references public.services(id),
  staff_id uuid not null references public.staff(id),
  position int not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  blocked_until timestamptz not null,            -- ends_at + buffer
  price_cents int not null,                      -- snapshot imutável
  duration_min int not null,
  active boolean not null default true,          -- false quando cancelado/falta (libera o horário)
  check (blocked_until >= ends_at),
  -- GARANTIA NO BANCO: um profissional não pode ter dois atendimentos ativos sobrepostos
  constraint no_staff_overlap exclude using gist (
    staff_id with =,
    tstzrange(starts_at, blocked_until, '[)') with &&
  ) where (active)
);
create index on public.appointment_services (appointment_id);

create table public.appointment_history (
  id bigint generated always as identity primary key,
  tenant_id uuid not null,
  appointment_id uuid not null references public.appointments(id) on delete cascade,
  actor uuid,
  event text not null,
  detail jsonb,
  at timestamptz not null default now()
);

-- Libera/ocupa horário conforme status e registra histórico
create or replace function public.sync_appointment_status() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and new.status is distinct from old.status then
    update appointment_services
       set active = (new.status not in ('cancelled','no_show'))
     where appointment_id = new.id;
    insert into appointment_history(tenant_id, appointment_id, actor, event, detail)
    values (new.tenant_id, new.id, auth.uid(), 'status_changed',
            jsonb_build_object('from', old.status, 'to', new.status));
  end if;
  return new;
end $$;
create trigger trg_sync_status after update on public.appointments
  for each row execute function public.sync_appointment_status();

-- ───────── Motor de disponibilidade ─────────
-- O profissional está livre em [p_start, p_end) (bloqueado até p_blocked_until)?
create or replace function public.staff_is_free(
  p_staff uuid, p_start timestamptz, p_end timestamptz, p_blocked_until timestamptz
) returns boolean language plpgsql stable set search_path = public as $$
declare
  v_tenant uuid; v_tz text; ls timestamp; le timestamp; wd int;
begin
  select s.tenant_id, ts.timezone into v_tenant, v_tz
    from staff s join tenant_settings ts on ts.tenant_id = s.tenant_id
   where s.id = p_staff and s.active;
  if v_tenant is null then return false; end if;

  ls := p_start at time zone v_tz;  le := p_end at time zone v_tz;
  if ls::date <> le::date then return false; end if;       -- atendimento não cruza a meia-noite
  wd := extract(dow from ls)::int;

  if not exists (select 1 from staff_schedules sc
      where sc.staff_id = p_staff and sc.weekday = wd
        and sc.start_time <= ls::time and sc.end_time >= le::time) then return false; end if;

  if exists (select 1 from staff_breaks b
      where b.staff_id = p_staff and b.weekday = wd
        and b.start_time < le::time and b.end_time > ls::time) then return false; end if;

  if exists (select 1 from staff_absences a
      where a.staff_id = p_staff and tstzrange(a.starts_at, a.ends_at) && tstzrange(p_start, p_end)) then return false; end if;

  if exists (select 1 from schedule_blocks sb
      where sb.tenant_id = v_tenant and (sb.staff_id = p_staff or sb.staff_id is null)
        and tstzrange(sb.starts_at, sb.ends_at) && tstzrange(p_start, p_end)) then return false; end if;

  if exists (select 1 from appointment_services x
      where x.staff_id = p_staff and x.active
        and tstzrange(x.starts_at, x.blocked_until, '[)') && tstzrange(p_start, p_blocked_until, '[)')) then return false; end if;

  return true;
end $$;

-- Monta a sequência de serviços a partir de p_start. Retorna jsonb (array) ou NULL se inviável.
-- p_staff: mesmo tamanho de p_services; elemento NULL = "qualquer profissional disponível".
create or replace function public.plan_chain(
  p_tenant uuid, p_branch uuid, p_start timestamptz, p_services uuid[], p_staff uuid[] default null
) returns jsonb language plpgsql stable set search_path = public as $$
declare
  i int; cursor_ts timestamptz := p_start; svc record; v_staff uuid; v_end timestamptz; v_blk timestamptz;
  v_plan jsonb := '[]'::jsonb;
begin
  for i in 1 .. coalesce(array_length(p_services,1),0) loop
    select * into svc from services where id = p_services[i] and tenant_id = p_tenant and active;
    if not found then return null; end if;
    v_end := cursor_ts + make_interval(mins => svc.duration_min);
    v_blk := v_end + make_interval(mins => svc.buffer_min);

    v_staff := null;
    if p_staff is not null and p_staff[i] is not null then
      if exists (select 1 from staff s join staff_services ss on ss.staff_id = s.id
                  where s.id = p_staff[i] and s.tenant_id = p_tenant and s.branch_id = p_branch
                    and ss.service_id = svc.id and staff_is_free(s.id, cursor_ts, v_end, v_blk))
      then v_staff := p_staff[i]; end if;
    else
      select s.id into v_staff from staff s join staff_services ss on ss.staff_id = s.id
       where s.tenant_id = p_tenant and s.branch_id = p_branch and s.active and ss.service_id = svc.id
         and staff_is_free(s.id, cursor_ts, v_end, v_blk)
       order by s.id limit 1;
    end if;
    if v_staff is null then return null; end if;

    v_plan := v_plan || jsonb_build_object(
      'position', i, 'service_id', svc.id, 'staff_id', v_staff,
      'starts_at', cursor_ts, 'ends_at', v_end, 'blocked_until', v_blk,
      'price_cents', svc.price_cents, 'duration_min', svc.duration_min);
    cursor_ts := v_blk;
  end loop;
  if jsonb_array_length(v_plan) = 0 then return null; end if;
  return v_plan;
end $$;

-- Horários realmente disponíveis em uma data para uma combinação de serviços.
create or replace function public.available_slots(
  p_tenant uuid, p_branch uuid, p_date date, p_services uuid[], p_staff uuid[] default null
) returns table (slot_start timestamptz, plan jsonb)
language plpgsql stable set search_path = public as $$
declare ts tenant_settings; t timestamptz; day0 timestamptz; v_plan jsonb;
begin
  select * into ts from tenant_settings where tenant_id = p_tenant;
  if not found then return; end if;
  day0 := p_date::timestamp at time zone ts.timezone;
  for t in select g from generate_series(day0, day0 + interval '23 hours 59 minutes',
                                         make_interval(mins => ts.slot_step_minutes)) g loop
    continue when t < now() + make_interval(mins => ts.min_notice_minutes);
    continue when t > now() + make_interval(days => ts.max_advance_days);
    v_plan := plan_chain(p_tenant, p_branch, t, p_services, p_staff);
    if v_plan is not null then slot_start := t; plan := v_plan; return next; end if;
  end loop;
end $$;

-- Reserva transacional (múltiplos serviços). Chamada pelo servidor com service_role.
create or replace function public.create_booking(
  p_tenant uuid, p_branch uuid, p_client_name text, p_client_phone text, p_client_email text,
  p_start timestamptz, p_services uuid[], p_staff uuid[] default null, p_source text default 'public'
) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_plan jsonb; v_client uuid; v_appt uuid; v_token text; el jsonb; ts tenant_settings;
begin
  select * into ts from tenant_settings where tenant_id = p_tenant;
  if not found then raise exception 'tenant_not_found'; end if;
  if p_start < now() + make_interval(mins => ts.min_notice_minutes) then raise exception 'too_soon'; end if;
  if p_start > now() + make_interval(days => ts.max_advance_days) then raise exception 'too_far'; end if;
  if not exists (select 1 from branches where id = p_branch and tenant_id = p_tenant and active) then
    raise exception 'branch_not_found'; end if;

  v_plan := plan_chain(p_tenant, p_branch, p_start, p_services, p_staff);
  if v_plan is null then raise exception 'slot_unavailable'; end if;

  insert into clients(tenant_id, name, phone, email)
  values (p_tenant, p_client_name, p_client_phone, p_client_email)
  on conflict (tenant_id, phone) do update set name = excluded.name
  returning id into v_client;

  v_token := encode(gen_random_bytes(24), 'hex');
  insert into appointments(tenant_id, branch_id, client_id, starts_at, ends_at, total_cents, total_minutes, source, manage_token_hash)
  select p_tenant, p_branch, v_client, p_start,
         max((e->>'ends_at')::timestamptz),
         sum((e->>'price_cents')::int), sum((e->>'duration_min')::int),
         p_source, digest(v_token, 'sha256')
    from jsonb_array_elements(v_plan) e
  returning id into v_appt;

  begin
    for el in select * from jsonb_array_elements(v_plan) loop
      insert into appointment_services(tenant_id, appointment_id, service_id, staff_id, position,
        starts_at, ends_at, blocked_until, price_cents, duration_min)
      values (p_tenant, v_appt, (el->>'service_id')::uuid, (el->>'staff_id')::uuid, (el->>'position')::int,
        (el->>'starts_at')::timestamptz, (el->>'ends_at')::timestamptz, (el->>'blocked_until')::timestamptz,
        (el->>'price_cents')::int, (el->>'duration_min')::int);
    end loop;
  exception when exclusion_violation then
    raise exception 'slot_unavailable';          -- corrida: outro cliente reservou primeiro; tudo é revertido
  end;

  insert into appointment_history(tenant_id, appointment_id, event, detail)
  values (p_tenant, v_appt, 'created', jsonb_build_object('source', p_source));

  return jsonb_build_object('appointment_id', v_appt, 'manage_token', v_token, 'plan', v_plan);
end $$;

-- ───────── Permissões de execução ─────────
revoke all on function public.create_booking(uuid,uuid,text,text,text,timestamptz,uuid[],uuid[],text) from public, anon, authenticated;
grant execute on function public.create_booking(uuid,uuid,text,text,text,timestamptz,uuid[],uuid[],text) to service_role;
revoke all on function public.plan_chain(uuid,uuid,timestamptz,uuid[],uuid[]) from public, anon;
revoke all on function public.available_slots(uuid,uuid,date,uuid[],uuid[]) from public, anon;
grant execute on function public.plan_chain(uuid,uuid,timestamptz,uuid[],uuid[]) to authenticated, service_role;
grant execute on function public.available_slots(uuid,uuid,date,uuid[],uuid[]) to authenticated, service_role;

-- ───────── RLS ─────────
do $$
declare t text;
begin
  foreach t in array array['service_categories','services','service_prices','staff','staff_schedules','staff_breaks',
    'staff_absences','schedule_blocks','clients','appointments','appointment_services','appointment_history']
  loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- Leitura: membros do tenant (catálogo/equipe); escrita por permissão
create policy cat_read on public.service_categories for select to authenticated using (is_member(tenant_id));
create policy cat_write on public.service_categories for all to authenticated
  using (has_perm(tenant_id,'services.manage')) with check (has_perm(tenant_id,'services.manage'));
create policy svc_read on public.services for select to authenticated using (is_member(tenant_id));
create policy svc_write on public.services for all to authenticated
  using (has_perm(tenant_id,'services.manage')) with check (has_perm(tenant_id,'services.manage'));
create policy sprice_read on public.service_prices for select to authenticated using (has_perm(tenant_id,'services.manage'));

create policy staff_read on public.staff for select to authenticated using (is_member(tenant_id));
create policy staff_write on public.staff for all to authenticated
  using (has_perm(tenant_id,'staff.manage')) with check (has_perm(tenant_id,'staff.manage'));
create policy ss_read on public.staff_services for select to authenticated
  using (exists (select 1 from staff s where s.id = staff_id and is_member(s.tenant_id)));
create policy ss_write on public.staff_services for all to authenticated
  using (exists (select 1 from staff s where s.id = staff_id and has_perm(s.tenant_id,'staff.manage')))
  with check (exists (select 1 from staff s where s.id = staff_id and has_perm(s.tenant_id,'staff.manage')));

do $$
declare t text;
begin
  foreach t in array array['staff_schedules','staff_breaks','staff_absences','schedule_blocks']
  loop
    execute format('create policy %I on public.%I for select to authenticated using (is_member(tenant_id))', t||'_read', t);
    execute format($f$create policy %I on public.%I for all to authenticated
      using (has_perm(tenant_id,'schedule.manage')) with check (has_perm(tenant_id,'schedule.manage'))$f$, t||'_write', t);
  end loop;
end $$;

create policy clients_read on public.clients for select to authenticated using (has_perm(tenant_id,'clients.read'));
create policy clients_ins on public.clients for insert to authenticated with check (has_perm(tenant_id,'clients.write'));
create policy clients_upd on public.clients for update to authenticated
  using (has_perm(tenant_id,'clients.write')) with check (has_perm(tenant_id,'clients.write'));
create policy clients_del on public.clients for delete to authenticated using (has_perm(tenant_id,'clients.delete'));

create policy appt_read on public.appointments for select to authenticated using (
  has_perm(tenant_id,'appointments.read')
  or (has_perm(tenant_id,'appointments.read_own') and exists (
        select 1 from appointment_services x join staff s on s.id = x.staff_id
         where x.appointment_id = appointments.id and s.user_id = auth.uid())));
create policy appt_write on public.appointments for update to authenticated
  using (has_perm(tenant_id,'appointments.write')) with check (has_perm(tenant_id,'appointments.write'));

create policy aps_read on public.appointment_services for select to authenticated using (
  has_perm(tenant_id,'appointments.read')
  or (has_perm(tenant_id,'appointments.read_own') and exists (
        select 1 from staff s where s.id = staff_id and s.user_id = auth.uid())));
create policy hist_read on public.appointment_history for select to authenticated
  using (has_perm(tenant_id,'appointments.read'));
-- Inserção de agendamentos: somente via create_booking (service_role) — nenhuma policy de INSERT para clientes finais.

create trigger audit_services after insert or update or delete on public.services for each row execute function public.audit_row();
create trigger audit_staff after insert or update or delete on public.staff for each row execute function public.audit_row();
create trigger audit_clients after update or delete on public.clients for each row execute function public.audit_row();
create trigger audit_appts after update or delete on public.appointments for each row execute function public.audit_row();
