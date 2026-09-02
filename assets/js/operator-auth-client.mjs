import { OPERATOR_ROUTES, validatePublicConfig } from "./operator-auth-core.mjs?v=20260902-login-stability";

let clientPromise;

async function loadConfig() {
  const response = await fetch("/assets/config/operator-auth.json", {
    cache: "no-store",
    credentials: "same-origin",
    headers: { Accept: "application/json" },
  });
  if (!response.ok) throw new Error("AUTH_CONFIG_INVALID");
  return validatePublicConfig(await response.json(), window.location.origin);
}

export function getOperatorClient() {
  if (!clientPromise) {
    clientPromise = loadConfig().then((config) => {
      if (!window.supabase?.createClient) throw new Error("AUTH_CONFIG_INVALID");
      const client = window.supabase.createClient(config.supabaseUrl, config.publishableKey, {
        auth: {
          autoRefreshToken: true,
          detectSessionInUrl: window.location.pathname === OPERATOR_ROUTES.callback,
          flowType: "pkce",
          persistSession: true,
        },
      });
      return { client, config };
    });
  }
  return clientPromise;
}
