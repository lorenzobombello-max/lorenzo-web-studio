import { createClient } from "npm:@supabase/supabase-js@2";
import { getSupabaseServerSecretKey } from "../_shared/supabase-key-bindings.ts";
import { sweepPreviewDeadlines } from "../_shared/website-project-preview-cleanup.ts";
import type { PreviewDispatchRpc } from "../_shared/website-project-preview-dispatch.ts";

export function dossier006DeadlineClient(client: PreviewDispatchRpc): PreviewDispatchRpc {
  return {
    rpc(name: string, args: Record<string, unknown>) {
      const scoped = {
        expire_website_project_preview_dispatches_v1: "expire_website_project_preview_dispatches_dossier006_v1",
        get_website_project_preview_cleanup_candidates_v1: "get_website_project_preview_cleanup_candidates_dossier006_v1",
        get_website_project_preview_failed_storage_paths_v1: "get_website_project_preview_failed_storage_paths_dossier006_v1",
        record_website_project_preview_cleanup_checked_v1: "record_website_project_preview_cleanup_checked_dossier006_v1",
      }[name];
      if (!scoped) throw new Error("PROJECT_PREVIEW_CLEANUP_AUTHORITY_INVALID");
      return client.rpc(scoped, args);
    },
  };
}

// Shared by the trusted pg_cron HTTP route and explicit operator CLI invocation.
export async function runPreviewDeadlineSweep() {
  const url = Deno.env.get("SUPABASE_URL");
  if (!url) throw new Error("SERVER_CONFIGURATION_ERROR");
  const client = createClient(url, getSupabaseServerSecretKey("default"), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const scopedClient = dossier006DeadlineClient(client);
  return await sweepPreviewDeadlines(scopedClient, client.storage.from("website-project-previews"));
}
if (import.meta.main) console.log(JSON.stringify(await runPreviewDeadlineSweep()));
