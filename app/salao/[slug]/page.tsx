import { admin } from "@/lib/supabase/admin";
import { notFound } from "next/navigation";
import BookingForm from "@/components/BookingForm";

export async function generateMetadata({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const { data: t } = await admin().from("tenants").select("name").eq("slug", slug).single();
  return { title: t ? `${t.name} — Agende online` : "Salão", openGraph: { title: t?.name } };
}

export default async function SalonPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const db = admin();
  const { data: t } = await db.from("tenants").select("id,name,status").eq("slug", slug).in("status", ["trial", "active"]).single();
  if (!t) notFound();
  const { data: services } = await db.from("services").select("id,name,description,price_cents,duration_min")
    .eq("tenant_id", t.id).eq("active", true).order("name");
  return (
    <main>
      <h1>{t.name}</h1>
      <p className="muted">Escolha um ou mais serviços e agende sem criar conta. O pagamento é feito no salão.</p>
      <BookingForm slug={slug} services={services ?? []} />
    </main>
  );
}
