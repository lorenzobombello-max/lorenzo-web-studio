import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  createInMemorySingleUseTokenLedger,
  mintWebsiteProjectPreviewSingleUseToken,
  verifyWebsiteProjectPreviewSingleUseToken,
  WebsiteProjectPreviewTokenError,
} from "./website-project-preview-single-use-token.ts";

const SECRET = "synthetic-test-secret-never-a-real-credential";

Deno.test("mints a token that verifies successfully for the correct purpose/subject", async () => {
  const minted = await mintWebsiteProjectPreviewSingleUseToken({
    purpose: "artifact-receipt",
    subject: "build-123",
    ttlSeconds: 60,
    secret: SECRET,
  });
  const verified = await verifyWebsiteProjectPreviewSingleUseToken({
    token: minted.token,
    purpose: "artifact-receipt",
    subject: "build-123",
    secret: SECRET,
  });
  assertEquals(verified.tokenHash, minted.tokenHash);
});

Deno.test("rejects a token verified for a different subject (cross-build binding)", async () => {
  const minted = await mintWebsiteProjectPreviewSingleUseToken({
    purpose: "artifact-receipt",
    subject: "build-123",
    ttlSeconds: 60,
    secret: SECRET,
  });
  await assertRejects(
    () =>
      verifyWebsiteProjectPreviewSingleUseToken({
        token: minted.token,
        purpose: "artifact-receipt",
        subject: "build-999",
        secret: SECRET,
      }),
    WebsiteProjectPreviewTokenError,
    "TOKEN_BINDING_MISMATCH",
  );
});

Deno.test("rejects a token verified for a different purpose", async () => {
  const minted = await mintWebsiteProjectPreviewSingleUseToken({
    purpose: "artifact-receipt",
    subject: "build-123",
    ttlSeconds: 60,
    secret: SECRET,
  });
  await assertRejects(
    () =>
      verifyWebsiteProjectPreviewSingleUseToken({
        token: minted.token,
        purpose: "preview-handoff",
        subject: "build-123",
        secret: SECRET,
      }),
    WebsiteProjectPreviewTokenError,
    "TOKEN_BINDING_MISMATCH",
  );
});

Deno.test("rejects a tampered token (invalid signature)", async () => {
  const minted = await mintWebsiteProjectPreviewSingleUseToken({
    purpose: "artifact-receipt",
    subject: "build-123",
    ttlSeconds: 60,
    secret: SECRET,
  });
  const tampered = minted.token.slice(0, -2) + "00";
  await assertRejects(
    () =>
      verifyWebsiteProjectPreviewSingleUseToken({
        token: tampered,
        purpose: "artifact-receipt",
        subject: "build-123",
        secret: SECRET,
      }),
    WebsiteProjectPreviewTokenError,
    "TOKEN_SIGNATURE_INVALID",
  );
});

Deno.test("rejects a token signed with a different secret", async () => {
  const minted = await mintWebsiteProjectPreviewSingleUseToken({
    purpose: "artifact-receipt",
    subject: "build-123",
    ttlSeconds: 60,
    secret: SECRET,
  });
  await assertRejects(
    () =>
      verifyWebsiteProjectPreviewSingleUseToken({
        token: minted.token,
        purpose: "artifact-receipt",
        subject: "build-123",
        secret: "a-completely-different-secret",
      }),
    WebsiteProjectPreviewTokenError,
    "TOKEN_SIGNATURE_INVALID",
  );
});

Deno.test("rejects an expired token", async () => {
  const minted = await mintWebsiteProjectPreviewSingleUseToken({
    purpose: "artifact-receipt",
    subject: "build-123",
    ttlSeconds: 1,
    secret: SECRET,
  });
  await new Promise((resolve) => setTimeout(resolve, 1100));
  await assertRejects(
    () =>
      verifyWebsiteProjectPreviewSingleUseToken({
        token: minted.token,
        purpose: "artifact-receipt",
        subject: "build-123",
        secret: SECRET,
      }),
    WebsiteProjectPreviewTokenError,
    "TOKEN_EXPIRED",
  );
});

Deno.test("in-memory ledger enforces single-use: second consumption of the same hash is rejected", async () => {
  const minted = await mintWebsiteProjectPreviewSingleUseToken({
    purpose: "artifact-receipt",
    subject: "build-123",
    ttlSeconds: 60,
    secret: SECRET,
  });
  const ledger = createInMemorySingleUseTokenLedger();
  assertEquals(ledger.consumeOnce(minted.tokenHash), true);
  assertEquals(ledger.consumeOnce(minted.tokenHash), false);
});

Deno.test("two different minted tokens never collide in the ledger", async () => {
  const first = await mintWebsiteProjectPreviewSingleUseToken({
    purpose: "artifact-receipt",
    subject: "build-a",
    ttlSeconds: 60,
    secret: SECRET,
  });
  const second = await mintWebsiteProjectPreviewSingleUseToken({
    purpose: "artifact-receipt",
    subject: "build-b",
    ttlSeconds: 60,
    secret: SECRET,
  });
  const ledger = createInMemorySingleUseTokenLedger();
  assertEquals(ledger.consumeOnce(first.tokenHash), true);
  assertEquals(ledger.consumeOnce(second.tokenHash), true);
});
