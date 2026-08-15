import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  decryptIntakeInvitationToken,
  decryptQuotationDeliveryToken,
  encryptIntakeInvitationToken,
  encryptQuotationDeliveryToken,
  hashApprovalToken,
  hashIntakeToken,
} from "./security.ts";

const secret = "phase32fa-fixed-test-secret-not-production";
const token = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
const accessTokenHash = "a".repeat(64);
const preRemediationEncryptedToken =
  "v1.jiVbJqLtKdTxxXv2.qgCUgzGSkpjEIvPiM-QuyWi0F8Q2fiy6OcJYyz2-wVXyopMRp5zoAL31o2-gqNvGQKZvqHk1191M2yQ";

Deno.test("quotation delivery token encryption is digest-bound", async () => {
  await withApprovalTokenSecret(async () => {
    const digest = "a".repeat(64);
    const encrypted = await encryptQuotationDeliveryToken(token, digest);
    assertEquals(await decryptQuotationDeliveryToken(encrypted, digest), token);
    await assertRejects(() => decryptQuotationDeliveryToken(encrypted, "b".repeat(64)));
  });
});

async function withApprovalTokenSecret(run: () => Promise<void>): Promise<void> {
  const previous = Deno.env.get("APPROVAL_TOKEN_SECRET");
  Deno.env.set("APPROVAL_TOKEN_SECRET", secret);
  try {
    await run();
  } finally {
    if (previous === undefined) Deno.env.delete("APPROVAL_TOKEN_SECRET");
    else Deno.env.set("APPROVAL_TOKEN_SECRET", previous);
  }
}

Deno.test("security HMAC outputs match fixed pre-remediation vectors", async () => {
  await withApprovalTokenSecret(async () => {
    assertEquals(
      await hashApprovalToken(token),
      "ecfe54efab521f40d26a1a6e158ebd6ec2f23b95caf223d3899c87667b24fb57",
    );
    assertEquals(
      await hashIntakeToken(token),
      "1cfab46ab8ff6c8533bcfd5a52e215da62d49abc462e5386043e5bfe92e73324",
    );
  });
});

Deno.test("intake invitation encryption remains compatible and rejects tampering", async () => {
  await withApprovalTokenSecret(async () => {
    assertEquals(
      await decryptIntakeInvitationToken(
        preRemediationEncryptedToken,
        accessTokenHash,
      ),
      token,
    );

    const encryptedToken = await encryptIntakeInvitationToken(
      token,
      accessTokenHash,
    );
    assertEquals(
      await decryptIntakeInvitationToken(encryptedToken, accessTokenHash),
      token,
    );
    await assertRejects(() =>
      decryptIntakeInvitationToken(encryptedToken, "b".repeat(64))
    );

    const parts = encryptedToken.split(".");
    parts[2] = `${parts[2][0] === "A" ? "B" : "A"}${parts[2].slice(1)}`;
    await assertRejects(() =>
      decryptIntakeInvitationToken(parts.join("."), accessTokenHash)
    );
  });
});