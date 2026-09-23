const { spawn, spawnSync } = require("node:child_process");

const container = "supabase_db_xcsptvntvrizwhskaphr";
const baseArgs = ["exec", "-i", container, "psql", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-At"];
const tokenHash = "1".repeat(64);
const leaseId = "d1000000-0000-4000-8000-000000000001";
const buildId = "d2000000-0000-4000-8000-000000000001";
const commitSha = "a".repeat(40);

function query(sql) {
  const result = spawnSync("docker", [...baseArgs, "-c", sql], { encoding: "utf8" });
  if (result.status !== 0) throw new Error(result.stderr || result.stdout);
  return result.stdout.trim().split(/\r?\n/).filter(Boolean).at(-1) || "";
}

function run(sql) {
  return new Promise((resolve) => {
    const child = spawn("docker", [...baseArgs, "-c", sql]);
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (data) => stdout += data);
    child.stderr.on("data", (data) => stderr += data);
    child.on("exit", (code) => resolve({ code, stdout, stderr }));
  });
}

function consume(repositoryId = "7300000001") {
  return `set role service_role; select set_config('request.jwt.claims','{"role":"service_role"}',false); select public.consume_website_project_preview_artifact_token_v1('${tokenHash}','${leaseId}','${buildId}',${repositoryId},'${commitSha}',9876)::text;`;
}

async function main() {
  query(`delete from lws_internal.website_project_preview_artifact_tokens where token_hash='${tokenHash}'`);
  try {
    query(`
      set session_replication_role=replica;
      insert into lws_internal.website_project_preview_artifact_tokens(
        token_hash, preview_lease_id, build_id, repository_external_id,
        commit_sha, workflow_run_id, expires_at
      ) values ('${tokenHash}','${leaseId}','${buildId}',7300000001,'${commitSha}',9876,clock_timestamp()+interval '5 minutes');
      set session_replication_role=origin;
    `);
    const wrong = await run(consume("7300000002"));
    if (wrong.code === 0 || !/PROJECT_PREVIEW_ARTIFACT_TOKEN_INVALID/.test(wrong.stderr)) {
      throw new Error(`WRONG_REPOSITORY_ACCEPTED:${wrong.stdout}:${wrong.stderr}`);
    }
    const results = await Promise.all([run(consume()), run(consume())]);
    const winners = results.filter((result) => result.code === 0);
    const losers = results.filter((result) => /PROJECT_PREVIEW_ARTIFACT_TOKEN_INVALID/.test(result.stderr));
    if (winners.length !== 1 || losers.length !== 1) {
      throw new Error(`EXPECTED_ONE_TOKEN_WINNER:${JSON.stringify(results)}`);
    }
    query(`update lws_internal.website_project_preview_artifact_tokens set consumed_at=null, expires_at=clock_timestamp()-interval '1 second' where token_hash='${tokenHash}'`);
    const expired = await run(consume());
    if (expired.code === 0 || !/PROJECT_PREVIEW_ARTIFACT_TOKEN_INVALID/.test(expired.stderr)) {
      throw new Error(`EXPIRED_TOKEN_ACCEPTED:${expired.stdout}:${expired.stderr}`);
    }
    console.log("website preview artifact token concurrency: PASS (1 winner, replay/wrong repo/expiry denied)");
  } finally {
    query(`delete from lws_internal.website_project_preview_artifact_tokens where token_hash='${tokenHash}'`);
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});