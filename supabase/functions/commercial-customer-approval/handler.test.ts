import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { handleCommercialCustomerApproval } from "./handler.ts";

const PUBLIC_ORIGIN = "https://approval.lorenzowebsolutions.be";
const PROJECT_ID = "ca200000-0000-4000-8000-000000000001";
const ACCESS_TOKEN = "customer-access-token-that-must-not-be-stored";
const SESSION_TOKEN = "0e".repeat(32);

const approvalContext = Object.freeze({
  projectId: PROJECT_ID,
  currentState: "M2_PAYMENT_RECEIVED",
  revision: 8,
  previewAccessId: "ca400000-0000-4000-8000-000000000001",
  previewVersionId: "ca300000-0000-4000-8000-000000000001",
  previewVersionNumber: 3,
  previewContentReference: "TEST_ONLY:current-delivery",
  previewContentSha256: "3".repeat(64),
  statementVersion: "OPL-W-01",
  statementSha256: "57a39bab36303b133c6acb41f857aeb4cad6de25811e127e7444f590fda4697b",
  statementText: "Formele, actieve acceptatie is vereist — er geldt geen stilzwijgende aanvaarding.",
  statementSection: "§4 Aanvaarding",
  sourceFilename: "07_Opleverdocument.docx",
  sourceDriveId: "1dx4vXk6VNbykqY2S2cKmK9TeQBMBfDKP",
  sourceByteLength: 169278,
  approvalReplayAvailable: false,
  approvalExpectedState: "M2_PAYMENT_RECEIVED",
  approvalExpectedRevision: 8,
  sessionExpiresAt: "2026-09-28T12:30:00.000Z",
  deliveryDocument: Object.freeze({
    viewDerivativeId: "ca800000-0000-4000-8000-000000000003",
    documentVersion: 3,
    pdfSha256: "c".repeat(64),
    sourceDocxSha256: "b".repeat(64),
    pdfBytes: 200000,
  }),
  deliveryDocumentViewed: true,
  acceptance: null,
});

const VIEWED = Object.freeze({ viewedDocumentVersion: 3, viewedPdfSha256: "c".repeat(64) });

function approvalRequest(body: unknown, headers: HeadersInit = {}) {
  return new Request(`${PUBLIC_ORIGIN}/approval`, {
    method: "POST",
    headers: {
      origin: PUBLIC_ORIGIN,
      cookie: `__Host-lws_commercial_session=${SESSION_TOKEN}`,
      "content-type": "application/json",
      ...headers,
    },
    body: JSON.stringify(body),
  });
}

function service(overrides: Record<string, unknown> = {}) {
  return {
    publicOrigin: PUBLIC_ORIGIN,
    randomBytes: () => new Uint8Array(32).fill(7),
    redeemAccess: async () => ({
      projectId: PROJECT_ID,
      previewAccessId: "ca400000-0000-4000-8000-000000000001",
      previewVersionId: "ca300000-0000-4000-8000-000000000001",
      expiresAt: "2026-09-28T12:30:00.000Z",
    }),
    resolveContext: async () => approvalContext,
    serveDocument: async () => new Response(new TextEncoder().encode("%PDF-test"), {
      status: 200,
      headers: {
        "cache-control": "private, no-store",
        "content-type": "application/pdf",
      },
    }),
    submitApproval: async () => ({
      projectId: PROJECT_ID,
      resultingState: "FINAL_APPROVAL_RECORDED",
      revision: 9,
      commandType: "submit_customer_approval",
    }),
    ...overrides,
  };
}

function sessionRequest(body: unknown, init: RequestInit = {}) {
  const headers = new Headers(init.headers);
  headers.set("content-type", "application/json");
  if (!headers.has("origin")) headers.set("origin", PUBLIC_ORIGIN);
  return new Request(`${PUBLIC_ORIGIN}/session`, {
    ...init,
    method: init.method ?? "POST",
    headers,
    body: init.method === "GET" ? undefined : JSON.stringify(body),
  });
}

Deno.test("customer access redemption hashes both credentials and sets a host-only session cookie", async () => {
  let received: Record<string, string> | undefined;
  const response = await handleCommercialCustomerApproval(
    sessionRequest({ projectId: PROJECT_ID, accessToken: ACCESS_TOKEN }),
    service({
      redeemAccess: async (input: Record<string, string>) => {
        received = input;
        return {
          projectId: PROJECT_ID,
          previewAccessId: "ca400000-0000-4000-8000-000000000001",
          previewVersionId: "ca300000-0000-4000-8000-000000000001",
          expiresAt: "2026-09-28T12:30:00.000Z",
        };
      },
    }),
  );

  assertEquals(response.status, 204);
  if (!received) throw new Error("redemption RPC was not called");
  assertEquals(received.projectId, PROJECT_ID);
  assertEquals(received.accessTokenDigest.length, 64);
  assertEquals(received.sessionDigest.length, 64);
  assertEquals(received.accessTokenDigest === ACCESS_TOKEN, false);
  assertEquals(received.sessionDigest === received.accessTokenDigest, false);

  const cookie = response.headers.get("set-cookie") ?? "";
  assertStringIncludes(cookie, "__Host-lws_commercial_session=");
  assertStringIncludes(cookie, "HttpOnly; Secure; SameSite=Strict; Path=/");
  assertEquals(cookie.includes("Domain="), false);
  assertEquals(cookie.includes(ACCESS_TOKEN), false);
  assertEquals(await response.text(), "");
  assertEquals(response.headers.get("cache-control"), "private, no-store");
});

Deno.test("customer session creation rejects cross-origin POST before dependencies", async () => {
  let called = false;
  const request = sessionRequest(
    { projectId: PROJECT_ID, accessToken: ACCESS_TOKEN },
    { headers: { origin: "https://attacker.example" } },
  );
  const response = await handleCommercialCustomerApproval(request, service({
    redeemAccess: async () => {
      called = true;
      throw new Error("unexpected");
    },
  }));

  assertEquals(response.status, 403);
  assertEquals(await response.text(), "ORIGIN_FORBIDDEN");
  assertEquals(called, false);
  assertEquals(response.headers.has("set-cookie"), false);
});

Deno.test("GET never redeems a customer access token", async () => {
  let called = false;
  const response = await handleCommercialCustomerApproval(
    new Request(`${PUBLIC_ORIGIN}/session?projectId=${PROJECT_ID}&accessToken=${ACCESS_TOKEN}`, {
      method: "GET",
      headers: { origin: PUBLIC_ORIGIN },
    }),
    service({
      redeemAccess: async () => {
        called = true;
        throw new Error("unexpected");
      },
    }),
  );

  assertEquals(response.status, 405);
  assertEquals(called, false);
  assertEquals(response.headers.has("set-cookie"), false);
  assertEquals((await response.text()).includes(ACCESS_TOKEN), false);
});

Deno.test("invalid access is denied without setting a session cookie", async () => {
  const response = await handleCommercialCustomerApproval(
    sessionRequest({ projectId: PROJECT_ID, accessToken: ACCESS_TOKEN }),
    service({ redeemAccess: async () => { throw new Error("ACCESS_DENIED"); } }),
  );

  assertEquals(response.status, 403);
  assertEquals(await response.text(), "ACCESS_DENIED");
  assertEquals(response.headers.has("set-cookie"), false);
});

Deno.test("malformed redemption input is rejected before dependencies", async () => {
  let called = false;
  const response = await handleCommercialCustomerApproval(
    sessionRequest({ projectId: "not-a-project", accessToken: "short" }),
    service({
      redeemAccess: async () => {
        called = true;
        throw new Error("unexpected");
      },
    }),
  );

  assertEquals(response.status, 400);
  assertEquals(await response.text(), "INVALID_REQUEST");
  assertEquals(called, false);
});

Deno.test("approval page keeps the access credential in the URL fragment and out of browser storage", async () => {
  const response = await handleCommercialCustomerApproval(
    new Request(`${PUBLIC_ORIGIN}/`, { method: "GET" }),
    service(),
  );
  const html = await response.text();

  assertEquals(response.status, 200);
  assertStringIncludes(response.headers.get("content-type") ?? "", "text/html");
  assertStringIncludes(html, "location.hash");
  assertStringIncludes(html, "history.replaceState");
  assertEquals(/localStorage|sessionStorage/.test(html), false);
  assertEquals(/submit_customer_approval/.test(html), false);
});

Deno.test("delivery page shows the bound project and registered document action", async () => {
  const response = await handleCommercialCustomerApproval(
    new Request(`${PUBLIC_ORIGIN}/`, { method: "GET" }),
    service(),
  );
  const html = await response.text();

  assertStringIncludes(html, '<span class="label">Projectreferentie</span>');
  assertStringIncludes(html, 'id="project"');
  assertStringIncludes(html, "data.projectId");
  assertStringIncludes(html, 'id="version"');
  assertStringIncludes(html, 'id="view-document"');
  assertStringIncludes(html, 'id="document-frame"');
});

Deno.test("acceptance controls are hidden until the registered document is viewed and never pre-checked", async () => {
  const response = await handleCommercialCustomerApproval(
    new Request(`${PUBLIC_ORIGIN}/`, { method: "GET" }),
    service(),
  );
  const html = await response.text();
  const acceptance = /<section id="acceptance"[^>]*>/.exec(html)?.[0] ?? "";
  const checkbox = /<input[^>]*id="confirmed"[^>]*>/.exec(html)?.[0] ?? "";
  const approve = /<button[^>]*id="approve"[^>]*>/.exec(html)?.[0] ?? "";

  assertStringIncludes(acceptance, "hidden");
  assertStringIncludes(checkbox, 'type="checkbox"');
  assertEquals(/\bchecked\b/.test(checkbox), false);
  assertStringIncludes(approve, "disabled");
  assertStringIncludes(html, "Ik heb de website gecontroleerd en bevestig deze formele aanvaarding.");
  assertStringIncludes(html, "Goedkeuring vastleggen");
  assertStringIncludes(html, "data.statementText");
  assertStringIncludes(html, "endpoint+'/approval'");
  assertStringIncludes(html, "x-lws-document-sha256");
  assertStringIncludes(html, "viewedPdfSha256");
  assertStringIncludes(html, "viewedDocumentVersion");
  // The approval request is only reachable from the approve click handler, after an explicit check.
  assertEquals(html.indexOf("endpoint+'/approval'") > html.indexOf("approve.addEventListener('click'"), true);
  assertStringIncludes(html, "approve.disabled=!(confirmed.checked&&viewed");
  assertEquals(acceptance.indexOf("hidden") >= 0 && html.indexOf('id="acceptance"') > html.indexOf('id="document-frame"'), true);
});

Deno.test("acceptance page reuses the reviewed W4.3 processing and error texts", async () => {
  const html = await (await handleCommercialCustomerApproval(
    new Request(`${PUBLIC_ORIGIN}/`, { method: "GET" }),
    service(),
  )).text();

  assertStringIncludes(html, "Goedkeuring vastleggen…");
  assertStringIncludes(html, "Goedkeuring kon niet worden vastgelegd. Vernieuw de pagina en controleer de actuele versie.");
  assertEquals(html.includes("Goedkeuring wordt vastgelegd…"), false);
  assertEquals(html.includes("'De goedkeuring kon niet worden vastgelegd.'"), false);
});

Deno.test("a recorded acceptance is reported even when the follow-up status refresh fails", async () => {
  const html = await (await handleCommercialCustomerApproval(
    new Request(`${PUBLIC_ORIGIN}/`, { method: "GET" }),
    service(),
  )).text();
  const click = html.slice(html.indexOf("approve.addEventListener('click'"));

  // The success text is set from the POST result; the context refresh must not turn it into an error.
  assertEquals(click.indexOf("Uw formele goedkeuring is vastgelegd.") > 0, true);
  assertEquals(click.indexOf("Uw formele goedkeuring is vastgelegd.") < click.indexOf("context().catch("), true);
  // The success body is consumed, so the request completes instead of leaving an unread response stream.
  assertStringIncludes(click, "if(!response.ok)throw new Error(await response.text());await response.text().catch(()=>'');");
});

Deno.test("acceptance controls appear only when the viewed bytes are the server's current document", async () => {
  const html = await (await handleCommercialCustomerApproval(
    new Request(`${PUBLIC_ORIGIN}/`, { method: "GET" }),
    service(),
  )).text();

  assertStringIncludes(html, "current.deliveryDocument.documentVersion===viewed.version");
  assertStringIncludes(html, "current.deliveryDocument.pdfSha256===viewed.sha");
});

Deno.test("hidden acceptance controls stay hidden despite their own display styles", async () => {
  const response = await handleCommercialCustomerApproval(
    new Request(`${PUBLIC_ORIGIN}/`, { method: "GET" }),
    service(),
  );
  const html = await response.text();

  // .confirm uses display:flex; without this rule a hidden confirmation checkbox stays visible after acceptance.
  assertStringIncludes(html, "[hidden]{display:none!important}");
});

Deno.test("delivery document action defines an explicit keyboard focus indicator", async () => {
  const response = await handleCommercialCustomerApproval(
    new Request(`${PUBLIC_ORIGIN}/`, { method: "GET" }),
    service(),
  );
  const html = await response.text();

  assertStringIncludes(html, "button:focus-visible");
  assertStringIncludes(html, "outline:");
  assertStringIncludes(html, "outline-offset:");
});

Deno.test("delivery status precedes the document action and viewer", async () => {
  const response = await handleCommercialCustomerApproval(
    new Request(`${PUBLIC_ORIGIN}/`, { method: "GET" }),
    service(),
  );
  const html = await response.text();
  const actionStatus = html.indexOf('id="status"');
  const button = html.indexOf('id="view-document"');
  const viewer = html.indexOf('id="document-frame"');

  assertEquals(actionStatus > 0, true);
  assertEquals(actionStatus < button, true);
  assertEquals(button < viewer, true);
});

Deno.test("session-bound document GET returns exact private PDF bytes without invoking approval", async () => {
  const pdf = new TextEncoder().encode("%PDF-1.7 exact registered bytes");
  let served: Record<string, string> | undefined;
  let submitted = false;
  const response = await handleCommercialCustomerApproval(
    new Request(`${PUBLIC_ORIGIN}/document?project_id=${PROJECT_ID}`, {
      headers: { cookie: `__Host-lws_commercial_session=${SESSION_TOKEN}` },
    }),
    service({
      serveDocument: async (input: Record<string, string>) => {
        served = input;
        return new Response(pdf, {
          headers: {
            "cache-control": "private, no-store",
            "content-type": "application/pdf",
            "content-disposition": 'inline; filename="opleverdocument-v3.pdf"',
            "x-lws-document-version": "3",
            "x-lws-document-sha256": "c".repeat(64),
          },
        });
      },
      submitApproval: async () => {
        submitted = true;
        throw new Error("unexpected");
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(new Uint8Array(await response.arrayBuffer()), pdf);
  assertEquals(response.headers.get("content-type"), "application/pdf");
  assertEquals(response.headers.get("cache-control"), "private, no-store");
  assertEquals(response.headers.get("x-lws-document-version"), "3");
  assertEquals(served?.projectId, PROJECT_ID);
  assertEquals(served?.sessionDigest.length, 64);
  assertEquals(submitted, false);
});

Deno.test("document GET rejects a missing customer session before dependencies", async () => {
  let called = false;
  const response = await handleCommercialCustomerApproval(
    new Request(`${PUBLIC_ORIGIN}/document?project_id=${PROJECT_ID}`),
    service({
      serveDocument: async () => {
        called = true;
        throw new Error("unexpected");
      },
    }),
  );

  assertEquals(response.status, 401);
  assertEquals(await response.text(), "SESSION_REQUIRED");
  assertEquals(called, false);
});

Deno.test("session-bound context GET returns official statement and current delivery without mutation", async () => {
  let submitted = false;
  const response = await handleCommercialCustomerApproval(
    new Request(`${PUBLIC_ORIGIN}/context?project_id=${PROJECT_ID}`, {
      headers: { cookie: `__Host-lws_commercial_session=${SESSION_TOKEN}` },
    }),
    service({
      submitApproval: async () => {
        submitted = true;
        throw new Error("unexpected");
      },
    }),
  );
  const body = await response.json();

  assertEquals(response.status, 200);
  assertEquals(body.statementVersion, "OPL-W-01");
  assertEquals(body.statementSha256, approvalContext.statementSha256);
  assertEquals(body.sourceByteLength, 169278);
  assertEquals(body.previewVersionId, approvalContext.previewVersionId);
  assertEquals(body.currentState, "M2_PAYMENT_RECEIVED");
  assertEquals(submitted, false);
});

Deno.test("approval POST derives authority and idempotency server-side", async () => {
  const calls: Record<string, unknown>[] = [];
  let contextReads = 0;
  const request = new Request(`${PUBLIC_ORIGIN}/approval`, {
    method: "POST",
    headers: {
      origin: PUBLIC_ORIGIN,
      cookie: `__Host-lws_commercial_session=${SESSION_TOKEN}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      projectId: PROJECT_ID,
      confirmed: true,
      ...VIEWED,
      statementVersion: "ATTACKER-CONTROLLED",
      statementSha256: "0".repeat(64),
      previewVersionId: "ca300000-0000-4000-8000-000000000099",
    }),
  });
  const bound = service({
    resolveContext: async () => {
      contextReads += 1;
      return contextReads === 1
        ? approvalContext
        : {
          ...approvalContext,
          currentState: "FINAL_APPROVAL_RECORDED",
          revision: 9,
          approvalReplayAvailable: true,
        };
    },
    submitApproval: async (input: Record<string, unknown>) => {
      calls.push(input);
      return {
        projectId: PROJECT_ID,
        resultingState: "FINAL_APPROVAL_RECORDED",
        revision: 9,
        commandType: "submit_customer_approval",
      };
    },
  });

  const first = await handleCommercialCustomerApproval(request, bound);
  const replay = await handleCommercialCustomerApproval(new Request(`${PUBLIC_ORIGIN}/approval`, {
    method: "POST",
    headers: {
      origin: PUBLIC_ORIGIN,
      cookie: `__Host-lws_commercial_session=${SESSION_TOKEN}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({ projectId: PROJECT_ID, confirmed: true, ...VIEWED }),
  }), bound);

  assertEquals(first.status, 200);
  assertEquals(replay.status, 200);
  assertEquals((await first.json()).resultingState, "FINAL_APPROVAL_RECORDED");
  assertEquals(calls.length, 2);
  assertEquals(calls[0].idempotencyKey, calls[1].idempotencyKey);
  assertEquals(calls[1].expectedState, "M2_PAYMENT_RECEIVED");
  assertEquals(calls[1].expectedRevision, 8);
  assertEquals(calls[0].statementVersion, "OPL-W-01");
  assertEquals(calls[0].statementSha256, approvalContext.statementSha256);
  assertEquals(calls[0].previewVersionId, approvalContext.previewVersionId);
  assertEquals(calls[0].viewedDocumentVersion, 3);
  assertEquals(calls[0].viewedPdfSha256, "c".repeat(64));
  assertEquals(JSON.stringify(calls[0]).includes("ATTACKER-CONTROLLED"), false);
});

Deno.test("approval POST requires the viewed document claim before any dependency", async () => {
  let contextRead = false;
  let submitted = false;
  const guarded = service({
    resolveContext: async () => {
      contextRead = true;
      return approvalContext;
    },
    submitApproval: async () => {
      submitted = true;
      throw new Error("unexpected");
    },
  });
  const missing = await handleCommercialCustomerApproval(
    approvalRequest({ projectId: PROJECT_ID, confirmed: true }),
    guarded,
  );
  const malformed = await handleCommercialCustomerApproval(
    approvalRequest({ projectId: PROJECT_ID, confirmed: true, viewedDocumentVersion: "3", viewedPdfSha256: "short" }),
    guarded,
  );

  assertEquals(missing.status, 400);
  assertEquals(await missing.text(), "VIEWED_DOCUMENT_REQUIRED");
  assertEquals(malformed.status, 400);
  assertEquals(contextRead, false);
  assertEquals(submitted, false);
});

Deno.test("approval POST refuses unviewed, missing, or changed registered documents without submitting", async () => {
  let submitted = 0;
  const attempt = async (context: Record<string, unknown>, body: Record<string, unknown> = VIEWED) =>
    await handleCommercialCustomerApproval(
      approvalRequest({ projectId: PROJECT_ID, confirmed: true, ...body }),
      service({
        resolveContext: async () => context,
        submitApproval: async () => {
          submitted += 1;
          throw new Error("unexpected");
        },
      }),
    );

  const notViewed = await attempt({ ...approvalContext, deliveryDocumentViewed: false });
  const noDocument = await attempt({ ...approvalContext, deliveryDocument: null, deliveryDocumentViewed: false });
  const otherHash = await attempt(approvalContext, { viewedDocumentVersion: 3, viewedPdfSha256: "f".repeat(64) });
  const replaced = await attempt({
    ...approvalContext,
    deliveryDocument: { ...approvalContext.deliveryDocument, documentVersion: 4, pdfSha256: "2".repeat(64) },
  });

  assertEquals(notViewed.status, 409);
  assertEquals(await notViewed.text(), "DOCUMENT_VIEW_REQUIRED");
  assertEquals(noDocument.status, 409);
  assertEquals(await noDocument.text(), "DOCUMENT_NOT_AVAILABLE");
  assertEquals(otherHash.status, 409);
  assertEquals(await otherHash.text(), "DOCUMENT_VERSION_CHANGED");
  assertEquals(replaced.status, 409);
  assertEquals(await replaced.text(), "DOCUMENT_VERSION_CHANGED");
  assertEquals(submitted, 0);
});

Deno.test("approval idempotency is bound to the viewed document version and hash", async () => {
  const keys: unknown[] = [];
  const submit = async (input: Record<string, unknown>) => {
    keys.push(input.idempotencyKey);
    return { projectId: PROJECT_ID, resultingState: "FINAL_APPROVAL_RECORDED", revision: 9, commandType: "submit_customer_approval" };
  };
  const v4 = { documentVersion: 4, pdfSha256: "2".repeat(64) };
  await handleCommercialCustomerApproval(approvalRequest({ projectId: PROJECT_ID, confirmed: true, ...VIEWED }),
    service({ submitApproval: submit }));
  await handleCommercialCustomerApproval(approvalRequest({ projectId: PROJECT_ID, confirmed: true, ...VIEWED }),
    service({ submitApproval: submit }));
  await handleCommercialCustomerApproval(
    approvalRequest({ projectId: PROJECT_ID, confirmed: true, viewedDocumentVersion: 4, viewedPdfSha256: v4.pdfSha256 }),
    service({
      resolveContext: async () => ({ ...approvalContext, deliveryDocument: { ...approvalContext.deliveryDocument, ...v4 } }),
      submitApproval: submit,
    }),
  );

  assertEquals(keys.length, 3);
  assertEquals(keys[0], keys[1]);
  assertEquals(keys[0] === keys[2], false);
});

Deno.test("database acceptance refusals map to explicit customer-safe codes", async () => {
  const refused = async (message: string) => {
    const response = await handleCommercialCustomerApproval(
      approvalRequest({ projectId: PROJECT_ID, confirmed: true, ...VIEWED }),
      service({ submitApproval: async () => { throw new Error(message); } }),
    );
    return [response.status, await response.text()];
  };

  assertEquals(await refused("WEBSITE_DELIVERY_VIEW_EVIDENCE_REQUIRED"), [409, "DOCUMENT_VIEW_REQUIRED"]);
  assertEquals(await refused("WEBSITE_DELIVERY_DOCUMENT_VERSION_CHANGED"), [409, "DOCUMENT_VERSION_CHANGED"]);
  assertEquals(await refused("WEBSITE_DELIVERY_ACCEPTANCE_INPUT_INVALID"), [400, "VIEWED_DOCUMENT_REQUIRED"]);
  assertEquals(await refused("ACCESS_DENIED"), [401, "SESSION_INVALID"]);
  assertEquals(await refused("WEBSITE_DELIVERY_ALREADY_ACCEPTED"), [409, "APPROVAL_NOT_AVAILABLE"]);
});

Deno.test("approval POST rejects missing confirmation, missing session, cross-origin, and stale preview", async () => {
  const request = (body: unknown, headers: HeadersInit = {}) => new Request(`${PUBLIC_ORIGIN}/approval`, {
    method: "POST",
    headers: {
      origin: PUBLIC_ORIGIN,
      cookie: `__Host-lws_commercial_session=${SESSION_TOKEN}`,
      "content-type": "application/json",
      ...headers,
    },
    body: JSON.stringify(body),
  });

  const unconfirmed = await handleCommercialCustomerApproval(
    request({ projectId: PROJECT_ID, confirmed: false }),
    service(),
  );
  const noSession = await handleCommercialCustomerApproval(
    request({ projectId: PROJECT_ID, confirmed: true }, { cookie: "" }),
    service(),
  );
  const crossOrigin = await handleCommercialCustomerApproval(
    request({ projectId: PROJECT_ID, confirmed: true }, { origin: "https://attacker.example" }),
    service(),
  );
  const stale = await handleCommercialCustomerApproval(
    request({ projectId: PROJECT_ID, confirmed: true, ...VIEWED }),
    service({ resolveContext: async () => { throw new Error("PREVIEW_VERSION_MISMATCH"); } }),
  );

  assertEquals(unconfirmed.status, 400);
  assertEquals(noSession.status, 401);
  assertEquals(crossOrigin.status, 403);
  assertEquals(stale.status, 409);
});
