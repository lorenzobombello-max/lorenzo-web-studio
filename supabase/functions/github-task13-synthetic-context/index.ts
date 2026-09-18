import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders, rejectIfOriginNotAllowed } from "../_shared/cors.ts";
import { handleGitHubTask13SyntheticContext } from "./handler.ts";

const EXPECTED_SUPABASE_URL = "https://xcsptvntvrizwhskaphr.supabase.co";

function withCors(request: Request, response: Response): Response {
  const headers = new Headers(response.headers);
  for (
    const [key, value] of Object.entries(
      corsHeaders(request.headers.get("origin")),
    )
  ) headers.set(key, value);
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
      const publishableKeys = JSON.parse(
        Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") || "null",
      ) as Record<string, unknown> | null;
      const publishableKey = publishableKeys?.default;
      if (
        url !== EXPECTED_SUPABASE_URL || typeof publishableKey !== "string" ||
        !/^sb_publishable_[A-Za-z0-9_-]+$/.test(publishableKey)
      ) throw new Error("SERVER_CONFIGURATION_ERROR");

      const clientFor = (jwt: string) =>
        createClient(url, publishableKey, {
          global: { headers: { Authorization: `Bearer ${jwt}` } },
          auth: { persistSession: false, autoRefreshToken: false },
        });
      const response = await handleGitHubTask13SyntheticContext(request, {
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
            error || !data || typeof data !== "object" ||
            Array.isArray(data) || data.role !== "owner" ||
            data.status !== "ACTIVE"
          ) throw new Error("OWNER_REQUIRED");
        },
        create: async () => {
          const authorization = request.headers.get("authorization") || "";
          const jwt = authorization.replace(/^Bearer\s+/i, "");
          const { data, error } = await clientFor(jwt).rpc(
            "create_task13_synthetic_context_v1",
            {},
          );
          if (error || !data) throw new Error("SYNTHETIC_CONTEXT_FAILED");
          return data;
        },
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
