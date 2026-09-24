import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const workflowUrl = new URL("../.github/workflows/build-website-project-preview.yml", import.meta.url);
const workflow = (await readFile(workflowUrl, "utf8")).replaceAll("\r\n", "\n");

function job(name, nextName) {
  const start = workflow.indexOf(`  ${name}:\n`);
  const end = nextName ? workflow.indexOf(`  ${nextName}:\n`, start + 1) : workflow.length;
  assert.notEqual(start, -1, `missing ${name} job`);
  assert.notEqual(end, -1, `missing ${nextName} job`);
  return workflow.slice(start, end);
}

const fetchJob = job("fetch", "build");
const buildJob = job("build", "upload");
const uploadJob = job("upload");

test("fetch exchanges its own OIDC token and checks out only the exact authorized source", () => {
  assert.match(fetchJob, /permissions:\s*\n\s+id-token: write/);
  assert.match(fetchJob, /ACTIONS_ID_TOKEN_REQUEST_URL/);
  assert.match(fetchJob, /LWS_PREVIEW_SOURCE_TOKEN_ENDPOINT/);
  assert.match(fetchJob, /repository: \$\{\{ github\.event\.inputs\.repository_owner \}\}\/\$\{\{ github\.event\.inputs\.repository_name \}\}/);
  assert.match(fetchJob, /ref: \$\{\{ github\.event\.inputs\.commit_sha \}\}/);
  assert.match(fetchJob, /token: \$\{\{ steps\.source_token\.outputs\.token \}\}/);
  assert.match(fetchJob, /git -C source rev-parse HEAD/);
  assert.match(fetchJob, /rm -rf source\/\.git/);
  assert.doesNotMatch(fetchJob, /NOT_YET_IMPLEMENTED/);
});

test("installation credentials never cross into build or upload jobs", () => {
  assert.match(buildJob, /permissions: \{\}/);
  assert.doesNotMatch(buildJob, /id-token: write/);
  assert.doesNotMatch(buildJob, /source_token|installation.token|GH_TOKEN|GITHUB_TOKEN/i);
  assert.doesNotMatch(uploadJob, /source_token|installation.token|GH_TOKEN|GITHUB_TOKEN/i);
  assert.match(uploadJob, /id-token: write/);
});

test("isolated build uses the non-root owner of the writable source mount", () => {
  assert.match(buildJob, /BUILD_UID="\$\(stat -c '%u' "\$\{\{ github\.workspace \}\}\/source"\)"/);
  assert.match(buildJob, /BUILD_GID="\$\(stat -c '%g' "\$\{\{ github\.workspace \}\}\/source"\)"/);
  assert.match(buildJob, /if \[ -z "\$BUILD_UID" \] \|\| \[ -z "\$BUILD_GID" \] \|\| \[ "\$BUILD_UID" = "0" \] \|\| \[ "\$BUILD_GID" = "0" \]/);
  assert.match(buildJob, /--user "\$\{BUILD_UID\}:\$\{BUILD_GID\}"/);
  assert.doesNotMatch(buildJob, /chmod|chown/);
});

test("workflow remains manual and preserves server-authorized lease and build inputs", () => {
  assert.match(workflow, /on:\s*\n\s+workflow_dispatch:/);
  assert.doesNotMatch(workflow, /\n\s+push:/);
  assert.match(workflow, /lease_id:/);
  assert.match(workflow, /build_id:/);
  assert.match(fetchJob, /LWS_PREVIEW_BUILD_ID: \$\{\{ github\.event\.inputs\.build_id \}\}/);
  assert.match(fetchJob, /LWS_PREVIEW_REPOSITORY_ID: \$\{\{ github\.event\.inputs\.repository_id \}\}/);
});
