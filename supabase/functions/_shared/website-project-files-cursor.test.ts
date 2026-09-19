import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  signWebsiteProjectFilesCursor,
  verifyWebsiteProjectFilesCursor,
  WebsiteProjectFilesCursorError,
} from "./website-project-files-cursor.ts";

const NOW = 1_800_000_000_000;
const SECRET = "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE";
const OTHER_SECRET = "AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI";
const SHA_A = "a".repeat(40);
const SHA_B = "b".repeat(40);

const input = Object.freeze({
  actorAuthUserId: "10000000-0000-4000-8000-000000000001",
  websiteWorkContextId: "10000000-0000-4000-8000-000000000002",
  repositoryExternalId: "7100000001",
  bindingRevision: 7,
  commitSha: SHA_A,
  rootTreeSha: SHA_B,
  directory: "src/components",
  directoryTreeSha: "c".repeat(40),
  offset: 500,
});

function expected(overrides: Record<string, unknown> = {}) {
  return Object.freeze({
    actorAuthUserId: input.actorAuthUserId,
    websiteWorkContextId: input.websiteWorkContextId,
    repositoryExternalId: input.repositoryExternalId,
    bindingRevision: input.bindingRevision,
    commitSha: input.commitSha,
    rootTreeSha: input.rootTreeSha,
    directory: input.directory,
    directoryTreeSha: input.directoryTreeSha,
    offset: input.offset,
    ...overrides,
  });
}

Deno.test("website project files cursor signs and verifies exact canonical five-minute payload", async () => {
  const cursor = await signWebsiteProjectFilesCursor(input, {
    now: NOW,
    secret: SECRET,
  });
  const payload = await verifyWebsiteProjectFilesCursor(
    cursor,
    expected(),
    { now: NOW + 1, secret: SECRET },
  );
  assertEquals(payload, {
    domain: "lws-website-project-files",
    version: 1,
    keyId: "V1",
    ...input,
    issuedAt: NOW,
    expiresAt: NOW + 300_000,
  });
  assertEquals(payload.expiresAt - payload.issuedAt, 300_000);
});

Deno.test("website project files cursor rejects payload and signature tampering", async () => {
  const cursor = await signWebsiteProjectFilesCursor(input, {
    now: NOW,
    secret: SECRET,
  });
  const parts = cursor.split(".");
  const payloadBytes = Uint8Array.from(
    atob(
      parts[1].replaceAll("-", "+").replaceAll("_", "/").padEnd(
        Math.ceil(parts[1].length / 4) * 4,
        "=",
      ),
    ),
    (value) => value.charCodeAt(0),
  );
  const payload = JSON.parse(new TextDecoder().decode(payloadBytes));
  payload.offset = 501;
  const changed = btoa(JSON.stringify(payload)).replaceAll("+", "-")
    .replaceAll("/", "_").replace(/=+$/u, "");
  await assertRejects(
    () =>
      verifyWebsiteProjectFilesCursor(
        `v1.${changed}.${parts[2]}`,
        expected(),
        { now: NOW + 1, secret: SECRET },
      ),
    WebsiteProjectFilesCursorError,
    "PROJECT_FILES_CURSOR_INVALID",
  );
  await assertRejects(
    () =>
      verifyWebsiteProjectFilesCursor(
        `${parts[0]}.${parts[1]}.${parts[2].slice(0, -1)}A`,
        expected(),
        { now: NOW + 1, secret: SECRET },
      ),
    WebsiteProjectFilesCursorError,
    "PROJECT_FILES_CURSOR_INVALID",
  );
});

Deno.test("website project files cursor rejects wrong key, expiry, and future issue", async () => {
  const cursor = await signWebsiteProjectFilesCursor(input, {
    now: NOW,
    secret: SECRET,
  });
  await assertRejects(
    () =>
      verifyWebsiteProjectFilesCursor(cursor, expected(), {
        now: NOW + 1,
        secret: OTHER_SECRET,
      }),
    WebsiteProjectFilesCursorError,
  );
  await assertRejects(
    () =>
      verifyWebsiteProjectFilesCursor(cursor, expected(), {
        now: NOW + 300_000,
        secret: SECRET,
      }),
    WebsiteProjectFilesCursorError,
  );
  await assertRejects(
    () =>
      verifyWebsiteProjectFilesCursor(cursor, expected(), {
        now: NOW - 1,
        secret: SECRET,
      }),
    WebsiteProjectFilesCursorError,
  );
});

Deno.test("website project files cursor rejects every cross-context and snapshot substitution", async () => {
  const cursor = await signWebsiteProjectFilesCursor(input, {
    now: NOW,
    secret: SECRET,
  });
  const substitutions = [
    { actorAuthUserId: "20000000-0000-4000-8000-000000000001" },
    { websiteWorkContextId: "20000000-0000-4000-8000-000000000002" },
    { repositoryExternalId: "7100000002" },
    { bindingRevision: 8 },
    { commitSha: "d".repeat(40) },
    { rootTreeSha: "e".repeat(40) },
    { directory: "src/other" },
    { directoryTreeSha: "f".repeat(40) },
    { offset: 501 },
  ];
  for (const substitution of substitutions) {
    await assertRejects(
      () =>
        verifyWebsiteProjectFilesCursor(cursor, expected(substitution), {
          now: NOW + 1,
          secret: SECRET,
        }),
      WebsiteProjectFilesCursorError,
      "PROJECT_FILES_CURSOR_INVALID",
    );
  }
});

Deno.test("website project files cursor fails closed on missing or malformed signing configuration", async () => {
  const previous = Deno.env.get(
    "LWS_WEBSITE_PROJECT_FILES_CURSOR_SIGNING_KEY_V1",
  );
  Deno.env.delete("LWS_WEBSITE_PROJECT_FILES_CURSOR_SIGNING_KEY_V1");
  try {
    await assertRejects(
      () => signWebsiteProjectFilesCursor(input, { now: NOW }),
      WebsiteProjectFilesCursorError,
      "PROJECT_FILES_CURSOR_CONFIGURATION_ERROR",
    );
    await assertRejects(
      () => signWebsiteProjectFilesCursor(input, { now: NOW, secret: "bad" }),
      WebsiteProjectFilesCursorError,
      "PROJECT_FILES_CURSOR_CONFIGURATION_ERROR",
    );
  } finally {
    if (previous === undefined) {
      Deno.env.delete("LWS_WEBSITE_PROJECT_FILES_CURSOR_SIGNING_KEY_V1");
    } else {
      Deno.env.set(
        "LWS_WEBSITE_PROJECT_FILES_CURSOR_SIGNING_KEY_V1",
        previous,
      );
    }
  }
});
