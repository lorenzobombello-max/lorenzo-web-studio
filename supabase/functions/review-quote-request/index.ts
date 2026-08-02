import { createClient } from "npm:@supabase/supabase-js@2";
import { buildApprovedConfirmationEmail } from "../_shared/email-templates.ts";
import { corsHeaders, rejectIfOriginNotAllowed } from "../_shared/cors.ts";
import { hashApprovalToken } from "../_shared/security.ts";
import { validateAction, validateToken } from "../_shared/validation.ts";

type ReviewState = "pending" | "approved" | "rejected" | "expired" | "invalid";

function jsonResponse(status: number, body: Record<string, unknown>, origin: string | null): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(origin),
      "Content-Type": "application/json",
    },
  });
}

Deno.serve(async (request) => {
  const origin = request.headers.get("origin");

  if (request.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: corsHeaders(origin),
    });
  }

  const blocked = rejectIfOriginNotAllowed(request);
  if (blocked) return blocked;

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const resendApiKey = Deno.env.get("RESEND_API_KEY");
  const fromEmail = Deno.env.get("FROM_EMAIL");

  if (!supabaseUrl || !serviceRoleKey || !resendApiKey || !fromEmail) {
    return jsonResponse(500, {
      ok: false,
      message: "Server configuration is incomplete.",
    }, origin);
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  if (request.method === "GET") {
    const tokenRaw = new URL(request.url).searchParams.get("token") || "";
    let token: string;

    try {
      token = validateToken(tokenRaw);
    } catch {
      return jsonResponse(200, { ok: true, state: "invalid" satisfies ReviewState }, origin);
    }

    const tokenHash = await hashApprovalToken(token);

    const { data, error } = await supabase
      .from("quote_requests")
      .select("id, created_at, name, company, email, phone, website_type, budget, timing, description, status, approval_token_expires_at, reviewed_at")
      .eq("approval_token_hash", tokenHash)
      .maybeSingle();

    if (error || !data) {
      return jsonResponse(200, { ok: true, state: "invalid" satisfies ReviewState }, origin);
    }

    const now = Date.now();
    const expiresAt = data.approval_token_expires_at ? Date.parse(data.approval_token_expires_at) : 0;

    if (data.status === "pending" && expiresAt > 0 && expiresAt < now) {
      return jsonResponse(200, {
        ok: true,
        state: "expired" satisfies ReviewState,
        request: {
          id: data.id,
          created_at: data.created_at,
        },
      }, origin);
    }

    if (data.status === "approved" || data.status === "rejected") {
      return jsonResponse(200, {
        ok: true,
        state: data.status as ReviewState,
        request: {
          id: data.id,
          reviewed_at: data.reviewed_at,
        },
      }, origin);
    }

    return jsonResponse(200, {
      ok: true,
      state: "pending" satisfies ReviewState,
      request: {
        id: data.id,
        created_at: data.created_at,
        name: data.name,
        company: data.company,
        email: data.email,
        phone: data.phone,
        website_type: data.website_type,
        budget: data.budget,
        timing: data.timing,
        description: data.description,
      },
    }, origin);
  }

  if (request.method === "POST") {
    let body: Record<string, unknown>;
    try {
      body = await request.json();
    } catch {
      return jsonResponse(400, { ok: false, message: "Invalid request payload." }, origin);
    }

    let token: string;
    let action: "approved" | "rejected";

    try {
      token = validateToken(body.token);
      action = validateAction(body.action);
    } catch {
      return jsonResponse(400, { ok: false, message: "Invalid review action." }, origin);
    }

    const tokenHash = await hashApprovalToken(token);

    const { data: existing, error: fetchError } = await supabase
      .from("quote_requests")
      .select("id, name, email, status, approval_token_expires_at")
      .eq("approval_token_hash", tokenHash)
      .maybeSingle();

    if (fetchError || !existing) {
      return jsonResponse(200, { ok: true, state: "invalid" satisfies ReviewState }, origin);
    }

    const nowIso = new Date().toISOString();
    const expiresAt = existing.approval_token_expires_at ? Date.parse(existing.approval_token_expires_at) : 0;

    if (existing.status !== "pending") {
      return jsonResponse(200, { ok: true, state: existing.status as ReviewState }, origin);
    }

    if (expiresAt > 0 && expiresAt < Date.now()) {
      return jsonResponse(200, { ok: true, state: "expired" satisfies ReviewState }, origin);
    }

    const { data: updatedRows, error: updateError } = await supabase
      .from("quote_requests")
      .update({
        status: action,
        reviewer_action: action,
        reviewed_at: nowIso,
      })
      .eq("id", existing.id)
      .eq("status", "pending")
      .eq("approval_token_hash", tokenHash)
      .gt("approval_token_expires_at", nowIso)
      .select("id, name, email, status")
      .limit(1);

    if (updateError || !updatedRows || updatedRows.length === 0) {
      const { data: current } = await supabase
        .from("quote_requests")
        .select("status, reviewed_at")
        .eq("id", existing.id)
        .maybeSingle();

      if (current?.status === "approved" || current?.status === "rejected") {
        return jsonResponse(200, {
          ok: true,
          state: current.status as ReviewState,
          request: { id: existing.id, reviewed_at: current.reviewed_at ?? nowIso },
        }, origin);
      }

      return jsonResponse(200, { ok: true, state: "expired" satisfies ReviewState }, origin);
    }

    const updated = updatedRows[0];

    if (updated.status === "approved") {
      const confirmationEmail = buildApprovedConfirmationEmail(updated.name);
      const emailResponse = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${resendApiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          from: fromEmail,
          to: [updated.email],
          subject: confirmationEmail.subject,
          html: confirmationEmail.html,
          text: confirmationEmail.text,
        }),
      });

      if (emailResponse.ok) {
        await supabase
          .from("quote_requests")
          .update({ confirmation_sent_at: new Date().toISOString() })
          .eq("id", updated.id)
          .eq("status", "approved");
      }

      return jsonResponse(200, {
        ok: true,
        state: "approved" satisfies ReviewState,
        mail_sent: emailResponse.ok,
      }, origin);
    }

    return jsonResponse(200, {
      ok: true,
      state: "rejected" satisfies ReviewState,
      mail_sent: false,
    }, origin);
  }

  return jsonResponse(405, { ok: false, message: "Method not allowed." }, origin);
});
