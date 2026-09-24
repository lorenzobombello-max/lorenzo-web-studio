import { assertEquals } from "jsr:@std/assert@1";
import { createClient } from "npm:@supabase/supabase-js@2";
import { handlePagesPreviewRequest } from "../../../cloudflare/website-project-preview-host/functions/[[path]].ts";
import { createWebsiteProjectPreviewHostRuntime } from "./index.ts";
import { handleWebsiteProjectPreviewHost } from "./handler.ts";

const decoder = new TextDecoder();
const encoder = new TextEncoder();
const actorAuthUserId = "c9bcd3ef-1e7e-4889-8a12-db827f1b97b0";
const commitSha = "1f19bf01c61c6da79fa4c7374333a91b70f9bf48";
const workflowRunId = 998878;

async function command(name: string, args: string[]): Promise<string> {
  const result = await new Deno.Command(name, {
    args,
    stdout: "piped",
    stderr: "piped",
  }).output();
  if (!result.success) {
    throw new Error(decoder.decode(result.stderr) || `${name} failed`);
  }
  return decoder.decode(result.stdout).trim();
}

async function sha256(value: string): Promise<string> {
  const bytes = new Uint8Array(
    await crypto.subtle.digest("SHA-256", encoder.encode(value)),
  );
  return [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function literal(value: unknown): string {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function service(sql: string): string {
  return `set role service_role; select set_config('request.jwt.claims','{"role":"service_role"}',false); ${sql}`;
}

Deno.test("finalized preview serves only its authorized storage prefix after lease release", async () => {
  const npx = Deno.build.os === "windows" ? "npx.cmd" : "npx";
  const local = Object.fromEntries(
    (await command(npx, ["supabase", "status", "-o", "env"]))
      .split(/\r?\n/).flatMap((line) => {
        const match = /^([A-Z_]+)="?(.*?)"?$/.exec(line);
        return match ? [[match[1], match[2]]] : [];
      }),
  );
  const repositoryId = 7_500_000_000 +
    crypto.getRandomValues(new Uint32Array(1))[0] % 100_000_000;
  const repositoryName = `preview-host-chain-${
    crypto.randomUUID().slice(0, 8)
  }`;
  const idempotencyKey = crypto.randomUUID();
  const receiptHash = await sha256(crypto.randomUUID());
  const uploadSessionHash = await sha256(crypto.randomUUID());
  const handoffToken = [...crypto.getRandomValues(new Uint8Array(32))]
    .map((byte) => byte.toString(16).padStart(2, "0")).join("");
  const handoffHash = await sha256(handoffToken);
  const claims = JSON.stringify({
    sub: actorAuthUserId,
    role: "authenticated",
    aal: "aal2",
  });
  const psql = async (sql: string) =>
    (await command("docker", [
      "exec",
      "supabase_db_xcsptvntvrizwhskaphr",
      "psql",
      "-U",
      "postgres",
      "-d",
      "postgres",
      "-v",
      "ON_ERROR_STOP=1",
      "-qAt",
      "-c",
      sql,
    ])).split(/\r?\n/).filter(Boolean).at(-1) ?? "";
  const authority = JSON.parse(
    await psql(`
    begin;
    select set_config('request.jwt.claims',${literal(claims)},true);
    set local session_replication_role=replica;
    update public.commercial_operators set role='owner',status='ACTIVE',revoked_at=null
      where auth_user_id=${literal(actorAuthUserId)}::uuid;
    set local session_replication_role=origin;
    create temporary table preview_host_chain_fixture as
      select (value->>'website_work_context_id')::uuid website_work_context_id,
             (value->>'workspace_id')::uuid website_workspace_id,
             null::uuid quote_request_id
      from (select public.create_task13_synthetic_context_v1() value) created;
    update preview_host_chain_fixture fixture set quote_request_id=context.quote_request_id
      from public.website_work_contexts context where context.website_work_context_id=fixture.website_work_context_id;
    set local session_replication_role=replica;
    update public.website_execution_workspaces workspace set
      workspace_state='REPOSITORY_READY',repository_owner='lorenzo-web-solutions',repository_name=${
      literal(repositoryName)
    },
      repository_external_id=${repositoryId},repository_node_id=${
      literal(`R_${repositoryName.slice(-8)}`)
    },repository_visibility='private',
      repository_state='BOUND',starter_source='lws-local-fixtures/website-starter',starter_version='1.0.0',
      starter_commit_sha=${
      literal(commitSha)
    },repository_marker_commit_sha=repeat('d',40),repository_bound_at=clock_timestamp(),
      binding_revision=1,default_branch='main',last_commit_sha=${
      literal(commitSha)
    }
    from preview_host_chain_fixture fixture where workspace.website_workspace_id=fixture.website_workspace_id;
    set local session_replication_role=origin;
    select set_config('lws.website_repository_command','on',true);
    insert into public.website_repository_provisioning_operations (
      operation_id,website_workspace_id,website_work_context_id,actor_id,idempotency_key,request_fingerprint,
      repository_owner,repository_name,starter_source,starter_version,starter_commit_sha,state,attempt_count,
      repository_external_id,repository_node_id,claimed_at,updated_at,external_created_at,bound_at)
    select gen_random_uuid(),fixture.website_workspace_id,fixture.website_work_context_id,operator.operator_id,
      gen_random_uuid(),repeat('1',64),'lorenzo-web-solutions',${
      literal(repositoryName)
    },'lorenzo-web-solutions/website-starter',
      '1.0.0',${literal(commitSha)},'BOUND',1,${repositoryId},${
      literal(`R_${repositoryName.slice(-8)}`)
    },clock_timestamp(),
      clock_timestamp(),clock_timestamp(),clock_timestamp()
    from preview_host_chain_fixture fixture
    join public.commercial_operators operator on operator.auth_user_id=${
      literal(actorAuthUserId)
    }::uuid;
    select public.acquire_website_project_preview_build_v1(
      fixture.quote_request_id,${literal(commitSha)},${
      literal(idempotencyKey)
    }::uuid
    )::text from preview_host_chain_fixture fixture;
    commit;`),
  );
  const leaseId = String(authority.leaseId);
  const authorizedBuildId = String(authority.buildId);
  const indexBytes = encoder.encode("<h1>Authorized preview</h1>");
  const nestedBytes = encoder.encode("body{color:#123456}");
  const entries = [
    {
      relativePath: "index.html",
      contentType: "text/html; charset=utf-8",
      bytes: indexBytes,
      sha256: await sha256(decoder.decode(indexBytes)),
    },
    {
      relativePath: "assets/app.css",
      contentType: "text/css; charset=utf-8",
      bytes: nestedBytes,
      sha256: await sha256(decoder.decode(nestedBytes)),
    },
  ];
  const storage = createClient(local.API_URL, local.SECRET_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  }).storage.from("website-project-previews");
  const otherBuildId = crypto.randomUUID();
  let previewBuildId = "";
  let previewSessionId = "";

  try {
    await psql(
      service(`select public.issue_website_project_preview_artifact_token_v1(
      ${literal(receiptHash)},${literal(leaseId)}::uuid,${
        literal(authorizedBuildId)
      }::uuid,
      ${repositoryId},${literal(commitSha)},${workflowRunId},300
    )::text;`),
    );
    await psql(
      service(`select public.open_website_project_preview_upload_session_v1(
      ${literal(receiptHash)},${literal(uploadSessionHash)},${
        literal(leaseId)
      }::uuid,${literal(authorizedBuildId)}::uuid,
      ${repositoryId},${
        literal(commitSha)
      },${workflowRunId},'index.html','PASS',
      ${
        literal(JSON.stringify(entries.map((entry) => ({
          relative_path: entry.relativePath,
          content_type: entry.contentType,
          sha256: entry.sha256,
          bytes: entry.bytes.byteLength,
        }))))
      }::jsonb,600
    )::text;`),
    );
    for (const entry of entries) {
      await psql(
        service(`select public.claim_website_project_preview_upload_file_v1(
        ${literal(uploadSessionHash)},${literal(leaseId)}::uuid,${
          literal(authorizedBuildId)
        }::uuid,
        ${repositoryId},${literal(commitSha)},${workflowRunId},${
          literal(entry.relativePath)
        },
        ${literal(entry.contentType)},${
          literal(entry.sha256)
        },${entry.bytes.byteLength}
      )::text;`),
      );
      const uploaded = await storage.upload(
        `${authorizedBuildId}/${entry.relativePath}`,
        entry.bytes,
        {
          contentType: entry.contentType.split(";", 1)[0],
          upsert: false,
        },
      );
      if (uploaded.error) throw new Error(uploaded.error.message);
      await psql(
        service(`select public.complete_website_project_preview_upload_file_v1(
        ${literal(uploadSessionHash)},${literal(leaseId)}::uuid,${
          literal(authorizedBuildId)
        }::uuid,
        ${repositoryId},${literal(commitSha)},${workflowRunId},${
          literal(entry.relativePath)
        }
      )::text;`),
      );
    }
    const finalized = JSON.parse(
      await psql(
        service(
          `select public.finalize_website_project_preview_upload_session_v1(
      ${literal(uploadSessionHash)},${literal(leaseId)}::uuid,${
            literal(authorizedBuildId)
          }::uuid,
      ${repositoryId},${literal(commitSha)},${workflowRunId}
    )::text;`,
        ),
      ),
    );
    previewBuildId = String(finalized.previewBuildId);
    assertEquals(previewBuildId === authorizedBuildId, false);
    assertEquals(
      await psql(
        `select (released_at is not null)::text from lws_internal.website_project_preview_build_leases where preview_lease_id=${
          literal(leaseId)
        }::uuid;`,
      ),
      "true",
    );
    assertEquals(
      await psql(`select concat(
      has_function_privilege('anon','public.resolve_website_project_preview_session_v1(text)','EXECUTE'), '|',
      has_function_privilege('authenticated','public.resolve_website_project_preview_session_v1(text)','EXECUTE'), '|',
      has_function_privilege('service_role','public.resolve_website_project_preview_session_v1(text)','EXECUTE')
    );`),
      "f|f|t",
    );

    previewSessionId = String(
      JSON.parse(
        await psql(
          `select set_config('request.jwt.claims',${
            literal(claims)
          },false); select public.create_website_project_preview_session_v1(
      ${literal(previewBuildId)}::uuid,${literal(handoffHash)}
    )::text;`,
        ),
      ).previewSessionId,
    );
    for (const entry of entries) {
      const decoy = await storage.upload(
        `${otherBuildId}/${entry.relativePath}`,
        encoder.encode("OTHER BUILD"),
        {
          contentType: entry.contentType.split(";", 1)[0],
          upsert: false,
        },
      );
      if (decoy.error) throw new Error(decoy.error.message);
    }

    const environment = new Map([
      ["SUPABASE_URL", local.API_URL],
      ["SUPABASE_SECRET_KEYS", JSON.stringify({ default: local.SECRET_KEY })],
      ["LWS_PREVIEW_ORIGIN_TOKEN", "local-purpose-token"],
    ]);
    const origin = createWebsiteProjectPreviewHostRuntime({
      get: (name) => environment.get(name),
    });
    const pagesEnv = {
      LWS_PREVIEW_ORIGIN_URL:
        "https://origin.local/functions/v1/website-project-preview-host",
      LWS_PREVIEW_ORIGIN_TOKEN: "local-purpose-token",
    };
    const originFetch = (request: RequestInfo | URL) =>
      handleWebsiteProjectPreviewHost(
        request instanceof Request ? request : new Request(request),
        origin,
      );
    const handoffs = await Promise.all(
      [1, 2].map(() =>
        handlePagesPreviewRequest(
          new Request(
            `https://preview.lorenzowebsolutions.be/handoff?token=${handoffToken}`,
          ),
          pagesEnv,
          originFetch,
        )
      ),
    );
    assertEquals(handoffs.map(({ status }) => status).sort(), [302, 403]);
    const handoff = handoffs.find(({ status }) => status === 302);
    if (!handoff) throw new Error("PREVIEW_HANDOFF_WINNER_MISSING");
    const cookie = handoff.headers.get("set-cookie")?.split(";", 1)[0] ?? "";
    const viewerToken = cookie.split("=", 2)[1] ?? "";
    const resolved = JSON.parse(
      await psql(
        service(`select public.resolve_website_project_preview_session_v1(
      ${literal(await sha256(viewerToken))}
    )::text;`),
      ),
    );
    assertEquals(resolved.previewBuildId, previewBuildId);
    assertEquals(resolved.storageBuildId, authorizedBuildId);
    for (
      const [path, expected, contentType] of [
        ["/", indexBytes, "text/html; charset=utf-8"],
        ["/assets/app.css", nestedBytes, "text/css; charset=utf-8"],
      ] as const
    ) {
      const asset = await handlePagesPreviewRequest(
        new Request(`https://preview.lorenzowebsolutions.be${path}`, {
          headers: { cookie },
        }),
        pagesEnv,
        originFetch,
      );
      assertEquals(asset.status, 200);
      assertEquals(asset.headers.get("content-type"), contentType);
      assertEquals(new Uint8Array(await asset.arrayBuffer()), expected);
    }
    const crossBuild = await handlePagesPreviewRequest(
      new Request(
        `https://preview.lorenzowebsolutions.be/${otherBuildId}/index.html`,
        { headers: { cookie } },
      ),
      pagesEnv,
      originFetch,
    );
    assertEquals(crossBuild.status, 404);
  } finally {
    await storage.remove(entries.flatMap((entry) => [
      `${authorizedBuildId}/${entry.relativePath}`,
      `${otherBuildId}/${entry.relativePath}`,
    ])).catch(() => {});
    if (previewSessionId) {
      await psql(
        `delete from lws_internal.website_project_preview_sessions where preview_session_id=${
          literal(previewSessionId)
        }::uuid;`,
      ).catch(() => {});
    }
  }
});
