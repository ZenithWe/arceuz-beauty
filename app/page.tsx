import Link from "next/link";

export default function Home() {
  return (
    <main style={{ maxWidth: 980, paddingTop: 72 }}>
      <header style={{ display: "flex", justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", gap: 16 }}>
        <strong style={{ letterSpacing: 2, fontSize: 20 }}>ARCEUZ <span style={{ color: "var(--brand)" }}>BEAUTY OS</span></strong>
        <Link className="btn" style={{ display: "inline-flex", alignItems: "center", textDecoration: "none" }} href="/login">Entrar no painel</Link>
      </header>
      <section style={{ padding: "100px 0 60px" }}>
        <p style={{ color: "var(--brand)", fontWeight: 700, letterSpacing: 2 }}>GESTÃO E AGENDAMENTOS PARA SALÕES</p>
        <h1 style={{ fontSize: "clamp(36px, 6vw, 68px)", lineHeight: 1.12, margin: "20px 0", maxWidth: 850 }}>Seu salão organizado. Sua agenda sob controle.</h1>
        <p style={{ maxWidth: 620, color: "var(--muted)", lineHeight: 1.8, fontSize: 18 }}>Agendamentos online, serviços combinados na mesma reserva e painel para acompanhar os atendimentos. A plataforma está em fase inicial de configuração.</p>
        <div className="row" style={{ marginTop: 32 }}>
          <Link className="btn" href="/login" style={{ textDecoration: "none", display: "inline-flex", alignItems: "center" }}>Acessar painel</Link>
        </div>
      </section>
      <section className="row">
        {[
          ["Agenda inteligente", "Consulta de horários e agendamentos sem conflito."],
          ["Vários serviços", "O cliente pode selecionar mais de um serviço em uma reserva."],
          ["Gestão segura", "Painel com autenticação e permissões por salão."],
        ].map(([title, description]) => (
          <article className="card" key={title} style={{ flex: "1 1 230px" }}>
            <h2>{title}</h2><p className="muted">{description}</p>
          </article>
        ))}
      </section>
      <footer style={{ paddingTop: 70, color: "var(--muted)" }}>© ARCEUZ · Beauty OS</footer>
    </main>
  );
}
