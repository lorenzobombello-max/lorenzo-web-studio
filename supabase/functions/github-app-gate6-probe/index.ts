import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders, rejectIfOriginNotAllowed } from "../_shared/cors.ts";
import { getSupabasePublishableKey } from "../_shared/supabase-key-bindings.ts";
import { handleGitHubAppGate6Probe } from "./handler.ts";
import { executeGitHubAppGate6Probe } from "./probe.ts";
import { loadGate6ProbeConfig, signGitHubAppJwt } from "./runtime.ts";

function withCors(request: Request, response: Response): Response {
  const headers = new Headers(response.headers);
  for (
    const [key, value] of Object.entries(
      corsHeaders(request.headers.get("origin")),
    )
  ) {
    headers.set(key, value);
  }
  return new Response(response.body, { status: response.status, headers });
}

if (import.meta.main) {
  Deno.serve(async (request) => {
    const originRejection = rejectIfOriginNotAllowed(request);
    if (originRejection) return originRejection;
    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: corsHeaders(request.headers.get("origin")),
      });
    }
    try {
      const url = Deno.env.get("SUPABASE_URL");
      if (!url) throw new Error("SERVER_CONFIGURATION_ERROR");
      const publishableKey = getSupabasePublishableKey("default");
      const clientFor = (jwt: string) =>
        createClient(url, publishableKey, {
          global: { headers: { Authorization: `Bearer ${jwt}` } },
          auth: { persistSession: false, autoRefreshToken: false },
        });
      const config = loadGate6ProbeConfig();
      const response = await handleGitHubAppGate6Probe(request, {
        now: Date.now,
        verifyUser: async (jwt) => {
          const { data, error } = await clientFor(jwt).auth.getUser(jwt);
          return error || !data.user ? null : { id: data.user.id };
        },
        authorizeOwner: async (jwt) => {
          const { data, error } = await clientFor(jwt).rpc(
            "get_current_operator_identity_v1",
            {},
          );
          if (
            error || !data || typeof data !== "object" || Array.isArray(data) ||
            Object.keys(data).length !== 3 || data.role !== "owner" ||
            data.status !== "ACTIVE" || typeof data.display_name !== "string" ||
            !data.display_name
          ) throw new Error("OWNER_REQUIRED");
        },
        executeProbe: () =>
          executeGitHubAppGate6Probe({
            ...config,
            signAppJwt: (privateKey, appId) =>
              signGitHubAppJwt(privateKey, appId),
            fetch,
          }),
      });
      return withCors(request, response);
    } catch {
      return withCors(
        request,
        Response.json(
          { ok: false, code: "SERVER_CONFIGURATION_ERROR" },
          { status: 500, headers: { "Cache-Control": "no-store" } },
        ),
      );
    }
  });
}
