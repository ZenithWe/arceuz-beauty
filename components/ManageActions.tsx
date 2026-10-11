"use client";
import { useState } from "react";
export default function ManageActions({ token }: { token: string }) {
  const [msg, setMsg] = useState(""); const [busy, setBusy] = useState(false); const [start, setStart] = useState("");
  async function call(payload: object) {
    setBusy(true); setMsg("");
    try { const r = await fetch("/api/public/manage", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ token, ...payload }) });
      const j = await r.json(); if (!r.ok) setMsg(j.error); else location.reload();
    } catch { setMsg("Falha de conexão. Tente novamente."); } finally { setBusy(false); }
  }
  return (<div className="grid" style={{ marginTop: 16 }}>
    <label>Novo horário<input type="datetime-local" value={start} onChange={(e) => setStart(e.target.value)} /></label>
    <button className="btn" disabled={busy || !start} onClick={() => call({ action: "reschedule", start: new Date(start).toISOString() })}>Reagendar</button>
    <button className="chip" disabled={busy} onClick={() => confirm("Cancelar este agendamento?") && call({ action: "cancel" })}>Cancelar agendamento</button>
    {msg && <p className="err" role="alert">{msg}</p>}</div>);
}
