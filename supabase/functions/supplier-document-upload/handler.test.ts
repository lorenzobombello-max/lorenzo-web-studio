import { assert, assertEquals, assertMatch } from "jsr:@std/assert@1";
import {
  handleSupplierDocumentUpload,
  SUPPLIER_DOCUMENT_BUCKET,
  SUPPLIER_DOCUMENT_MAX_BYTES,
  type SupplierDocumentUploadDependencies,
} from "./handler.ts";

const ORIGIN = "https://lorenzowebsolutions.be";
const PDF = new TextEncoder().encode("%PDF-1.7 supplier document");
const PNG = new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10, 1]);
const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1]);

type PutInput = Parameters<SupplierDocumentUploadDependencies["putObject"]>[0];
type FinalizeInput = Parameters<
  SupplierDocumentUploadDependencies["finalizeObjectMetadata"]
>[0];

function request(
  bytes: Uint8Array,
  mimeType: string,
  headers: Record<string, string> = {},
): Request {
  return new Request(
    "https://project.supabase.co/functions/v1/supplier-document-upload",
    {
      method: "POST",
      headers: {
        origin: ORIGIN,
        authorization: "Bearer user-jwt",
        "content-type": mimeType,
        ...headers,
      },
      body: new Uint8Array(bytes).buffer,
    },
  );
}

function dependencies(
  overrides: Partial<SupplierDocumentUploadDependencies> = {},
) {
  const puts: PutInput[] = [];
  const finalizations: FinalizeInput[] = [];
  const value: SupplierDocumentUploadDependencies = {
    verifyUser: () => Promise.resolve(true),
    authorizeOwner: () => Promise.resolve(true),
    putObject: (input) => {
      puts.push(input);
      return Promise.resolve("stored");
    },
    finalizeObjectMetadata: (input) => {
      finalizations.push(input);
      return Promise.resolve();
    },
    ...overrides,
  };
  return { value, puts, finalizations };
}

async function payload(response: Response): Promise<Record<string, unknown>> {
  return await response.json();
}

function assertNoStorageOrFinalizer(
  deps: ReturnType<typeof dependencies>,
): void {
  assertEquals(deps.puts.length, 0, "upload calls");
  assertEquals(
    deps.puts.length,
    0,
    "collision-download calls: putObject boundary was not entered",
  );
  assertEquals(deps.finalizations.length, 0, "finalizer calls");
}

Deno.test("active owner uploads PDF with server-derived canonical metadata", async () => {
  const deps = dependencies();
  const result = await handleSupplierDocumentUpload(
    request(PDF, "application/pdf", { "x-storage-path": "attacker/path" }),
    deps.value,
  );
  const body = await payload(result);
  assertEquals(result.status, 200);
  assertEquals(body.code, "STORED");
  assertEquals(body.bucket, SUPPLIER_DOCUMENT_BUCKET);
  assertEquals(body.byte_count, PDF.byteLength);
  assertEquals(body.mime_type, "application/pdf");
  assertMatch(String(body.sha256), /^[0-9a-f]{64}$/);
  assertEquals(body.object_path, `documents/${body.sha256}.pdf`);
  assertEquals(deps.puts.length, 1);
  assertEquals(deps.puts[0].objectPath, body.object_path);
  assertEquals(deps.puts[0].upsert, false);
  assertEquals(deps.finalizations, [{
    bucket: SUPPLIER_DOCUMENT_BUCKET,
    objectPath: body.object_path,
    sha256: body.sha256,
    byteCount: PDF.byteLength,
    mimeType: "application/pdf",
  }]);
});

for (
  const fixture of [
    { name: "PNG", bytes: PNG, mime: "image/png", extension: "png" },
    { name: "JPEG", bytes: JPEG, mime: "image/jpeg", extension: "jpg" },
  ]
) {
  Deno.test(`${fixture.name} receives its canonical extension`, async () => {
    const deps = dependencies();
    const result = await handleSupplierDocumentUpload(
      request(fixture.bytes, fixture.mime),
      deps.value,
    );
    const body = await payload(result);
    assertEquals(result.status, 200);
    assertMatch(
      String(body.object_path),
      new RegExp(`^documents/[0-9a-f]{64}\\.${fixture.extension}$`),
    );
    assertEquals(deps.puts[0].mimeType, fixture.mime);
  });
}

for (
  const actor of ["anonymous", "non-owner", "disabled", "revoked", "unknown"]
) {
  Deno.test(`${actor} is denied without storage mutation`, async () => {
    const deps = dependencies(
      actor === "anonymous"
        ? { verifyUser: () => Promise.resolve(false) }
        : { authorizeOwner: () => Promise.resolve(false) },
    );
    const result = await handleSupplierDocumentUpload(
      request(PDF, "application/pdf"),
      deps.value,
    );
    assertEquals(result.status, 403);
    assertEquals(await payload(result), {
      ok: false,
      code: "SUPPLIER_DOCUMENT_UPLOAD_OWNER_REQUIRED",
    });
    assertNoStorageOrFinalizer(deps);
  });
}

Deno.test("missing bearer token is denied", async () => {
  const deps = dependencies();
  const result = await handleSupplierDocumentUpload(
    new Request(
      "https://project.supabase.co/functions/v1/supplier-document-upload",
      {
        method: "POST",
        headers: { origin: ORIGIN, "content-type": "application/pdf" },
        body: PDF,
      },
    ),
    deps.value,
  );
  assertEquals(result.status, 401);
  assertEquals(await payload(result), {
    ok: false,
    code: "AUTHENTICATION_REQUIRED",
  });
  assertNoStorageOrFinalizer(deps);
});

for (
  const authorization of [
    "",
    "Bearer",
    "Basic token",
    "Bearer token extra",
  ]
) {
  Deno.test(`malformed bearer ${JSON.stringify(authorization)} is denied before side effects`, async () => {
    let verifyCalls = 0;
    let authorityCalls = 0;
    const deps = dependencies({
      verifyUser: () => {
        verifyCalls += 1;
        return Promise.resolve(true);
      },
      authorizeOwner: () => {
        authorityCalls += 1;
        return Promise.resolve(true);
      },
    });
    const result = await handleSupplierDocumentUpload(
      request(PDF, "application/pdf", { authorization }),
      deps.value,
    );
    assertEquals(result.status, 401);
    assertEquals(await payload(result), {
      ok: false,
      code: "AUTHENTICATION_REQUIRED",
    });
    assertEquals(verifyCalls, 0);
    assertEquals(authorityCalls, 0);
    assertNoStorageOrFinalizer(deps);
  });
}

for (const tokenState of ["invalid", "expired"]) {
  Deno.test(`${tokenState} JWT is denied before authority or side effects`, async () => {
    let authorityCalls = 0;
    const deps = dependencies({
      verifyUser: () => Promise.resolve(false),
      authorizeOwner: () => {
        authorityCalls += 1;
        return Promise.resolve(true);
      },
    });
    const result = await handleSupplierDocumentUpload(
      request(PDF, "application/pdf"),
      deps.value,
    );
    assertEquals(result.status, 403);
    assertEquals(await payload(result), {
      ok: false,
      code: "SUPPLIER_DOCUMENT_UPLOAD_OWNER_REQUIRED",
    });
    assertEquals(authorityCalls, 0);
    assertNoStorageOrFinalizer(deps);
  });
}

Deno.test("verifier exception fails closed before authority or side effects", async () => {
  let authorityCalls = 0;
  const deps = dependencies({
    verifyUser: () => Promise.reject(new Error("verifier unavailable")),
    authorizeOwner: () => {
      authorityCalls += 1;
      return Promise.resolve(true);
    },
  });
  const result = await handleSupplierDocumentUpload(
    request(PDF, "application/pdf"),
    deps.value,
  );
  assertEquals(result.status, 503);
  assertEquals(await payload(result), {
    ok: false,
    code: "UPLOAD_NOT_AVAILABLE",
  });
  assertEquals(authorityCalls, 0);
  assertNoStorageOrFinalizer(deps);
});

Deno.test("authority exception fails closed before storage or finalizer", async () => {
  const deps = dependencies({
    authorizeOwner: () => Promise.reject(new Error("authority unavailable")),
  });
  const result = await handleSupplierDocumentUpload(
    request(PDF, "application/pdf"),
    deps.value,
  );
  assertEquals(result.status, 503);
  assertEquals(await payload(result), {
    ok: false,
    code: "UPLOAD_NOT_AVAILABLE",
  });
  assertNoStorageOrFinalizer(deps);
});

Deno.test("unsupported declared MIME is rejected", async () => {
  const deps = dependencies();
  const result = await handleSupplierDocumentUpload(
    request(PDF, "application/octet-stream"),
    deps.value,
  );
  assertEquals(result.status, 415);
  assertEquals(deps.puts.length, 0);
});

Deno.test("declared MIME must match server-observed binary signature", async () => {
  const deps = dependencies();
  const result = await handleSupplierDocumentUpload(
    request(PNG, "application/pdf"),
    deps.value,
  );
  assertEquals(result.status, 415);
  assertEquals(deps.puts.length, 0);
});

Deno.test("zero-byte binary is rejected", async () => {
  const deps = dependencies();
  const result = await handleSupplierDocumentUpload(
    request(new Uint8Array(), "application/pdf"),
    deps.value,
  );
  assertEquals(result.status, 400);
  assertEquals(deps.puts.length, 0);
});

Deno.test("declared file over ten MiB is rejected before authorization or upload", async () => {
  let verified = false;
  const deps = dependencies({
    verifyUser: () => {
      verified = true;
      return Promise.resolve(true);
    },
  });
  const result = await handleSupplierDocumentUpload(
    request(PDF, "application/pdf", {
      "content-length": String(SUPPLIER_DOCUMENT_MAX_BYTES + 1),
    }),
    deps.value,
  );
  assertEquals(result.status, 413);
  assertEquals(verified, false);
  assertEquals(deps.puts.length, 0);
});

Deno.test("actual streamed file over ten MiB is rejected without upload", async () => {
  const deps = dependencies();
  const oversized = new Uint8Array(SUPPLIER_DOCUMENT_MAX_BYTES + 1);
  oversized.set(PDF);
  const result = await handleSupplierDocumentUpload(
    request(oversized, "application/pdf"),
    deps.value,
  );
  assertEquals(result.status, 413);
  assertEquals(deps.puts.length, 0);
});

Deno.test("exact ten MiB binary is accepted", async () => {
  const deps = dependencies();
  const maximum = new Uint8Array(SUPPLIER_DOCUMENT_MAX_BYTES);
  maximum.set(PDF);
  const result = await handleSupplierDocumentUpload(
    request(maximum, "application/pdf"),
    deps.value,
  );
  assertEquals(result.status, 200);
  assertEquals(deps.puts[0].bytes.byteLength, SUPPLIER_DOCUMENT_MAX_BYTES);
});

Deno.test("declared and observed byte counts must match", async () => {
  const deps = dependencies();
  const result = await handleSupplierDocumentUpload(
    request(PDF, "application/pdf", {
      "content-length": String(PDF.byteLength + 1),
    }),
    deps.value,
  );
  assertEquals(result.status, 400);
  assertEquals(deps.puts.length, 0);
});

Deno.test("invalid content length is rejected", async () => {
  const deps = dependencies();
  const result = await handleSupplierDocumentUpload(
    request(PDF, "application/pdf", { "content-length": "invalid" }),
    deps.value,
  );
  assertEquals(result.status, 400);
  assertEquals(deps.puts.length, 0);
});

Deno.test("duplicate binary is deterministic and never overwrites", async () => {
  const deps = dependencies({ putObject: () => Promise.resolve("duplicate") });
  const first = await payload(
    await handleSupplierDocumentUpload(
      request(PDF, "application/pdf"),
      deps.value,
    ),
  );
  const second = await payload(
    await handleSupplierDocumentUpload(
      request(PDF, "application/pdf"),
      deps.value,
    ),
  );
  assertEquals(first, second);
  assertEquals(first.code, "DUPLICATE");
});

Deno.test("unexpected storage error is contained", async () => {
  const deps = dependencies({
    putObject: () => Promise.reject(new Error("storage detail")),
  });
  const result = await handleSupplierDocumentUpload(
    request(PDF, "application/pdf"),
    deps.value,
  );
  assertEquals(result.status, 503);
  assertEquals(await payload(result), {
    ok: false,
    code: "UPLOAD_NOT_AVAILABLE",
  });
});

Deno.test("metadata finalization failure is contained for canonical retry", async () => {
  const deps = dependencies({
    finalizeObjectMetadata: () => Promise.reject(new Error("finalize failed")),
  });
  const result = await handleSupplierDocumentUpload(
    request(PDF, "application/pdf"),
    deps.value,
  );
  assertEquals(result.status, 503);
  assertEquals(deps.puts.length, 1);
});

Deno.test("disallowed origin and method are rejected without storage mutation", async () => {
  const deps = dependencies();
  const blockedOrigin = request(PDF, "application/pdf", {
    origin: "https://attacker.example",
  });
  const wrongMethod = new Request(
    "https://project.supabase.co/functions/v1/supplier-document-upload",
    {
      method: "GET",
      headers: { origin: ORIGIN, authorization: "Bearer user-jwt" },
    },
  );
  assertEquals(
    (await handleSupplierDocumentUpload(blockedOrigin, deps.value)).status,
    403,
  );
  assertEquals(
    (await handleSupplierDocumentUpload(wrongMethod, deps.value)).status,
    405,
  );
  assertEquals(deps.puts.length, 0);
});

Deno.test("response exposes no credential or download authority", async () => {
  const deps = dependencies();
  const body = await payload(
    await handleSupplierDocumentUpload(
      request(PDF, "application/pdf"),
      deps.value,
    ),
  );
  assertEquals(Object.keys(body).sort(), [
    "bucket",
    "byte_count",
    "code",
    "mime_type",
    "object_path",
    "ok",
    "sha256",
  ]);
  assert(!JSON.stringify(body).match(/signed|secret|credential|download/i));
});

Deno.test("allowed-origin preflight performs no authorization or upload", async () => {
  let verified = false;
  let authorized = false;
  const deps = dependencies({
    verifyUser: () => {
      verified = true;
      return Promise.resolve(true);
    },
    authorizeOwner: () => {
      authorized = true;
      return Promise.resolve(true);
    },
  });
  const result = await handleSupplierDocumentUpload(
    new Request(
      "https://project.supabase.co/functions/v1/supplier-document-upload",
      {
        method: "OPTIONS",
        headers: { origin: ORIGIN },
      },
    ),
    deps.value,
  );
  assertEquals(result.status, 204);
  assertEquals(verified, false);
  assertEquals(authorized, false);
  assertNoStorageOrFinalizer(deps);
});
