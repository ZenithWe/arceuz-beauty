import { supabaseServer } from "@/lib/supabase/server";
import { redirect } from "next/navigation";
import { brl } from "@/lib/util";

export const dynamic = "force-dynamic";
export default async function Dashboard() {
  const sb = await supabaseServer();
  const { data: { user } } = await sb.auth.getUser();
  if (!user) redirect("/login");
  const start = new Date(); start.setHours(0, 0, 0, 0);
  const end = new Date(start); end.setDate(end.getDate() + 1);
  // RLS garante que só chegam registros do(s) salão(ões) do usuário e que ele tenha permissão de leitura.
  const { data: appts, error } = await sb.from("appointments")
    .select("id,starts_at,status,total_cents,clients(name)").gte("starts_at", start.toISOString()).lt("starts_at", end.toISOString())
    .order("starts_at");
  const active = (appts ?? []).filter((a) => !["cancelled", "no_show"].includes(a.status));
  return (<main><h1>Hoje</h1>
    {error && <p className="err" role="alert">Não foi possível carregar a agenda.</p>}
    <div className="row"><div className="card"><div className="muted">Agendamentos</div><strong>{active.length}</strong></div>
      <div className="card"><div className="muted">Receita prevista</div><strong>{brl(active.reduce((a, x) => a + x.total_cents, 0))}</strong></div></div>
    <h2>Agenda</h2>
    <div className="grid">{(appts ?? []).length === 0 && <p className="muted">Nenhum agendamento hoje.</p>}
      {(appts ?? []).map((a) => (<div className="card" key={a.id}>
        {new Date(a.starts_at).toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" })} · {(a.clients as unknown as { name: string } | null)?.name} · {a.status}</div>))}</div>
  </main>);
}
