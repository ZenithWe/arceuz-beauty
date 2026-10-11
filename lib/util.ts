export const normalizePhone = (raw: string) => {
  const d = raw.replace(/\D/g, "");
  return d.startsWith("55") ? `+${d}` : `+55${d}`;
};
export const brl = (cents: number) => (cents / 100).toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
export const ERRORS: Record<string, [number, string]> = {
  slot_unavailable: [409, "Esse horário acabou de ser ocupado. Escolha outro, por favor."],
  too_soon: [400, "Esse horário exige mais antecedência."],
  too_far: [400, "Esse horário está além do limite de reservas futuras."],
  too_late: [403, "O prazo para alterar ou cancelar já passou. Fale com o salão."],
  reschedule_limit: [403, "Limite de reagendamentos atingido. Fale com o salão."],
  not_found: [404, "Reserva não encontrada."],
  not_cancellable: [409, "Esta reserva não pode mais ser cancelada."],
  not_reschedulable: [409, "Esta reserva não pode mais ser reagendada."],
};
export function mapError(e: { message?: string }) {
  const [status, message] = ERRORS[e.message ?? ""] ?? [500, "Algo deu errado. Tente novamente em instantes."];
  return Response.json({ error: message }, { status });
}
