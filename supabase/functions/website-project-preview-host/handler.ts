import { normalizeWebsiteProjectPreviewAssetPath } from "../_shared/website-project-preview-local-hosting-gateway.ts";

const COOKIE_NAME = "lws_preview_session";

type PreviewArtifact = Readonly<{
  relativePath: string;
  contentType: string;
  sha256: string;
  bytes: number;
}>;

export type WebsiteProjectPreviewHostService = Readonly<{
  originToken: string;
  randomBytes(): Uint8Array;
  consumeHandoff(
    input: Readonly<{
      handoffTokenHash: string;
      viewerSessionTokenHash: string;
    }>,
  ): PromiseLike<Readonly<{ expiresAt: string }>>;
  resolveSession(viewerSessionTokenHash: string): PromiseLike<
    Readonly<{
      previewBuildId: string;
      storageBuildId: string;
      artifacts: readonly PreviewArtifact[];
    }>
  >;
  download(objectPath: string): PromiseLike<Uint8Array>;
}>;

function text(status: number, code: string): Response {
  return new Response(code, {
    status,
    headers: { "cache-control": "private, no-store" },
  });
}

function toHex(bytes: Uint8Array): string {
  return [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function sha256(value: string): Promise<string> {
  return toHex(
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)),
    ),
  );
}

function cookieToken(request: Request): string {
  const cookies = request.headers.get("cookie") ?? "";
  return /(?:^|;\s*)lws_preview_session=([A-Za-z0-9_-]{32,256})(?:;|$)/.exec(
    cookies,
  )?.[1] ?? "";
}

export async function handleWebsiteProjectPreviewHost(
  request: Request,
  service: WebsiteProjectPreviewHostService,
): Promise<Response> {
  if (
    request.headers.get("x-lws-preview-origin-token") !== service.originToken ||
    !service.originToken
  ) {
    return text(403, "PREVIEW_ORIGIN_FORBIDDEN");
  }
  if (request.method !== "GET" && request.method !== "HEAD") {
    return text(405, "METHOD_NOT_ALLOWED");
  }

  const forwardedPath = request.headers.get("x-lws-preview-path");
  let url: URL;
  try {
    url = new URL(
      forwardedPath || new URL(request.url).pathname,
      "https://preview.lorenzowebsolutions.be",
    );
  } catch {
    return text(400, "PREVIEW_ASSET_PATH_INVALID");
  }
  if (url.origin !== "https://preview.lorenzowebsolutions.be") {
    return text(400, "PREVIEW_ASSET_PATH_INVALID");
  }
  if (url.pathname === "/handoff") {
    const handoffToken = url.searchParams.get("token") ?? "";
    if (!handoffToken) return text(403, "PREVIEW_HANDOFF_INVALID");
    const viewerToken = toHex(service.randomBytes());
    try {
      await service.consumeHandoff({
        handoffTokenHash: await sha256(handoffToken),
        viewerSessionTokenHash: await sha256(viewerToken),
      });
    } catch {
      return text(403, "PREVIEW_HANDOFF_INVALID");
    }
    return new Response(null, {
      status: 302,
      headers: {
        location: "/",
        "cache-control": "private, no-store",
        "set-cookie":
          `${COOKIE_NAME}=${viewerToken}; HttpOnly; Secure; SameSite=Lax; Path=/`,
      },
    });
  }

  const viewerToken = cookieToken(request);
  if (!viewerToken) return text(401, "PREVIEW_SESSION_REQUIRED");
  let session: Awaited<
    ReturnType<WebsiteProjectPreviewHostService["resolveSession"]>
  >;
  try {
    session = await service.resolveSession(await sha256(viewerToken));
  } catch {
    return text(401, "PREVIEW_SESSION_INVALID");
  }
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(
      session.storageBuildId,
    )
  ) {
    return text(401, "PREVIEW_SESSION_INVALID");
  }
  const relativePath = normalizeWebsiteProjectPreviewAssetPath(url.pathname);
  if (!relativePath) return text(400, "PREVIEW_ASSET_PATH_INVALID");
  const artifact = session.artifacts.find((candidate) =>
    candidate.relativePath === relativePath
  );
  if (!artifact) return text(404, "PREVIEW_ASSET_NOT_FOUND");
  try {
    const bytes = await service.download(
      `${session.storageBuildId}/${artifact.relativePath}`,
    );
    return new Response(
      request.method === "HEAD" ? null : Uint8Array.from(bytes).buffer,
      {
        status: 200,
        headers: {
          "cache-control": "private, no-store",
          "x-content-type-options": "nosniff",
          "x-lws-preview-content-type": artifact.contentType,
        },
      },
    );
  } catch {
    return text(404, "PREVIEW_ASSET_NOT_FOUND");
  }
}
