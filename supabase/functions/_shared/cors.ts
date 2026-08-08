const STRICT_ORIGINS = new Set([
  "https://lorenzowebsolutions.be",
  "https://www.lorenzowebsolutions.be",
  "https://lorenzobombello-max.github.io",
]);

const LOCAL_DEVELOPMENT_ORIGINS = new Set([
  "http://localhost:3000",
  "http://127.0.0.1:3000",
]);

function configuredOrigins(): Set<string> {
  const origins = new Set(STRICT_ORIGINS);
  const configured = Deno.env.get("ALLOWED_ORIGINS") || "";

  configured.split(",").forEach((value) => {
    const candidate = value.trim();
    if (!candidate) return;

    try {
      const parsed = new URL(candidate);
      if (parsed.origin === candidate) origins.add(candidate);
    } catch {
      // Invalid configured origins are ignored instead of weakening CORS.
    }
  });

  if (Deno.env.get("ALLOW_LOCAL_DEVELOPMENT_ORIGINS") === "true") {
    LOCAL_DEVELOPMENT_ORIGINS.forEach((origin) => origins.add(origin));
  }
  return origins;
}

export function isAllowedOrigin(origin: string | null): boolean {
  if (!origin) return true;

  try {
    const parsed = new URL(origin);
    return parsed.origin === origin && configuredOrigins().has(origin);
  } catch {
    return false;
  }
}

export function corsHeaders(origin: string | null): HeadersInit {
  const siteUrl = Deno.env.get("SITE_URL") || "https://lorenzowebsolutions.be";
  const allowOrigin = origin && isAllowedOrigin(origin) ? origin : siteUrl;

  return {
    "Access-Control-Allow-Origin": allowOrigin,
    "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
    "Access-Control-Allow-Headers": "authorization,content-type,idempotency-key,x-requested-with",
    "Vary": "Origin",
  };
}

export function rejectIfOriginNotAllowed(req: Request): Response | null {
  const origin = req.headers.get("origin");
  if (isAllowedOrigin(origin)) return null;

  return new Response(JSON.stringify({
    ok: false,
    message: "Origin not allowed.",
  }), {
    status: 403,
    headers: {
      ...corsHeaders(origin),
      "Content-Type": "application/json",
    },
  });
}
