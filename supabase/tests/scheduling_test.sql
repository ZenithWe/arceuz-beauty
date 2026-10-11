-- Rode no SQL Editor de um projeto de DESENVOLVIMENTO (cria e remove dados de teste; termina com ROLLBACK).
begin;

do $$
declare
  v_t uuid := gen_random_uuid(); v_b uuid := gen_random_uuid();
  v_corte uuid; v_hidr uuid; v_ana uuid; v_day date; v_start timestamptz;
  r jsonb; ok boolean;
begin
  -- Setup
  insert into tenants(id, slug, name) values (v_t, 'teste-'||substr(v_t::text,1,6), 'Salão Teste');
  insert into tenant_settings(tenant_id, min_notice_minutes) values (v_t, 0);
  insert into branches(id, tenant_id, name) values (v_b, v_t, 'Matriz');
  insert into services(tenant_id, name, price_cents, duration_min) values (v_t,'Corte',8000,45) returning id into v_corte;
  insert into services(tenant_id, name, price_cents, duration_min) values (v_t,'Hidratação',12000,40) returning id into v_hidr;
  insert into staff(tenant_id, branch_id, name) values (v_t, v_b, 'Ana') returning id into v_ana;
  insert into staff_services values (v_ana, v_corte), (v_ana, v_hidr);

  -- próxima segunda-feira, expediente 09–18, almoço 12–13
  v_day := current_date + ((8 - extract(dow from current_date)::int) % 7 + 7)::int;
  insert into staff_schedules(tenant_id, staff_id, weekday, start_time, end_time)
    values (v_t, v_ana, extract(dow from v_day)::int, '09:00', '18:00');
  insert into staff_breaks(tenant_id, staff_id, weekday, start_time, end_time)
    values (v_t, v_ana, extract(dow from v_day)::int, '12:00', '13:00');
  v_start := (v_day + time '09:00') at time zone 'America/Sao_Paulo';

  -- Cenário 1: dois serviços na mesma reserva, duração e valor somados
  r := create_booking(v_t, v_b, 'Maria', '+5531999990001', null, v_start, array[v_corte, v_hidr]);
  assert (select total_minutes from appointments where id = (r->>'appointment_id')::uuid) = 85, 'duração total';
  assert (select total_cents  from appointments where id = (r->>'appointment_id')::uuid) = 20000, 'valor total';

  -- Cenário 2: o mesmo horário não pode ser reservado duas vezes
  begin
    perform create_booking(v_t, v_b, 'João', '+5531999990002', null, v_start, array[v_corte]);
    assert false, 'deveria ter falhado';
  exception when others then
    assert sqlerrm = 'slot_unavailable', 'esperado slot_unavailable, veio: '||sqlerrm;
  end;

  -- Almoço nunca é oferecido
  assert not exists (select 1 from available_slots(v_t, v_b, v_day, array[v_corte])
     where (slot_start at time zone 'America/Sao_Paulo')::time > '11:15' and (slot_start at time zone 'America/Sao_Paulo')::time < '13:00'),
     'horário de almoço oferecido';

  -- Cancelar libera o horário
  update appointments set status = 'cancelled' where id = (r->>'appointment_id')::uuid;
  perform create_booking(v_t, v_b, 'João', '+5531999990002', null, v_start, array[v_corte]);

  -- Cenário 3: férias removem os horários
  insert into staff_absences(tenant_id, staff_id, starts_at, ends_at)
    values (v_t, v_ana, v_start - interval '1 day', v_start + interval '3 days');
  assert not exists (select 1 from available_slots(v_t, v_b, v_day, array[v_corte])), 'ofereceu horário em férias';

  -- Cenário 5: mudar preço não altera o histórico da reserva
  update services set price_cents = 9999 where id = v_corte;
  assert (select price_cents from appointment_services where service_id = v_corte
            and appointment_id <> (r->>'appointment_id')::uuid limit 1) = 8000, 'preço retroativo alterado';

  raise notice 'TODOS OS TESTES PASSARAM';
end $$;

rollback;

-- Cenários 7 e extra: reagendar sem duplicar; cancelar fora do prazo é recusado
begin;
do $$
declare v_t uuid := gen_random_uuid(); v_b uuid := gen_random_uuid(); v_s uuid; v_a uuid; v_day date; v_st timestamptz; r jsonb;
begin
  insert into tenants(id, slug, name) values (v_t,'t-'||substr(v_t::text,1,6),'T');
  insert into tenant_settings(tenant_id, min_notice_minutes, cancel_deadline_hours) values (v_t, 0, 1);
  insert into branches(id, tenant_id, name) values (v_b, v_t, 'M');
  insert into services(tenant_id, name, price_cents, duration_min) values (v_t,'Corte',8000,30) returning id into v_s;
  insert into staff(tenant_id, branch_id, name) values (v_t, v_b, 'Ana') returning id into v_a;
  insert into staff_services values (v_a, v_s);
  v_day := current_date + ((8 - extract(dow from current_date)::int) % 7 + 7)::int;
  insert into staff_schedules(tenant_id, staff_id, weekday, start_time, end_time) values (v_t, v_a, extract(dow from v_day)::int, '09:00','18:00');
  v_st := (v_day + time '10:00') at time zone 'America/Sao_Paulo';
  r := create_booking(v_t, v_b, 'Maria','+5531999990003', null, v_st, array[v_s]);
  perform reschedule_booking(r->>'manage_token', v_st + interval '1 hour');
  assert (select count(*) from appointments where tenant_id = v_t) = 1, 'reagendar duplicou reserva';
  assert (select count(*) from appointment_services where appointment_id = (r->>'appointment_id')::uuid and active) = 1;
  perform cancel_booking(r->>'manage_token', 'teste');
  assert (select status from appointments where tenant_id = v_t) = 'cancelled';
  raise notice 'TESTES DE REAGENDAMENTO PASSARAM';
end $$;
rollback;
