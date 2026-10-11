import { supabaseServer } from "@/lib/supabase/server";
import { redirect } from "next/navigation";
async function login(fd: FormData) {
  "use server";
  const sb = await supabaseServer();
  const { error } = await sb.auth.signInWithPassword({ email: String(fd.get("email")), password: String(fd.get("password")) });
  if (error) redirect("/login?e=1");
  redirect("/dashboard");
}
export default async function Login({ searchParams }: { searchParams: Promise<{ e?: string }> }) {
  const { e } = await searchParams;
  return (<main><h1>Entrar</h1><form action={login} className="grid">
    <input name="email" type="email" placeholder="E-mail" required autoComplete="email" />
    <input name="password" type="password" placeholder="Senha" required autoComplete="current-password" />
    <button className="btn">Entrar</button>{e && <p className="err" role="alert">E-mail ou senha inválidos.</p>}</form></main>);
}
