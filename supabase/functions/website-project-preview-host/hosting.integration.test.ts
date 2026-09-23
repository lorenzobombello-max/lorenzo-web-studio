import { assertEquals } from "jsr:@std/assert@1";
import { createClient } from "npm:@supabase/supabase-js@2";
import { handlePagesPreviewRequest } from "../../../cloudflare/website-project-preview-host/functions/[[path]].ts";
import { createWebsiteProjectPreviewHostRuntime } from "./index.ts";
import { handleWebsiteProjectPreviewHost } from "./handler.ts";

const decoder = new TextDecoder();
const encoder = new TextEncoder();

async function command(name: string, args: string[]): Promise<string> {
  const result = await new Deno.Command(name, { args, stdout: "piped", stderr: "piped" }).output();
  if (!result.success) throw new Error(decoder.decode(result.stderr) || `${name} failed`);
  return decoder.decode(result.stdout).trim();
}

async function sha256(value: string): Promise<string> {
  const bytes = new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(value)));
  return [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

Deno.test("Pages and Supabase origin serve one existing private build through rotated session", async () => {
  const npx = Deno.build.os === "windows" ? "npx.cmd" : "npx";
  const local = Object.fromEntries((await command(npx, ["supabase", "status", "-o", "env"]))
    .split(/\r?\n/).flatMap((line) => {
      const match = /^([A-Z_]+)="?(.*?)"?$/.exec(line);
      return match ? [[match[1], match[2]]] : [];
    }));
  const sessionId = crypto.randomUUID();
  const handoffToken = [...crypto.getRandomValues(new Uint8Array(32))]
    .map((byte) => byte.toString(16).padStart(2, "0")).join("");
  const handoffHash = await sha256(handoffToken);
  const insertSql = `with selected as (
    select b.preview_build_id, b.actor_auth_user_id, a.relative_path, a.content_type
    from lws_internal.website_project_preview_builds b
    join lws_internal.website_project_preview_build_artifacts a using (preview_build_id)
    where b.build_status in ('PASS','PASS_WITH_WARNINGS')
    order by b.built_at desc, a.relative_path limit 1
  ), inserted as (
    insert into lws_internal.website_project_preview_sessions
      (preview_session_id, preview_build_id, session_token_hash, actor_auth_user_id, expires_at)
    select '${sessionId}', preview_build_id, '${handoffHash}', actor_auth_user_id, clock_timestamp() + interval '30 minutes'
    from selected returning preview_build_id
  ) select selected.preview_build_id || '|' || selected.relative_path || '|' || selected.content_type
    from selected join inserted using (preview_build_id);`;
  const fixture = await command("docker", ["exec", "supabase_db_xcsptvntvrizwhskaphr", "psql", "-U", "postgres", "-d", "postgres", "-Atc", insertSql]);
  const [previewBuildId, relativePath, contentType] = fixture.split("|");
  if (!relativePath || !contentType) throw new Error("LOCAL_PREVIEW_FIXTURE_MISSING");
  const storage = createClient(local.API_URL, local.SECRET_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  }).storage.from("website-project-previews");
  const objectPath = `${previewBuildId}/${relativePath}`;

  try {
    const uploaded = await storage.upload(objectPath, encoder.encode("GIT-001C hosting integration"), {
      contentType: contentType.split(";", 1)[0],
      upsert: false,
    });
    if (uploaded.error) throw new Error(uploaded.error.message);

    const environment = new Map([
      ["SUPABASE_URL", local.API_URL],
      ["SUPABASE_SECRET_KEYS", JSON.stringify({ default: local.SECRET_KEY })],
      ["LWS_PREVIEW_ORIGIN_TOKEN", "local-purpose-token"],
    ]);
    const origin = createWebsiteProjectPreviewHostRuntime({ get: (name) => environment.get(name) });
    const pagesEnv = {
      LWS_PREVIEW_ORIGIN_URL: "https://origin.local/functions/v1/website-project-preview-host",
      LWS_PREVIEW_ORIGIN_TOKEN: "local-purpose-token",
    };
    const originFetch = (request: RequestInfo | URL) =>
      handleWebsiteProjectPreviewHost(request instanceof Request ? request : new Request(request), origin);
    const handoffs = await Promise.all([1, 2].map(() => handlePagesPreviewRequest(
      new Request(`https://preview.lorenzowebsolutions.be/handoff?token=${handoffToken}`),
      pagesEnv,
      originFetch,
    )));
    assertEquals(handoffs.map(({ status }) => status).sort(), [302, 403]);
    const handoff = handoffs.find(({ status }) => status === 302);
    if (!handoff) throw new Error("PREVIEW_HANDOFF_WINNER_MISSING");
    const cookie = handoff.headers.get("set-cookie")?.split(";", 1)[0] ?? "";
    const asset = await handlePagesPreviewRequest(
      new Request(`https://preview.lorenzowebsolutions.be/${relativePath}`, { headers: { cookie } }),
      pagesEnv,
      originFetch,
    );
    assertEquals(asset.status, 200);
    assertEquals(asset.headers.get("content-type"), contentType);
    assertEquals((await asset.arrayBuffer()).byteLength > 0, true);
  } finally {
    await storage.remove([objectPath]);
    await command("docker", ["exec", "supabase_db_xcsptvntvrizwhskaphr", "psql", "-U", "postgres", "-d", "postgres", "-c", `delete from lws_internal.website_project_preview_sessions where preview_session_id='${sessionId}';`]);
  }
});
