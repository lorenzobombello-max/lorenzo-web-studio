import { createClient } from "npm:@supabase/supabase-js@2";
import { handleQuotationAcceptance } from "../_shared/quotation-acceptance-handler.ts";
import { deliverAcceptanceConfirmation } from "../_shared/quotation-email-orchestration.ts";

async function confirmationIdempotencyKey(acceptanceId: string, audience: "customer" | "internal"): Promise<string> {
  const hash = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`lws-quotation-acceptance-confirmation:v1:${audience}:${acceptanceId}`)));
  hash[6] = (hash[6] & 0x0f) | 0x50;
  hash[8] = (hash[8] & 0x3f) | 0x80;
  const hex = [...hash.slice(0, 16)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

Deno.serve((request) => {
  const url = Deno.env.get("SUPABASE_URL"); const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) return new Response(JSON.stringify({ ok: false, state: "ACCEPTANCE_NOT_AVAILABLE" }), { status: 500, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" } });
  const client = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  return handleQuotationAcceptance(request, client, async (acceptanceId) => {
    const resendApiKey = Deno.env.get("RESEND_API_KEY") || "";
    const from = Deno.env.get("FROM_EMAIL") || "";
    const internalRecipient = Deno.env.get("ADMIN_EMAIL") || "";
    if (!resendApiKey || !from || !internalRecipient) throw new Error("Quotation confirmation email configuration missing");
    const results = await Promise.allSettled([
      deliverAcceptanceConfirmation({ supabase: client, acceptanceId, template: "ACCEPTANCE_CONFIRMATION_CUSTOMER_NL_BE_v1", idempotencyKey: await confirmationIdempotencyKey(acceptanceId, "customer"), createdBy: "service:quotation-acceptance", from, resendApiKey }),
      deliverAcceptanceConfirmation({ supabase: client, acceptanceId, template: "ACCEPTANCE_CONFIRMATION_INTERNAL_NL_BE_v1", idempotencyKey: await confirmationIdempotencyKey(acceptanceId, "internal"), createdBy: "service:quotation-acceptance", internalRecipient, from, resendApiKey }),
    ]);
    if (results.some((result) => result.status === "rejected" || result.value.status !== "sent")) throw new Error("Quotation confirmation delivery incomplete");
  });
});