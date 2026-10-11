-- ARCEUZ BEAUTY OS — 0001 Fundação: multi-tenant, RBAC, RLS, auditoria
create extension if not exists btree_gist;
create extension if not exists pgcrypto;

-- ───────── Tenants ─────────
create table public.tenants (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  name text not null,
  status text not null default 'trial' check (status in ('trial','active','suspended','cancelled')),
  created_at timestamptz not null default now()
);

create table public.tenant_settings (
  tenant_id uuid primary key references public.tenants(id) on delete cascade,
  timezone text not null default 'America/Sao_Paulo',
  min_notice_minutes int not null default 60 check (min_notice_minutes >= 0),
  max_advance_days int not null default 60 check (max_advance_days > 0),
  cancel_deadline_hours int not null default 12 check (cancel_deadline_hours >= 0),
  max_reschedules int not null default 2,
  slot_step_minutes int not null default 15 check (slot_step_minutes between 5 and 60),
  deposit_enabled boolean not null default false,   -- sinal é opcional
  deposit_percent numeric(5,2) check (deposit_percent between 0 and 100),
  brand jsonb not null default '{"primary":"#FF6500","logo":null}'::jsonb,
  updated_at timestamptz not null default now()
);

create table public.branches (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  name text not null,
  address text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (tenant_id, id)
);
create index on public.branches (tenant_id);

-- ───────── Usuários / papéis ─────────
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  avatar_url text,
  created_at timestamptz not null default now()
);

create table public.platform_admins (          -- Superadmin Arceuz (gerenciado só via service_role)
  user_id uuid primary key references auth.users(id) on delete cascade
);

create table public.roles (key text primary key, label text not null);
create table public.permissions (key text primary key, description text not null);
create table public.role_permissions (
  role_key text references public.roles(key) on delete cascade,
  permission_key text references public.permissions(key) on delete cascade,
  primary key (role_key, permission_key)
);

create table public.memberships (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null references public.roles(key),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (tenant_id, user_id)
);
create index on public.memberships (user_id);

insert into public.roles values
 ('owner','Proprietário'),('manager','Gerente'),('receptionist','Recepcionista'),('professional','Profissional');

insert into public.permissions values
 ('appointments.read','Ver todos os agendamentos'),
 ('appointments.read_own','Ver apenas os próprios agendamentos'),
 ('appointments.write','Criar/editar/cancelar agendamentos'),
 ('schedule.manage','Gerir escalas, folgas e bloqueios'),
 ('services.manage','Gerir serviços'),
 ('prices.write','Editar preços'),
 ('clients.read','Ver clientes'),
 ('clients.write','Cadastrar/editar clientes'),
 ('clients.delete','Excluir clientes'),
 ('staff.manage','Gerir funcionários e permissões'),
 ('finance.read','Ver financeiro'),
 ('finance.write','Editar financeiro'),
 ('commissions.read','Ver comissões'),
 ('reports.export','Exportar relatórios'),
 ('settings.write','Alterar configurações'),
 ('integrations.manage','Administrar integrações');

insert into public.role_permissions select 'owner', key from public.permissions;
insert into public.role_permissions select 'manager', key from public.permissions where key <> 'integrations.manage';
insert into public.role_permissions values
 ('receptionist','appointments.read'),('receptionist','appointments.write'),
 ('receptionist','clients.read'),('receptionist','clients.write'),
 ('professional','appointments.read_own');

-- ───────── Helpers de autorização (server-side, usados nas políticas RLS) ─────────
create or replace function public.is_member(p_tenant uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from memberships m
    where m.tenant_id = p_tenant and m.user_id = auth.uid() and m.active)
$$;

create or replace function public.has_perm(p_tenant uuid, p_perm text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from memberships m
    join role_permissions rp on rp.role_key = m.role
    where m.tenant_id = p_tenant and m.user_id = auth.uid() and m.active
      and rp.permission_key = p_perm)
$$;

-- ───────── Auditoria ─────────
create table public.audit_logs (
  id bigint generated always as identity primary key,
  tenant_id uuid,
  actor uuid,
  table_name text not null,
  row_id text,
  action text not null,
  old_data jsonb,
  new_data jsonb,
  at timestamptz not null default now()
);
create index on public.audit_logs (tenant_id, at desc);

create or replace function public.audit_row() returns trigger
language plpgsql security definer set search_path = public as $$
declare r jsonb := to_jsonb(coalesce(new, old));
begin
  insert into audit_logs(tenant_id, actor, table_name, row_id, action, old_data, new_data)
  values ((r->>'tenant_id')::uuid, auth.uid(), tg_table_name, r->>'id', tg_op,
          case when tg_op <> 'INSERT' then to_jsonb(old) end,
          case when tg_op <> 'DELETE' then to_jsonb(new) end);
  return coalesce(new, old);
end $$;

-- ───────── Criação de tenant (onboarding) ─────────
create or replace function public.create_tenant(p_name text, p_slug text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_tenant uuid;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  insert into tenants(name, slug) values (p_name, lower(p_slug)) returning id into v_tenant;
  insert into tenant_settings(tenant_id) values (v_tenant);
  insert into branches(tenant_id, name) values (v_tenant, 'Unidade principal');
  insert into memberships(tenant_id, user_id, role) values (v_tenant, auth.uid(), 'owner');
  return v_tenant;
end $$;
revoke all on function public.create_tenant(text,text) from public, anon;
grant execute on function public.create_tenant(text,text) to authenticated;

-- ───────── RLS ─────────
alter table public.tenants enable row level security;
alter table public.tenant_settings enable row level security;
alter table public.branches enable row level security;
alter table public.profiles enable row level security;
alter table public.memberships enable row level security;
alter table public.audit_logs enable row level security;
alter table public.platform_admins enable row level security;   -- sem políticas: só service_role
alter table public.roles enable row level security;
alter table public.permissions enable row level security;
alter table public.role_permissions enable row level security;

create policy roles_read on public.roles for select to authenticated using (true);
create policy perms_read on public.permissions for select to authenticated using (true);
create policy rp_read on public.role_permissions for select to authenticated using (true);

create policy tenants_read on public.tenants for select to authenticated using (is_member(id));
create policy tenants_update on public.tenants for update to authenticated
  using (has_perm(id,'settings.write')) with check (has_perm(id,'settings.write'));

create policy settings_read on public.tenant_settings for select to authenticated using (is_member(tenant_id));
create policy settings_write on public.tenant_settings for update to authenticated
  using (has_perm(tenant_id,'settings.write')) with check (has_perm(tenant_id,'settings.write'));

create policy branches_read on public.branches for select to authenticated using (is_member(tenant_id));
create policy branches_write on public.branches for all to authenticated
  using (has_perm(tenant_id,'settings.write')) with check (has_perm(tenant_id,'settings.write'));

create policy profiles_self on public.profiles for select to authenticated using (id = auth.uid());
create policy profiles_self_upd on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

create policy memberships_read on public.memberships for select to authenticated
  using (user_id = auth.uid() or has_perm(tenant_id,'staff.manage'));
create policy memberships_write on public.memberships for all to authenticated
  using (has_perm(tenant_id,'staff.manage')) with check (has_perm(tenant_id,'staff.manage'));

create policy audit_read on public.audit_logs for select to authenticated
  using (tenant_id is not null and has_perm(tenant_id,'staff.manage'));

create trigger audit_memberships after insert or update or delete on public.memberships
  for each row execute function public.audit_row();

-- Cria profile automaticamente no signup
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles(id, full_name) values (new.id, new.raw_user_meta_data->>'full_name');
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();
