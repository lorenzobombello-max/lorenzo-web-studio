import { assert, assertEquals, assertMatch, assertRejects, assertThrows } from "jsr:@std/assert@1";
import { buildRecruitmentCandidateInvitationEmail } from "../_shared/email-templates.ts";
import {
  createRawRecruitmentCandidateToken,
  decryptRecruitmentCandidateToken,
  encryptRecruitmentCandidateToken,
  hashRecruitmentCandidateToken,
} from "../_shared/security.ts";
import { handleRecruitmentCandidateInvitation } from "./index.ts";

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
