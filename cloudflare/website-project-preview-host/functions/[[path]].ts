type PreviewHostEnvironment = Readonly<{
  LWS_PREVIEW_ORIGIN_URL: string;
  LWS_PREVIEW_ORIGIN_TOKEN: string;
}>;

const PUBLIC_HOST = "preview.lorenzowebsolutions.be";

function unavailable(status = 503): Response {
  return new Response("PREVIEW_HOST_UNAVAILABLE", {
    status,
    headers: { "cache-control": "private, no-store" },
  });
}

export async function handlePagesPreviewRequest(
  request: Request,
  environment: PreviewHostEnvironment,
  runtimeFetch: typeof fetch = fetch,
): Promise<Response> {
  const incoming = new URL(request.url);
  if (incoming.hostname !== PUBLIC_HOST) {
    return new Response(null, {
      status: 308,
      headers: {
        "cache-control": "private, no-store",
        location: `https://${PUBLIC_HOST}${incoming.pathname}${incoming.search}`,
      },
    });
  }

  let origin: URL;
  try {
    origin = new URL(environment.LWS_PREVIEW_ORIGIN_URL);
  } catch {
    return unavailable();
  }
  if (origin.protocol !== "https:" || origin.username || origin.password || origin.search || origin.hash
    || !environment.LWS_PREVIEW_ORIGIN_TOKEN) return unavailable();

  const target = new URL(`${origin.pathname.replace(/\/$/, "")}${incoming.pathname}`, origin.origin);
  target.search = incoming.search;
  const headers = new Headers();
  const cookie = request.headers.get("cookie");
  if (cookie) headers.set("cookie", cookie);
  const accept = request.headers.get("accept");
  if (accept) headers.set("accept", accept);
  headers.set("x-lws-preview-origin-token", environment.LWS_PREVIEW_ORIGIN_TOKEN);
  headers.set("x-lws-preview-path", `${incoming.pathname}${incoming.search}`);

  try {
    const originResponse = await runtimeFetch(new Request(target, {
      method: request.method,
      headers,
      redirect: "manual",
    }));
    const responseHeaders = new Headers(originResponse.headers);
    const contentType = responseHeaders.get("x-lws-preview-content-type");
    responseHeaders.delete("x-lws-preview-content-type");
    responseHeaders.delete("x-lws-preview-origin-token");
    if (contentType) responseHeaders.set("content-type", contentType);
    responseHeaders.set("cache-control", "private, no-store");
    return new Response(originResponse.body, {
      status: originResponse.status,
      statusText: originResponse.statusText,
      headers: responseHeaders,
    });
  } catch {
    return unavailable(502);
  }
}

export const onRequest = (context: Readonly<{ request: Request; env: PreviewHostEnvironment }>) =>
  handlePagesPreviewRequest(context.request, context.env);
