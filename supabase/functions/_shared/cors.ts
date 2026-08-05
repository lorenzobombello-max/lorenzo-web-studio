const STRICT_ORIGINS = new Set([
  "https://lorenzowebsolutions.be",
  "https://www.lorenzowebsolutions.be",
  "https://lorenzobombello-max.github.io",
]);

function isLocalOrigin(origin: string): boolean {
  return origin.startsWith("http://localhost") || origin.startsWith("http://127.0.0.1");
}

export function isAllowedOrigin(origin: string | null): boolean {
  if (!origin) return true;
  return STRICT_ORIGINS.has(origin) || isLocalOrigin(origin);
}

export function corsHeaders(origin: string | null): HeadersInit {
  const siteUrl = Deno.env.get("SITE_URL") || "https://lorenzowebsolutions.be";
  const allowOrigin = origin && isAllowedOrigin(origin) ? origin : siteUrl;

  return {
    "Access-Control-Allow-Origin": allowOrigin,
    "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
    "Access-Control-Allow-Headers": "content-type,x-requested-with",
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
