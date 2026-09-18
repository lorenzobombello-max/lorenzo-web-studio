import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders, rejectIfOriginNotAllowed } from "../_shared/cors.ts";
import { handleGitHubAppGate6Probe } from "./handler.ts";
import { executeGitHubAppGate6Probe } from "./probe.ts";
import {
  createGitHubAppGate6ProbeInput,
  runGate6PreProbePipeline,
} from "./preprobe.ts";
import {
  diagnoseGate6ProbeConfiguration,
  initializeGitHubAppJwtSigner,
  loadGate6ProbeConfig,
  loadGate6ProbePublishableKey,
} from "./runtime.ts";

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
      if (url !== "https://xcsptvntvrizwhskaphr.supabase.co") {
        throw new Error("SERVER_CONFIGURATION_ERROR");
      }
      const publishableKey = loadGate6ProbePublishableKey();
      const clientFor = (jwt: string) =>
        createClient(url, publishableKey, {
          global: { headers: { Authorization: `Bearer ${jwt}` } },
          auth: { persistSession: false, autoRefreshToken: false },
        });
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
        diagnoseConfiguration: async () => {
          const diagnosis = diagnoseGate6ProbeConfiguration();
          return {
            configuration_valid: diagnosis.configuration_valid,
            failed_check: diagnosis.failed_check,
          };
        },
        executeProbe: () => {
          return runGate6PreProbePipeline({
            loadConfiguration: loadGate6ProbeConfig,
            initializeSigner: (config) =>
              initializeGitHubAppJwtSigner(config.privateKey),
            initializeDependencies: (config, signer) =>
              createGitHubAppGate6ProbeInput(
                config,
                (_privateKey, appId) => signer(appId),
                fetch,
              ),
            invokeProbe: executeGitHubAppGate6Probe,
          });
        },
        projectProbeResult: (result) => result,
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
