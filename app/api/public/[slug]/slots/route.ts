import { admin } from "@/lib/supabase/admin";
import { z } from "zod";
const q = z.object({ date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/), services: z.string().min(1) });

export async function GET(req: Request, { params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const url = new URL(req.url);
  const parsed = q.safeParse({ date: url.searchParams.get("date"), services: url.searchParams.get("services") });
  if (!parsed.success) return Response.json({ error: "Parâmetros inválidos." }, { status: 400 });
  const services = parsed.data.services.split(",");
  if (!services.every((s) => z.string().uuid().safeParse(s).success)) return Response.json({ error: "Serviço inválido." }, { status: 400 });

  const db = admin();
  const { data: t } = await db.from("tenants").select("id,status").eq("slug", slug).in("status", ["trial", "active"]).single();
  if (!t) return Response.json({ error: "Salão não encontrado." }, { status: 404 });
  const { data: b } = await db.from("branches").select("id").eq("tenant_id", t.id).eq("active", true).order("created_at").limit(1).single();
  if (!b) return Response.json({ error: "Unidade indisponível." }, { status: 404 });

  const { data, error } = await db.rpc("available_slots", {
    p_tenant: t.id, p_branch: b.id, p_date: parsed.data.date, p_services: services, p_staff: null,
  });
  if (error) return Response.json({ error: "Não foi possível consultar os horários." }, { status: 500 });
  return Response.json({ slots: (data ?? []).map((r: { slot_start: string }) => r.slot_start) });
}
