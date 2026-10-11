import { admin } from "@/lib/supabase/admin";
import { notFound } from "next/navigation";
import { brl } from "@/lib/util";
import ManageActions from "@/components/ManageActions";

export const dynamic = "force-dynamic";
export default async function Manage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  const { data: b } = await admin().rpc("get_booking", { p_token: token });
  if (!b) notFound();
  const when = new Date(b.starts_at).toLocaleString("pt-BR", { dateStyle: "full", timeStyle: "short", timeZone: "America/Sao_Paulo" });
  return (<main><h1>Seu agendamento</h1>
    <div className="card"><p><strong>{when}</strong> · {b.status}</p>
      <ul>{b.services?.map((s: { name: string; staff: string }, i: number) => <li key={i}>{s.name} com {s.staff}</li>)}</ul>
      <p>Total: {brl(b.total_cents)} (pago no salão)</p></div>
    {["scheduled", "confirmed"].includes(b.status) && <ManageActions token={token} />}</main>);
}
