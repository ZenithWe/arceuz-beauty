"use client";
import { useEffect, useMemo, useState } from "react";
import { brl } from "@/lib/util";

type Svc = { id: string; name: string; description: string | null; price_cents: number; duration_min: number };
const fmtTime = (iso: string) => new Date(iso).toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit", timeZone: "America/Sao_Paulo" });

export default function BookingForm({ slug, services }: { slug: string; services: Svc[] }) {
  const [sel, setSel] = useState<string[]>([]);
  const [date, setDate] = useState("");
  const [slots, setSlots] = useState<string[] | null>(null);
  const [slot, setSlot] = useState("");
  const [name, setName] = useState(""); const [phone, setPhone] = useState("");
  const [busy, setBusy] = useState(false); const [error, setError] = useState(""); const [done, setDone] = useState("");

  const chosen = useMemo(() => services.filter((s) => sel.includes(s.id)), [sel, services]);
  const total = chosen.reduce((a, s) => a + s.price_cents, 0);
  const minutes = chosen.reduce((a, s) => a + s.duration_min, 0);

  useEffect(() => {
    setSlot(""); setSlots(null);
    if (!sel.length || !date) return;
    const ac = new AbortController();
    fetch(`/api/public/${slug}/slots?date=${date}&services=${sel.join(",")}`, { signal: ac.signal })
      .then(async (r) => { const j = await r.json(); if (!r.ok) throw new Error(j.error); setSlots(j.slots); setError(""); })
      .catch((e) => { if (e.name !== "AbortError") setError(e.message || "Falha de conexão. Tente novamente."); });
    return () => ac.abort();
  }, [sel, date, slug]);

  async function submit() {
    setBusy(true); setError("");
    try {
      const r = await fetch(`/api/public/${slug}/book`, { method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name, phone, start: slot, services: sel }) });
      const j = await r.json();
      if (!r.ok) { setError(j.error); if (r.status === 409) setSlot(""); return; }
      setDone(j.manageUrl);
    } catch { setError("Falha de conexão. Tente novamente."); } finally { setBusy(false); }
  }

  if (done) return (<div className="card" role="status"><h2>Agendamento confirmado ✓</h2>
    <p>Guarde este link para acompanhar, reagendar ou cancelar:</p><a href={done}>{typeof window !== "undefined" ? window.location.origin : ""}{done}</a></div>);

  return (
    <div className="grid">
      <fieldset className="grid" style={{ border: 0, padding: 0 }}><legend><h2>1. Serviços</h2></legend>
        {services.length === 0 && <p className="muted">Este salão ainda não cadastrou serviços.</p>}
        {services.map((s) => (
          <button key={s.id} type="button" className="chip card" aria-pressed={sel.includes(s.id)}
            onClick={() => setSel((c) => c.includes(s.id) ? c.filter((x) => x !== s.id) : [...c, s.id])}>
            {s.name} · {s.duration_min} min · {brl(s.price_cents)}
          </button>))}
      </fieldset>
      {chosen.length > 0 && <p><strong>{minutes} min</strong> no total · <strong>{brl(total)}</strong></p>}
      <label><h2>2. Data</h2><input type="date" value={date} min={new Date().toISOString().slice(0, 10)} onChange={(e) => setDate(e.target.value)} /></label>
      {sel.length > 0 && date && (<div><h2>3. Horário</h2>
        {slots === null ? <p className="muted">Buscando horários…</p> : slots.length === 0 ? <p className="muted">Sem horários nesse dia. Tente outra data.</p> :
          <div className="row">{slots.map((s) => <button key={s} type="button" className="chip" aria-pressed={slot === s} onClick={() => setSlot(s)}>{fmtTime(s)}</button>)}</div>}
      </div>)}
      {slot && (<div className="grid"><h2>4. Seus dados</h2>
        <input placeholder="Seu nome" value={name} onChange={(e) => setName(e.target.value)} autoComplete="name" />
        <input placeholder="WhatsApp com DDD" inputMode="tel" value={phone} onChange={(e) => setPhone(e.target.value)} autoComplete="tel" />
        <button className="btn" disabled={busy || name.trim().length < 2 || phone.replace(/\D/g, "").length < 10} onClick={submit}>
          {busy ? "Confirmando…" : `Confirmar agendamento · ${brl(total)}`}</button></div>)}
      {error && <p className="err" role="alert">{error}</p>}
    </div>);
}
