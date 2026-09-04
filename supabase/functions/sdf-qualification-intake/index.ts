import { createClient } from "npm:@supabase/supabase-js@2";
import { hashIntakeToken } from "../_shared/security.ts";
import {
  getSupabaseServerSecretKey,
  SUPABASE_KEY_BINDING_ERROR,
} from "../_shared/supabase-key-bindings.ts";
import { handleSdfQualificationIntake } from "./handler.ts";

type RuntimeEnvironment = Readonly<{
  get(name: string): string | undefined;
}>;

type RuntimeClient = Readonly<{
  rpc(
    name: string,
    parameters: Record<string, unknown>,
  ): PromiseLike<
    { data: unknown; error: { message?: string; code?: string } | null }
  >;
}>;

type RuntimeClientFactory = (
  url: string,
  key: string,
  options: Readonly<{
    auth: Readonly<{ persistSession: false; autoRefreshToken: false }>;
  }>,
) => RuntimeClient;

function configurationError(code: string): Response {
  return new Response(JSON.stringify({ ok: false, code }), {
    status: 500,
    headers: {
      "content-type": "application/json",
      "cache-control": "no-store",
    },
  });
}

export function createSdfQualificationIntakeRuntime(
  environment: RuntimeEnvironment = Deno.env,
  clientFactory: RuntimeClientFactory = (url, key, options) =>
    createClient(url, key, options),
  hashCapability: (rawToken: string) => Promise<string> = hashIntakeToken,
): (request: Request) => Promise<Response> {
  const url = environment.get("SUPABASE_URL") || "";
  let key: string;
  try {
    key = getSupabaseServerSecretKey("default", environment);
  } catch {
    return async () => configurationError(SUPABASE_KEY_BINDING_ERROR);
  }

  if (!url) return async () => configurationError("SERVER_CONFIGURATION_ERROR");

  const client = clientFactory(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return (request) =>
    handleSdfQualificationIntake(request, {
      hashCapability,
      rpc: async (name, parameters) => await client.rpc(name, parameters),
    });
}

if (import.meta.main) Deno.serve(createSdfQualificationIntakeRuntime());
