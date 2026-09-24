import { createClient } from "npm:@supabase/supabase-js@2";
import {
  getSupabaseServerSecretKey,
  type SupabaseKeyBindingEnvironment,
} from "../_shared/supabase-key-bindings.ts";
import { handleWebsiteProjectPreviewHost } from "./handler.ts";

const BUCKET = "website-project-previews";

export function createWebsiteProjectPreviewHostRuntime(
  environment: SupabaseKeyBindingEnvironment = Deno.env,
) {
  const url = environment.get("SUPABASE_URL") ?? "";
  const originToken = environment.get("LWS_PREVIEW_ORIGIN_TOKEN") ?? "";
  if (!url || !originToken) throw new Error("SERVER_CONFIGURATION_ERROR");
  const client = createClient(
    url,
    getSupabaseServerSecretKey("default", environment),
    {
      auth: { persistSession: false, autoRefreshToken: false },
    },
  );
  const rpc = async <T>(
    name: string,
    args: Record<string, unknown>,
  ): Promise<T> => {
    const { data, error } = await client.rpc(name, args);
    if (error || !data) throw new Error(error?.message || "RPC_FAILED");
    return data as T;
  };
  return Object.freeze({
    originToken,
    randomBytes: () => crypto.getRandomValues(new Uint8Array(32)),
    consumeHandoff: (
      input: Readonly<
        { handoffTokenHash: string; viewerSessionTokenHash: string }
      >,
    ) =>
      rpc<Readonly<{ expiresAt: string }>>(
        "consume_website_project_preview_handoff_v1",
        {
          p_handoff_token_hash: input.handoffTokenHash,
          p_viewer_session_token_hash: input.viewerSessionTokenHash,
        },
      ),
    resolveSession: (viewerSessionTokenHash: string) =>
      rpc<
        Readonly<{
          previewBuildId: string;
          storageBuildId: string;
          artifacts: readonly Readonly<{
            relativePath: string;
            contentType: string;
            sha256: string;
            bytes: number;
          }>[];
        }>
      >("resolve_website_project_preview_session_v1", {
        p_session_token_hash: viewerSessionTokenHash,
      }),
    download: async (objectPath: string) => {
      const { data, error } = await client.storage.from(BUCKET).download(
        objectPath,
      );
      if (error || !data) {
        throw new Error(error?.message || "PREVIEW_ASSET_NOT_FOUND");
      }
      return new Uint8Array(await data.arrayBuffer());
    },
  });
}

if (import.meta.main) {
  const service = createWebsiteProjectPreviewHostRuntime();
  Deno.serve((request) => handleWebsiteProjectPreviewHost(request, service));
}
