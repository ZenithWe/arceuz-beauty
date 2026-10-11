import { admin } from "@/lib/supabase/admin";
import { mapError } from "@/lib/util";
import { z } from "zod";
const body = z.discriminatedUnion("action", [
  z.object({ action: z.literal("cancel"), token: z.string().min(20), reason: z.string().max(300).optional() }),
  z.object({ action: z.literal("reschedule"), token: z.string().min(20), start: z.string().datetime({ offset: true }) }),
]);

export async function POST(req: Request) {
  const p = body.safeParse(await req.json().catch(() => null));
  if (!p.success) return Response.json({ error: "Requisição inválida." }, { status: 400 });
  const db = admin();
  const { error } = p.data.action === "cancel"
    ? await db.rpc("cancel_booking", { p_token: p.data.token, p_reason: p.data.reason ?? null })
    : await db.rpc("reschedule_booking", { p_token: p.data.token, p_new_start: p.data.start });
  if (error) return mapError(error);
  return Response.json({ ok: true });
}
