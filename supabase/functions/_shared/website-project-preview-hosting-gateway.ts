// Explicit seam between the preview-build pipeline and however previews are
// eventually served to an operator's browser. No concrete implementation of
// this interface exists yet: the hosting route itself (checkpoint
// 009-git001c-astro-preview-build-plan.md §8/§16.6, item U1) is still an
// open, externally-gated decision - a reverse-proxy/CDN layer versus the
// path-rewriting fallback. Nothing in the async build/manifest/status
// contract should call a concrete hosting mechanism directly; it must go
// through this interface, so that decision can be made (and swapped) later
// without touching the build pipeline itself.
import type { WebsiteProjectPreviewArtifactManifest } from "./website-project-preview-artifact-manifest.ts";

export type WebsiteProjectPreviewHostingSession = Readonly<{
  // Opaque, single-use handoff URL handed back to the already-authorized
  // operator caller (checkpoint §14.2 step 1-2). Never a bare, reusable
  // secret - the concrete gateway implementation is responsible for
  // minting a short-lived, single-use token bound to exactly one build.
  handoffUrl: string;
  // Wall-clock expiry of the underlying build/session, whichever is
  // sooner - callers must not assume any specific downstream TTL policy.
  expiresAt: string;
}>;

export type WebsiteProjectPreviewHostingGateway = Readonly<{
  // Registers a successfully finalized build's manifest with whatever
  // hosting mechanism is eventually chosen, and returns a fresh handoff
  // session for the requesting operator. Must never be called for a
  // build whose status is anything other than PASS or PASS_WITH_WARNINGS.
  publish(input: Readonly<{
    previewBuildId: string;
    actorAuthUserId: string;
    manifest: WebsiteProjectPreviewArtifactManifest;
    buildStatus: "PASS" | "PASS_WITH_WARNINGS";
  }>): Promise<WebsiteProjectPreviewHostingSession>;
}>;
