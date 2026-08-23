import { createClient } from "npm:@supabase/supabase-js@2";
import { handleCommercialOperator, withCommercialOperatorCors } from "./handler.ts";
import {
  createApprovalTokenForIdempotencyKey,
  createInternalE2EIntakeTokenForIdempotencyKey,
  deriveAdminIntakeCapability,
  hashAdminIntakeToken,
  hashApprovalToken,
  hashIntakeToken,
} from "../_shared/security.ts";

async function sha256(value: string): Promise<string> {
  const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(bytes)].map((byte)=>byte.toString(16).padStart(2, "0")).join("");
}
Deno.serve((request)=>withCommercialOperatorCors(request, ()=>{
  const url = Deno.env.get("SUPABASE_URL"), anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !anonKey) return new Response(JSON.stringify({
    ok: false,
    code: "SERVER_CONFIGURATION_ERROR"
  }), {
    status: 500,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store"
    }
  });
  const clientFor = (jwt)=>createClient(url, anonKey, {
      global: {
        headers: {
          Authorization: `Bearer ${jwt}`
        }
      },
      auth: {
        persistSession: false,
        autoRefreshToken: false
      }
    });
  return handleCommercialOperator(request, {
    now: ()=>Date.now(),
    verifyUser: async (jwt)=>{
      const { data, error } = await clientFor(jwt).auth.getUser(jwt);
      return error || !data.user ? null : {
        id: data.user.id
      };
    },
    consumeRateLimit: async (jwt, projectId)=>{
      const { data, error } = await clientFor(jwt).rpc("consume_commercial_operator_rate_limit_v1", {
        p_project_id: projectId,
        p_max_requests: 60,
        p_window_seconds: 60
      });
      if (error) throw new Error(error.message);
      return data;
    },
    executeApplicationAction: async (jwt, input)=>{
      const client = clientFor(jwt);
      if (["interrupt_intake", "resume_intake", "cancel_intake", "reactivate_intake"].includes(input.action)) {
        const { data, error } = await client.rpc("execute_operator_intake_lifecycle_command_v1", {
          p_intake_id: input.intake_id,
          p_event_type: input.event_type,
          p_expected_revision: input.expected_revision,
          p_idempotency_key: input.idempotency_key,
          p_reason: input.reason,
        });
        if (error) throw new Error(error.message);
        return data;
      }
      if (input.action === "create_internal_e2e_run") {
        const approvalToken = await createApprovalTokenForIdempotencyKey(input.idempotency_key);
        const intakeToken = await createInternalE2EIntakeTokenForIdempotencyKey(input.idempotency_key);
        const intakeTokenHash = await hashIntakeToken(intakeToken);
        const adminToken = await deriveAdminIntakeCapability(intakeTokenHash);
        const requestFingerprint = await sha256(JSON.stringify({
          contract_version: 1,
          run_label: input.run_label,
          ttl_minutes: input.ttl_minutes,
        }));
        const { data, error } = await client.rpc("create_internal_e2e_run_v1", {
          p_idempotency_key: input.idempotency_key,
          p_request_fingerprint: requestFingerprint,
          p_run_label: input.run_label,
          p_ttl_minutes: input.ttl_minutes,
          p_approval_token_hash: await hashApprovalToken(approvalToken),
          p_intake_access_token_hash: intakeTokenHash,
          p_admin_access_token_hash: await hashAdminIntakeToken(adminToken),
        });
        if (error) throw new Error(error.message);
        return { ...data, intake_token: intakeToken, admin_intake_token: adminToken };
      }
      if (input.action === "finalize_internal_e2e_run") {
        const { data, error } = await client.rpc("finalize_internal_e2e_run_v1", {
          p_run_id: input.run_id,
          p_terminal_status: input.terminal_status,
          p_expected_revision: input.expected_revision,
          p_idempotency_key: input.idempotency_key,
        });
        if (error) throw new Error(error.message);
        return data;
      }
      const request = input.action === "list_applications"
        ? client.rpc("list_operator_applications_v1", {
          p_limit: input.limit,
          p_offset: input.offset
        })
        : input.action === "get_project_dossier"
        ? client.rpc("get_commercial_project_view_v2", {
          p_project_id: input.project_id
        })
        : input.action === "get_application_detail"
        ? client.rpc("get_operator_application_v1", {
          p_quote_request_id: input.quote_request_id,
          p_application_reference: input.application_reference
        })
        : client.rpc("promote_operator_application_v1", {
          p_idempotency_key: input.idempotency_key,
          p_quote_request_id: input.quote_request_id,
          p_application_reference: input.application_reference
        });
      const { data, error } = await request;
      if (error) throw new Error(error.message);
      return data;
    },
    executeCommand: async (jwt, input)=>{
      const { data, error } = await clientFor(jwt).rpc("execute_commercial_command_v2", {
        p_project_id: input.project_id,
        p_command_type: input.command_type,
        p_expected_state: input.expected_state,
        p_expected_revision: input.expected_revision,
        p_idempotency_key: input.idempotency_key,
        p_payload: input.payload
      });
      if (error) throw new Error(error.message);
      return data;
    }
  });
}));