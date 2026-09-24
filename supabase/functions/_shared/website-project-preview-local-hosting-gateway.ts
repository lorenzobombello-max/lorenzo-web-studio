// A concrete, LOCAL-ONLY implementation of WebsiteProjectPreviewHostingGateway
// (website-project-preview-hosting-gateway.ts), used exclusively for local
// development/testing. This is NOT the production hosting mechanism -
// checkpoint 009-git001c-astro-preview-build-plan.md §8/§16.6 item U1
// (the Cloudflare-vs-path-rewriting decision) remains open and unrelated
// to this file. This module exists so the async build pipeline has a
// real, runnable serving target to prove HTML/CSS/image delivery and the
// host->session->build access-control chain end to end, entirely on
// localhost, without any external DNS/TLS/CDN dependency.
//
// Implements checkpoint §14.2's access model precisely:
//   - a single-use handoff URL/token (via
//     website-project-preview-single-use-token.ts) exchanged exactly once
//     for a host-only session cookie;
//   - the session cookie is `HttpOnly; Secure; SameSite=Lax; Path=/`
//     with no `Domain` attribute (host-only);
//   - every subsequent asset request is resolved purely server-side via
//     session -> build, never trusting a client-supplied path/build
//     identifier;
//   - two different builds' sessions can never cross-resolve to each
//     other's assets.
import {
  createInMemorySingleUseTokenLedger,
  mintWebsiteProjectPreviewSingleUseToken,
  verifyWebsiteProjectPreviewSingleUseToken,
} from "./website-project-preview-single-use-token.ts";
import type {
  WebsiteProjectPreviewHostingGateway,
  WebsiteProjectPreviewHostingSession,
} from "./website-project-preview-hosting-gateway.ts";

const HANDOFF_PURPOSE = "preview-handoff";
const HANDOFF_TTL_SECONDS = 60;
// Checkpoint §14.2: the kijksessie-TTL, independent of the build lease
// and of artifact retention.
const SESSION_TTL_SECONDS = 30 * 60;

type StoredBuild = Readonly<{
  previewBuildId: string;
  actorAuthUserId: string;
  buildStatus: "PASS" | "PASS_WITH_WARNINGS";
  assets: ReadonlyMap<string, Readonly<{ contentType: string; bytes: Uint8Array }>>;
}>;

type StoredSession = { revoked: boolean; expiresAtMs: number; previewBuildId: string };

function toHex(bytes: ArrayBuffer): string {
  return [...new Uint8Array(bytes)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

async function randomSessionToken(): Promise<string> {
  return toHex(crypto.getRandomValues(new Uint8Array(32)).buffer);
}

export function normalizeWebsiteProjectPreviewAssetPath(pathname: string): string | null {
  let decoded: string;
  try {
    decoded = decodeURIComponent(pathname);
  } catch {
    return null;
  }
  if (!decoded.startsWith("/") || decoded.includes("\\") || decoded.includes("\0")
    || /%(?:00|2e|2f|5c)/i.test(decoded)) return null;
  const segments = decoded.split("/");
  if (segments.some((segment) => segment === "." || segment === "..")) return null;
  if (decoded === "/") return "index.html";
  const relativePath = decoded.slice(1);
  return decoded.endsWith("/") ? `${relativePath}index.html` : relativePath;
}

export type LocalWebsiteProjectPreviewHostingGateway =
  & WebsiteProjectPreviewHostingGateway
  & Readonly<{
    // Registers the raw asset bytes for a build (normally supplied by the
    // upload job) - kept separate from `publish()` itself so a caller can
    // upload assets incrementally, matching the real pipeline's per-file
    // upload step, then call `publish()` once with the accepted manifest.
    putAsset(
      input: Readonly<{
        previewBuildId: string;
        relativePath: string;
        contentType: string;
        bytes: Uint8Array;
      }>,
    ): void;
    registerBuild(
      input: Readonly<{ previewBuildId: string; actorAuthUserId: string }>,
    ): void;
    handleRequest(request: Request): Promise<Response>;
    close(): Promise<void>;
    readonly baseUrl: string;
  }>;

export async function createLocalWebsiteProjectPreviewHostingGateway(
  options: Readonly<{ hostname?: string; port?: number }> = {},
): Promise<LocalWebsiteProjectPreviewHostingGateway> {
  const secret = toHex(crypto.getRandomValues(new Uint8Array(32)).buffer);
  const handoffLedger = createInMemorySingleUseTokenLedger();
  const builds = new Map<string, {
    actorAuthUserId: string;
    assets: Map<string, { contentType: string; bytes: Uint8Array }>;
  }>();
  const publishedBuilds = new Map<string, StoredBuild>();
  const sessionsByTokenHash = new Map<string, StoredSession>();

  function ensureBuild(previewBuildId: string) {
    let entry = builds.get(previewBuildId);
    if (!entry) {
      entry = { actorAuthUserId: "", assets: new Map() };
      builds.set(previewBuildId, entry);
    }
    return entry;
  }

  async function handleRequest(request: Request): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/__preview-session") {
      const token = url.searchParams.get("token") ?? "";
      let verification;
      try {
        verification = await verifyWebsiteProjectPreviewSingleUseToken({
          token,
          purpose: HANDOFF_PURPOSE,
          subject: url.searchParams.get("build") ?? "",
          secret,
        });
      } catch {
        return new Response("PREVIEW_HANDOFF_INVALID", { status: 403 });
      }
      if (!handoffLedger.consumeOnce(verification.tokenHash)) {
        return new Response("PREVIEW_HANDOFF_ALREADY_USED", { status: 403 });
      }
      const previewBuildId = url.searchParams.get("build") ?? "";
      if (!publishedBuilds.has(previewBuildId)) {
        return new Response("PREVIEW_BUILD_NOT_FOUND", { status: 404 });
      }
      const sessionToken = await randomSessionToken();
      const sessionTokenHash = toHex(
        await crypto.subtle.digest(
          "SHA-256",
          new TextEncoder().encode(sessionToken),
        ),
      );
      sessionsByTokenHash.set(sessionTokenHash, {
        revoked: false,
        expiresAtMs: Date.now() + SESSION_TTL_SECONDS * 1000,
        previewBuildId,
      });
      return new Response(null, {
        status: 302,
        headers: {
          Location: "/",
          // Host-only (no Domain attribute), SameSite=Lax (not Strict -
          // this response itself is reached via a cross-site top-level
          // navigation from the operator dashboard), HttpOnly+Secure,
          // Path=/ - exactly checkpoint §14.2's corrected cookie design.
          "Set-Cookie":
            `lws_preview_session=${sessionToken}; HttpOnly; Secure; SameSite=Lax; Path=/`,
        },
      });
    }

    const cookieHeader = request.headers.get("cookie") ?? "";
    const match = /(?:^|;\s*)lws_preview_session=([0-9a-f]+)/.exec(cookieHeader);
    if (!match) return new Response("PREVIEW_SESSION_REQUIRED", { status: 401 });
    const sessionTokenHash = toHex(
      await crypto.subtle.digest("SHA-256", new TextEncoder().encode(match[1])),
    );
    const session = sessionsByTokenHash.get(sessionTokenHash);
    if (!session || session.revoked || session.expiresAtMs <= Date.now()) {
      return new Response("PREVIEW_SESSION_INVALID", { status: 401 });
    }
    const build = publishedBuilds.get(session.previewBuildId);
    if (!build) return new Response("PREVIEW_BUILD_NOT_FOUND", { status: 404 });

    const relativePath = normalizeWebsiteProjectPreviewAssetPath(url.pathname);
    if (!relativePath) return new Response("PREVIEW_ASSET_PATH_INVALID", { status: 400 });
    const asset = build.assets.get(relativePath);
    if (!asset) return new Response("PREVIEW_ASSET_NOT_FOUND", { status: 404 });
    return new Response(Uint8Array.from(asset.bytes).buffer, {
      status: 200,
      headers: { "content-type": asset.contentType },
    });
  }

  let server: Deno.HttpServer | null = null;
  let baseUrl = "";
  if (typeof Deno !== "undefined" && typeof Deno.serve === "function") {
    server = Deno.serve(
      { hostname: options.hostname ?? "127.0.0.1", port: options.port ?? 0, onListen: () => {} },
      handleRequest,
    );
    const addr = server.addr as Deno.NetAddr;
    baseUrl = `http://127.0.0.1:${addr.port}`;
  }

  return Object.freeze({
    registerBuild(input: Readonly<{ previewBuildId: string; actorAuthUserId: string }>) {
      const entry = ensureBuild(input.previewBuildId);
      entry.actorAuthUserId = input.actorAuthUserId;
    },
    putAsset(input: Readonly<{
      previewBuildId: string;
      relativePath: string;
      contentType: string;
      bytes: Uint8Array;
    }>) {
      const entry = ensureBuild(input.previewBuildId);
      entry.assets.set(input.relativePath, {
        contentType: input.contentType,
        bytes: input.bytes,
      });
    },
    async publish(input: Readonly<{
      previewBuildId: string;
      actorAuthUserId: string;
      buildStatus: "PASS" | "PASS_WITH_WARNINGS";
    }>): Promise<WebsiteProjectPreviewHostingSession> {
      const entry = ensureBuild(input.previewBuildId);
      publishedBuilds.set(
        input.previewBuildId,
        Object.freeze({
          previewBuildId: input.previewBuildId,
          actorAuthUserId: input.actorAuthUserId,
          buildStatus: input.buildStatus,
          assets: new Map(entry.assets),
        }),
      );
      const handoff = await mintWebsiteProjectPreviewSingleUseToken({
        purpose: HANDOFF_PURPOSE,
        subject: input.previewBuildId,
        ttlSeconds: HANDOFF_TTL_SECONDS,
        secret,
      });
      return Object.freeze({
        handoffUrl:
          `${baseUrl}/__preview-session?build=${input.previewBuildId}&token=${handoff.token}`,
        expiresAt: handoff.expiresAt,
      });
    },
    handleRequest,
    async close() {
      if (server) await server.shutdown();
    },
    get baseUrl() {
      return baseUrl;
    },
  });
}
