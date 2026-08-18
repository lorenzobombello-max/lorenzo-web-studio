export const OPERATOR_ROUTES = Object.freeze({
  login: "/operator/login/",
  callback: "/operator/auth/callback/",
  home: "/operator/",
  dashboard: "/operator/dashboard/",
});

const OPERATOR_AUTHORIZATION_PROBE_PROJECT_ID = "00000000-0000-0000-0000-000000000000";

const AUTH_PARAMETER_NAMES = new Set([
  "access_token",
  "refresh_token",
  "code",
  "token_type",
  "expires_in",
  "expires_at",
  "provider_token",
  "provider_refresh_token",
  "type",
  "error",
  "error_code",
  "error_description",
]);

export function validatePublicConfig(config, origin = "https://lorenzowebsolutions.be") {
  if (!config || typeof config !== "object") throw new Error("AUTH_CONFIG_INVALID");
  const supabaseUrl = new URL(String(config.supabaseUrl || ""));
  const callbackUrl = new URL(String(config.callbackUrl || ""));
  const publishableKey = String(config.publishableKey || "");

  if (supabaseUrl.protocol !== "https:" || supabaseUrl.hostname !== "xcsptvntvrizwhskaphr.supabase.co") {
    throw new Error("AUTH_CONFIG_INVALID");
  }
  if (callbackUrl.origin !== origin || callbackUrl.pathname !== OPERATOR_ROUTES.callback) {
    throw new Error("AUTH_CONFIG_INVALID");
  }
  if (!publishableKey || /service_role|secret/i.test(publishableKey)) {
    throw new Error("AUTH_CONFIG_INVALID");
  }

  return Object.freeze({ supabaseUrl: supabaseUrl.origin, publishableKey, callbackUrl: callbackUrl.href });
}

export function buildMagicLinkRequest(email, callbackUrl) {
  const normalizedEmail = String(email || "").trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalizedEmail)) throw new Error("EMAIL_INVALID");
  return {
    email: normalizedEmail,
    options: { emailRedirectTo: callbackUrl, shouldCreateUser: false },
  };
}

export function hasAuthCallbackMaterial(urlLike) {
  const url = new URL(urlLike, "https://lorenzowebsolutions.be");
  const hash = new URLSearchParams(url.hash.replace(/^#/, ""));
  return [...url.searchParams.keys(), ...hash.keys()].some((key) => AUTH_PARAMETER_NAMES.has(key));
}

export function scrubAuthUrl(locationLike, historyLike) {
  const cleanPath = locationLike.pathname || OPERATOR_ROUTES.callback;
  historyLike.replaceState(historyLike.state ?? null, "", cleanPath);
  return cleanPath;
}

export function isUsableSession(session, nowSeconds = Math.floor(Date.now() / 1000)) {
  return Boolean(
    session &&
    typeof session.access_token === "string" &&
    session.access_token.length > 0 &&
    session.user &&
    typeof session.user.id === "string" &&
    Number(session.expires_at) > nowSeconds + 15
  );
}

export async function resolveAuthCallback(client, environment) {
  const hadCallbackMaterial = hasAuthCallbackMaterial(environment.location.href);
  try {
    const { data, error } = await client.auth.getSession();
    if (error) return { ok: false, code: "SESSION_ESTABLISHMENT_FAILED" };
    if (!hadCallbackMaterial || !isUsableSession(data.session, environment.nowSeconds?.())) {
      return { ok: false, code: "SESSION_NOT_AVAILABLE" };
    }
    return { ok: true, code: "SESSION_ESTABLISHED", session: data.session };
  } finally {
    scrubAuthUrl(environment.location, environment.history);
  }
}

export async function requireOperatorSession(client, nowSeconds) {
  const { data, error } = await client.auth.getSession();
  if (error || !isUsableSession(data.session, nowSeconds)) return null;
  return data.session;
}

export async function requireAuthorizedOperator(client, nowSeconds) {
  const session = await requireOperatorSession(client, nowSeconds);
  if (!session) return { status: "unauthenticated", session: null };
  const { error } = await client.rpc("get_commercial_project_view_v2", {
    p_project_id: OPERATOR_AUTHORIZATION_PROBE_PROJECT_ID,
  });
  if (!error || (error.code === "23503" && error.message === "PROJECT_NOT_FOUND")) {
    return { status: "authorized", session };
  }
  return { status: "unauthorized", session: null };
}

export function watchOperatorSession(client, onSession, onSignedOut) {
  const { data } = client.auth.onAuthStateChange((event, session) => {
    if (event === "SIGNED_OUT" || !session) onSignedOut();
    else if (isUsableSession(session)) onSession(session);
  });
  return () => data.subscription.unsubscribe();
}

export async function signOutOperator(client) {
  const { error } = await client.auth.signOut({ scope: "local" });
  if (error) throw new Error("SIGN_OUT_FAILED");
}

export async function callCommercialOperator(client, functionsBaseUrl, input, fetchImpl = fetch) {
  const session = await requireOperatorSession(client);
  if (!session) throw new Error("AUTHENTICATION_REQUIRED");
  const response = await fetchImpl(`${functionsBaseUrl.replace(/\/$/, "")}/commercial-operator-command`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${session.access_token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(input),
  });
  return { status: response.status, body: await response.json() };
}

export function safeAuthMessage(code) {
  const messages = {
    AUTH_CONFIG_INVALID: "De aanmeldconfiguratie is niet beschikbaar.",
    EMAIL_INVALID: "Vul een geldig e-mailadres in.",
    SESSION_ESTABLISHMENT_FAILED: "De beveiligde sessie kon niet worden gestart.",
    SESSION_NOT_AVAILABLE: "De aanmeldlink is ongeldig of verlopen.",
    SIGN_OUT_FAILED: "Afmelden is niet gelukt. Probeer opnieuw.",
  };
  return messages[code] || "De beveiligde aanmelding kon niet worden voltooid.";
}
