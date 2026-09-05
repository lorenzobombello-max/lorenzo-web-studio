import { assert, assertEquals, assertMatch, assertRejects, assertThrows } from "jsr:@std/assert@1";
import { buildRecruitmentCandidateInvitationEmail } from "../_shared/email-templates.ts";
import {
  createRawRecruitmentCandidateToken,
  decryptRecruitmentCandidateToken,
  encryptRecruitmentCandidateToken,
  hashRecruitmentCandidateToken,
} from "../_shared/security.ts";
import {
  handleRecruitmentCandidateInvitation,
  resolveRecruitmentCandidateInvitationPublishableKey,
  resolveRecruitmentCandidateInvitationServiceKey,
} from "./index.ts";

const serverKey = ["sb", "secret", "recruitmentInvitation", "test"].join("_");
const publishableKey = ["sb", "publishable", "recruitmentInvitation", "test"].join("_");

function environment(values: Record<string, string | undefined>) {
  return { get: (name: string) => values[name] };
}

async function withConfigurationResponse(
  serverBinding: string | undefined,
  publishableBinding: string | undefined,
  legacyServiceBinding: string | undefined = "must-not-be-read",
  legacyAnonBinding: string | undefined = "must-not-be-read",
): Promise<Response> {
  const previousEnvironment = new Map<string, string | undefined>();
  for (const [name, value] of [
    ["SUPABASE_URL", "https://supabase.test"],
    ["SUPABASE_ANON_KEY", legacyAnonBinding],
    ["SUPABASE_SERVICE_ROLE_KEY", legacyServiceBinding],
    ["SUPABASE_SECRET_KEYS", serverBinding],
    ["SUPABASE_PUBLISHABLE_KEYS", publishableBinding],
  ] as const) {
    previousEnvironment.set(name, Deno.env.get(name));
    if (value === undefined) Deno.env.delete(name);
    else Deno.env.set(name, value);
  }

  try {
    return await handleRecruitmentCandidateInvitation(new Request("https://functions.test/recruitment-candidate-invitation", {
      method: "POST",
      headers: { authorization: "Bearer owner-jwt", "content-type": "application/json" },
      body: JSON.stringify({ name: "Sophie", email: "sophie@example.invalid", test_profile: "Development" }),
    }));
  } finally {
    for (const [name, value] of previousEnvironment) {
      if (value === undefined) Deno.env.delete(name);
      else Deno.env.set(name, value);
    }
  }
}

Deno.test("Recruitment invitation uses separate modern service and publishable bindings", async () => {
  assertEquals(
    resolveRecruitmentCandidateInvitationServiceKey(environment({
      SUPABASE_SECRET_KEYS: JSON.stringify({ default: serverKey }),
    })),
    serverKey,
  );

  for (const [serverBinding, legacyServiceBinding] of [
    [undefined, undefined],
    ["not-json", "must-not-be-read"],
    [JSON.stringify({ default: "legacy-service-role-key" }), "must-not-be-read"],
  ] as const) {
    assertEquals(
      resolveRecruitmentCandidateInvitationServiceKey(environment({
        SUPABASE_SERVICE_ROLE_KEY: "must-not-be-read",
        SUPABASE_SECRET_KEYS: serverBinding,
      })),
      null,
    );
    const response = await withConfigurationResponse(
      serverBinding,
      JSON.stringify({ default: publishableKey }),
      legacyServiceBinding,
    );
    assertEquals(response.status, 401);
    assertEquals(await response.json(), { ok: false, code: "RECRUITMENT_OWNER_REQUIRED" });
  }

  const legacyServiceOnlyResponse = await withConfigurationResponse(
    undefined,
    JSON.stringify({ default: publishableKey }),
    "legacy-only-service-key",
  );
  assertEquals(legacyServiceOnlyResponse.status, 401);
  assertEquals(await legacyServiceOnlyResponse.json(), { ok: false, code: "RECRUITMENT_OWNER_REQUIRED" });

  assertEquals(
    resolveRecruitmentCandidateInvitationPublishableKey(environment({
      SUPABASE_PUBLISHABLE_KEYS: JSON.stringify({ default: publishableKey }),
    })),
    publishableKey,
  );

  for (const [publishableBinding, legacyAnonBinding] of [
    [undefined, undefined],
    ["not-json", "must-not-be-read"],
    [JSON.stringify({ default: "legacy-anon-key" }), "must-not-be-read"],
  ] as const) {
    assertEquals(
      resolveRecruitmentCandidateInvitationPublishableKey(environment({
        SUPABASE_ANON_KEY: "must-not-be-read",
        SUPABASE_PUBLISHABLE_KEYS: publishableBinding,
      })),
      null,
    );
    const response = await withConfigurationResponse(
      JSON.stringify({ default: serverKey }),
      publishableBinding,
      "must-not-be-read",
      legacyAnonBinding,
    );
    assertEquals(response.status, 401);
    assertEquals(await response.json(), { ok: false, code: "RECRUITMENT_OWNER_REQUIRED" });
  }

  const legacyAnonOnlyResponse = await withConfigurationResponse(
    JSON.stringify({ default: serverKey }),
    undefined,
    "must-not-be-read",
    "legacy-only-anon-key",
  );
  assertEquals(legacyAnonOnlyResponse.status, 401);
  assertEquals(await legacyAnonOnlyResponse.json(), { ok: false, code: "RECRUITMENT_OWNER_REQUIRED" });

  const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  assert(source.includes('getSupabaseServerSecretKey("default"'));
  assert(!source.includes("SUPABASE_SERVICE_ROLE_KEY"));
  assert(source.includes('getSupabasePublishableKey("default"'));
  assert(!source.includes("SUPABASE_ANON_KEY"));
  assertEquals(source.match(/createClient\(/g)?.length, 2);
  assertEquals(source.match(/auth\.getUser\(jwt\)/g)?.length, 1);
  assertEquals(source.match(/\.rpc\(/g)?.length, 3);
  assertEquals(source.match(/\.from\(/g)?.length ?? 0, 0);
  assertEquals(source.match(/\.storage\./g)?.length ?? 0, 0);
  for (const expectedRpc of [
    "create_recruitment_candidate_invitation_v2",
    "claim_recruitment_candidate_invitation_email_v2",
    "complete_recruitment_candidate_invitation_email_v2",
  ]) assert(source.includes(expectedRpc));
});

Deno.test("Recruitment capability is random, hashed, encrypted, and bound to its digest", async () => {
  const previous = Deno.env.get("APPROVAL_TOKEN_SECRET");
  Deno.env.set("APPROVAL_TOKEN_SECRET", "local-recruitment-test-secret");
  try {
    const first = createRawRecruitmentCandidateToken();
    const second = createRawRecruitmentCandidateToken();
    assertMatch(first, /^[0-9a-f]{64}$/);
    assert(first !== second);
    const digest = await hashRecruitmentCandidateToken(first);
    const encrypted = await encryptRecruitmentCandidateToken(first, digest);
    assertMatch(encrypted, /^v1\.[A-Za-z0-9_-]{16}\.[A-Za-z0-9_-]{107}$/);
    assertEquals(await decryptRecruitmentCandidateToken(encrypted, digest), first);
    await assertRejects(() => decryptRecruitmentCandidateToken(encrypted, "0".repeat(64)));
  } finally {
    if (previous === undefined) Deno.env.delete("APPROVAL_TOKEN_SECRET");
    else Deno.env.set("APPROVAL_TOKEN_SECRET", previous);
  }
});

Deno.test("Recruitment invitation template clearly presents the profile, count, and personal fragment link", () => {
  const token = "a".repeat(64);
  const email = buildRecruitmentCandidateInvitationEmail({
    candidateName: "Sophie Janssens",
    testProfile: "Development",
    selectionCount: 5,
    testUrl: `https://lorenzowebsolutions.be/recruitment/test/#token=${token}`,
  });
  assertMatch(email.subject, /Development/);
  assertMatch(email.html, /Sophie Janssens/);
  assertMatch(email.html, /5 zorgvuldig geselecteerde praktijktests/);
  assertMatch(email.html, /<img src="https:\/\/lorenzowebsolutions\.be\/assets\/images\/branding\/logo\/lorenzo-web-solution-logo-transparent\.png"/);
  assert(!email.html.includes("127.0.0.1"));
  assertMatch(email.html, new RegExp(`#token=${token}`));
  assertMatch(email.text, /Deel deze persoonlijke link niet/);
});

Deno.test("Recruitment invitation rejects non-public candidate links", () => {
  assertThrows(() => buildRecruitmentCandidateInvitationEmail({
    candidateName: "Sophie Janssens",
    testProfile: "Development",
    selectionCount: 4,
    testUrl: `http://127.0.0.1:4173/recruitment/test/#token=${"a".repeat(64)}`,
  }));
});

Deno.test("Recruitment invitation worker fails closed without owner bearer authentication", async () => {
  const response = await handleRecruitmentCandidateInvitation(new Request("https://xcsptvntvrizwhskaphr.supabase.co/functions/v1/recruitment-candidate-invitation", {
    method: "POST",
    headers: { origin: "https://lorenzowebsolutions.be", "content-type": "application/json" },
    body: JSON.stringify({ name: "Sophie", email: "sophie@example.invalid", test_profile: "Development" }),
  }));
  assertEquals(response.status, 401);
  assertEquals((await response.json()).code, "RECRUITMENT_OWNER_REQUIRED");
});

Deno.test("Recruitment invitation worker source never logs or returns raw capability material", async () => {
  const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  assert(!/console\.(?:log|info|warn|error)/.test(source));
  assert(!source.includes('Deno.env.get("SITE_URL")'));
  assert(!/rawToken[^\n]*return json/.test(source));
  assert(!/encryptedToken[^\n]*return json/.test(source));
});
