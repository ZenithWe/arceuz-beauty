# ARCEUZ BEAUTY OS — Fundação + Agendamento (Etapas 1 e 2)

## O que está neste pacote

| Arquivo | Conteúdo |
|---|---|
| `supabase/migrations/0001_foundation.sql` | Multi-tenant, configurações por salão, unidades, perfis, RBAC (papéis + 16 permissões granulares), RLS, auditoria, `create_tenant()` para onboarding |
| `supabase/migrations/0002_scheduling.sql` | Serviços (+ histórico de preços), equipe, escalas, pausas, férias, bloqueios, clientes, agendamentos com múltiplos serviços, motor de disponibilidade, reserva transacional, RLS |
| `supabase/tests/scheduling_test.sql` | Testes dos cenários 1, 2, 3 e 5 do prompt (termina em ROLLBACK) |
| `app/styles/tokens.css` | Tokens de design (paleta Arceuz, claro/escuro, `prefers-reduced-motion`) |

## Como aplicar
1. Crie um projeto Supabase **de desenvolvimento**.
2. Rode `0001` e depois `0002` (SQL Editor ou `supabase db push`).
3. Rode `supabase/tests/scheduling_test.sql`; deve emitir `TODOS OS TESTES PASSARAM`.

## Decisões de arquitetura
- **Sem agendamento duplicado, garantido pelo banco:** `EXCLUDE USING gist` em `appointment_services` impede sobreposição de um mesmo profissional (incluindo o intervalo de preparo). Em corrida entre dois clientes, um deles recebe `slot_unavailable` e a transação inteira é revertida.
- **Múltiplos serviços:** `plan_chain()` encadeia os serviços em sequência, escolhendo o profissional por serviço (específico ou "qualquer disponível"), somando duração e valor.
- **Disponibilidade real:** `staff_is_free()` considera expediente, almoço/pausas, férias/ausências, bloqueios (do profissional ou do salão todo), outros agendamentos e buffer, em fuso horário do tenant. `available_slots()` aplica antecedência mínima e limite futuro.
- **Preço histórico:** cada `appointment_services` guarda snapshot de preço e duração; alterar o serviço depois não muda reservas existentes.
- **Segurança:** RLS em todas as tabelas; permissões verificadas no servidor via `has_perm()`. Reservas públicas só entram por `create_booking()` (apenas `service_role`, chamado por uma rota do servidor). O token de gestão do cliente é aleatório e só o hash SHA-256 é armazenado. Superadmin **não** tem acesso via RLS (acesso de suporte deve ser feito por rota própria, justificada e auditada).
- Valores monetários em centavos (`integer`).

## Status honesto
**Implementado (SQL):** itens acima.
**Não verificado:** não executei as migrations contra um banco real nesta sessão; o teste foi escrito mas não rodado. Rode-o antes de confiar no resultado.
**Não implementado ainda:** app Next.js (telas, calendário, página pública, dashboard), recursos/salas, lista de espera, reagendamento/cancelamento pelo link do cliente (as colunas existem; falta a RPC), financeiro, estoque, PDV, mensagens, IA, multiunidade avançada, superadmin, planos SaaS. Nenhuma integração (Mercado Pago, WhatsApp, e-mail) foi criada.
**Limitações conhecidas:** atendimentos não cruzam a meia-noite; escalas em hora local sem validade por período; horários de feriado entram como `schedule_blocks` com `staff_id` nulo; sem DST (ok para o Brasil atual); a escolha de profissional "qualquer" é a primeira livre (sem balanceamento de carga).

## Próxima etapa
1. Rodar e corrigir os testes no seu Supabase.
2. RPCs `reschedule_booking` / `cancel_booking` (token do cliente) e lista de espera.
3. Projeto Next.js (App Router, Tailwind, shadcn/ui, Framer Motion): shell do painel, página pública `/salao/[slug]` com fluxo de agendamento, calendário.


## Atualização: 0003 + app Next.js (primeira versão)
- `0003_booking_management.sql`: `get_booking`, `cancel_booking` (respeita prazo), `reschedule_booking` (mantém a mesma reserva, sem duplicar; respeita limite), `join_waitlist` e `waitlist_entries`. Ao cancelar, entradas da lista de espera do dia ficam `offered` por 30 min (o aviso em si ainda não é enviado).
- App Next.js 15: `/salao/[slug]` (múltiplos serviços, horários reais, sem conta), `/agendamento/[token]` (cancelar/reagendar), `/login`, `/dashboard` (agenda e receita *prevista* do dia via RLS), rotas `/api/public/*` validadas com Zod.
- **Não verificado:** `npm install`, `tsc` e `next build` não completaram no ambiente onde gerei o código (timeout). Rode `npm install && npm run typecheck && npm run build` e corrija o que aparecer. As migrations e os testes SQL também não foram executados.
- **Ausente:** calendário arrastável, editor de página pública, financeiro, estoque, PDV, comunicação, IA, superadmin, planos SaaS e integrações (Mercado Pago, WhatsApp, e-mail).
- Setup: copie `.env.example` para `.env.local` e preencha as chaves do Supabase.