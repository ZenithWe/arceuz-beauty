import "server-only";
import { createClient } from "@supabase/supabase-js";
// Cliente com service_role: usar apenas em rotas/Server Components. Nunca importar em código de navegador.
export const admin = () =>
  createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY!, {
    auth: { persistSession: false },
  });
