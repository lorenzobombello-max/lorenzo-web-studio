import { createClient } from "npm:@supabase/supabase-js@2";
import { handleCommercialOperator, withCommercialOperatorCors } from "./handler.ts";
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