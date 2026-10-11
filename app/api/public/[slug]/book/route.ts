import { admin } from "@/lib/supabase/admin";
import { mapError, normalizePhone } from "@/lib/util";
import { z } from "zod";
const body = z.object({
  name: z.string().trim().min(2).max(120),
  phone: z.string().min(8).max(20),
  email: z.string().email().optional().or(z.literal("")),
  start: z.string().datetime({ offset: true }),
  services: z.array(z.string().uuid()).min(1).max(8),
});

export async function POST(req: Request, { params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const p = body.safeParse(await req.json().catch(() => null));
  if (!p.success) return Response.json({ error: "Confira os dados informados." }, { status: 400 });
  const db = admin();
  const { data: t } = await db.from("tenants").select("id").eq("slug", slug).in("status", ["trial", "active"]).single();
  if (!t) return Response.json({ error: "Salão não encontrado." }, { status: 404 });
  const { data: b } = await db.from("branches").select("id").eq("tenant_id", t.id).eq("active", true).order("created_at").limit(1).single();
  if (!b) return Response.json({ error: "Unidade indisponível." }, { status: 404 });

  const { data, error } = await db.rpc("create_booking", {
    p_tenant: t.id, p_branch: b.id, p_client_name: p.data.name, p_client_phone: normalizePhone(p.data.phone),
    p_client_email: p.data.email || null, p_start: p.data.start, p_services: p.data.services, p_staff: null, p_source: "public",
  });
  if (error) return mapError(error);
  return Response.json({ appointmentId: data.appointment_id, manageUrl: `/agendamento/${data.manage_token}` }, { status: 201 });
}
