import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const contractPath = new URL("../.release/git001c-preview-release.json", import.meta.url);
const runbookPath = new URL("../docs/superpowers/plans/2026-09-23-git001c-production-execution.md", import.meta.url);
const scriptPath = new URL("./invoke-git001c-preview-release.ps1", import.meta.url);
const pagesConfigPaths = [
  new URL("../cloudflare/website-project-preview-host/wrangler.jsonc", import.meta.url),
  new URL("../cloudflare/website-project-preview-host/wrangler.example.jsonc", import.meta.url),
];

const expectedMigrations = [
  "20260922180000",
  "20260923060000",
  "20260923070000",
  "20260923080000",
  "20260923100000",
  "20260923110000",
  "20260923120000",
];

test("GIT-001C release preparation is exact, value-free, and fail-closed", async () => {
  const [contractSource, runbook, script, ...pagesConfigSources] = await Promise.all([
    readFile(contractPath, "utf8"),
    readFile(runbookPath, "utf8"),
    readFile(scriptPath, "utf8"),
    ...pagesConfigPaths.map((path) => readFile(path, "utf8")),
  ]);
  const contract = JSON.parse(contractSource);

  assert.equal(contract.resumeFrom, "b4fc16e2e754a31b111408a8450376332e5f3a90");
  assert.deepEqual(contract.supabase.migrations, expectedMigrations);
  assert.deepEqual(contract.supabase.functions, [
    "website-project-preview-artifact",
    "website-project-preview-source-token",
    "website-project-preview-host",
  ]);
  assert.equal(contract.github.repository, "lorenzobombello-max/lorenzo-web-studio");
  assert.equal(contract.github.repositoryId, "1320223175");
  assert.equal(contract.github.ref, "refs/heads/main");
  assert.equal(
    contract.github.workflowRef,
    "lorenzobombello-max/lorenzo-web-studio/.github/workflows/build-website-project-preview.yml@refs/heads/main",
  );
  assert.deepEqual(contract.github.variables, [
    "LWS_PREVIEW_SOURCE_TOKEN_ENDPOINT",
    "LWS_PREVIEW_ARTIFACT_ENDPOINT",
    "LWS_PREVIEW_OIDC_AUDIENCE",
  ]);
  assert.equal(contract.cloudflare.accountId, "acbc1b86d8c3f0ce809dc4600783a48b");
  assert.equal(contract.cloudflare.projectId, "56ba0651-2499-4b40-b3f7-ad2b690dfa3c");
  assert.equal(contract.cloudflare.projectName, "lws-website-project-preview-host");
  assert.equal(contract.cloudflare.pagesHostname, "lws-website-project-preview-host.pages.dev");
  assert.equal(contract.cloudflare.customHostname, "preview.lorenzowebsolutions.be");
  assert.equal(contract.cloudflare.pagesDevPolicy, "REDIRECT_BEFORE_ORIGIN");
  assert.equal(contract.secretsContainValues, false);

  for (const source of pagesConfigSources) {
    const config = JSON.parse(source);
    assert.equal(config.name, contract.cloudflare.projectName);
    assert.equal(config.pages_build_output_dir, "./public");
    assert.equal(
      config.vars.LWS_PREVIEW_ORIGIN_URL,
      "https://xcsptvntvrizwhskaphr.supabase.co/functions/v1/website-project-preview-host",
    );
    assert.equal(config.secrets, undefined);
    assert.doesNotMatch(source, /LWS_PREVIEW_ORIGIN_TOKEN/);
  }

  assert.match(script, /ValidateSet\("Preflight", "ApplyMigrations"\)/);
  assert.match(script, /if \(\$Phase -eq "ApplyMigrations" -and -not \$Execute\)/);
  assert.match(script, /\[string\]\$ResponsibleOperator/);
  assert.match(script, /\[string\]\$BackupId/);
  assert.match(script, /\[string\]\$BackupCompletedAtUtc/);
  assert.match(script, /ValidateSet\("OFF"\)/);
  assert.match(script, /deployedFunctions/);
  assert.match(script, /pagesDeploymentCount/);
  assert.match(script, /pagesDomains/);
  assert.match(script, /previewDnsStatus/);
  assert.match(script, /PSObject\.Properties\.Name -contains "source"/);
  assert.match(script, /PSObject\.Properties\.Name -contains "Answer"/);
  assert.match(script, /\$previewDnsAnswers = @\(\)\r?\n\s+if/);
  assert.match(script, /\$tokenCandidates\.Count -ne 1/);
  assert.match(script, /Assert-CloudflareResponse/);
  assert.match(script, /Pages deployments/);
  assert.match(script, /Pages domains/);
  assert.match(script, /Worker scripts/);
  assert.match(script, /supabase backups list/);
  assert.match(script, /supabase db push --linked --dry-run/);
  assert.match(script, /supabase db push --linked/);
  assert.doesNotMatch(script, /pages project create/i);

  assert.match(runbook, /wrangler pages deploy/);
  assert.match(runbook, /--project-name lws-website-project-preview-host/);
  assert.match(runbook, /--branch main/);
  assert.doesNotMatch(runbook, /wrangler pages project create/i);
  assert.match(runbook, /PREVIEW_SESSION_REQUIRED/);
  assert.match(runbook, /PREVIEW_ORIGIN_FORBIDDEN/);
});