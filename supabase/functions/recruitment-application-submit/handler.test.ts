import { assertEquals, assertMatch } from "jsr:@std/assert@1";
import {
  handleRecruitmentApplicationSubmit,
  RECRUITMENT_CV_MAX_BYTES,
  type RecruitmentApplicationSubmitDependencies,
} from "./handler.ts";

const vacancyId = "fa000000-0000-4000-8000-000000000001";
const applicationId = "fa100000-0000-4000-8000-000000000001";
const PDF = new TextEncoder().encode("%PDF-1.7 synthetic cv");
const DOC = new Uint8Array([
  0xd0,
  0xcf,
  0x11,
  0xe0,
  0xa1,
  0xb1,
  0x1a,
  0xe1,
  0x00,
]);

function littleEndian(value: number, width: number): number[] {
  return Array.from(
    { length: width },
    (_, index) => (value >>> (index * 8)) & 0xff,
  );
}

function zipWithEntries(names: string[]): Uint8Array {
  const localRecords: number[] = [];
  const centralRecords: number[] = [];
  for (const name of names) {
    const encoded = [...new TextEncoder().encode(name)];
    const localOffset = localRecords.length;
    localRecords.push(
      ...littleEndian(0x04034b50, 4),
      ...littleEndian(20, 2),
      ...new Array(20).fill(0),
      ...littleEndian(encoded.length, 2),
      0,
      0,
      ...encoded,
    );
    centralRecords.push(
      ...littleEndian(0x02014b50, 4),
      ...littleEndian(20, 2),
      ...littleEndian(20, 2),
      ...new Array(20).fill(0),
      ...littleEndian(encoded.length, 2),
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      ...new Array(4).fill(0),
      ...littleEndian(localOffset, 4),
      ...encoded,
    );
  }
  const end = [
    ...littleEndian(0x06054b50, 4),
    0,
    0,
    0,
    0,
    ...littleEndian(names.length, 2),
    ...littleEndian(names.length, 2),
    ...littleEndian(centralRecords.length, 4),
    ...littleEndian(localRecords.length, 4),
    0,
    0,
  ];
  return new Uint8Array([...localRecords, ...centralRecords, ...end]);
}

const DOCX = zipWithEntries(["[Content_Types].xml", "word/document.xml"]);

type Call = { type: string; value: Record<string, unknown> };

function dependencies(
  overrides: Partial<RecruitmentApplicationSubmitDependencies> = {},
) {
  const calls: Call[] = [];
  const value: RecruitmentApplicationSubmitDependencies = {
    createApplicationId: () => applicationId,
    putObject: async (input) => {
      calls.push({ type: "put", value: input });
    },
    finalizeApplication: async (input) => {
      calls.push({ type: "finalize", value: input });
    },
    removeObject: async (bucket, objectPath) => {
      calls.push({ type: "remove", value: { bucket, objectPath } });
    },
    ...overrides,
  };
  return { calls, value };
}

function request(
  bytes: Uint8Array | null = PDF,
  mimeType = "application/pdf",
  filename = "cv.pdf",
  fields: Record<string, string> = {},
): Request {
  const form = new FormData();
  form.set("vacancy_id", fields.vacancy_id ?? vacancyId);
  form.set("first_name", fields.first_name ?? " Ada ");
  form.set("last_name", fields.last_name ?? " Lovelace ");
  form.set("email", fields.email ?? " ADA@EXAMPLE.TEST ");
  form.set("phone", fields.phone ?? "");
  form.set(
    "motivation",
    fields.motivation ?? "Ik bouw graag zorgvuldige software.",
  );
  if (bytes !== null) {
    form.set(
      "cv",
      new File([new Uint8Array(bytes).buffer], filename, { type: mimeType }),
    );
  }
  for (const [key, value] of Object.entries(fields)) form.set(key, value);
  return new Request(
    "https://lorenzowebsolutions.be/functions/v1/recruitment-application-submit",
    {
      method: "POST",
      body: form,
    },
  );
}

async function body(response: Response): Promise<Record<string, unknown>> {
  return await response.json();
}

Deno.test("valid PDF is uploaded to a server-controlled path and finalized", async () => {
  const harness = dependencies();
  const response = await handleRecruitmentApplicationSubmit(
    request(),
    harness.value,
  );
  assertEquals(response.status, 201);
  assertEquals(await body(response), { ok: true, code: "SUBMITTED" });
  assertEquals(harness.calls.map((call) => call.type), ["put", "finalize"]);
  assertEquals(
    harness.calls[0].value.objectPath,
    `applications/${applicationId}/cv.pdf`,
  );
  assertEquals(harness.calls[0].value.upsert, false);
  assertMatch(String(harness.calls[0].value.sha256), /^[0-9a-f]{64}$/);
  assertEquals(harness.calls[1].value.email, "ada@example.test");
  assertEquals(harness.calls[1].value.phone, null);
  assertMatch(String(harness.calls[1].value.cvSha256), /^[0-9a-f]{64}$/);
});

for (
  const fixture of [
    {
      name: "DOC",
      bytes: DOC,
      mime: "application/msword",
      filename: "cv.doc",
      extension: "doc",
    },
    {
      name: "DOCX",
      bytes: DOCX,
      mime:
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      filename: "cv.docx",
      extension: "docx",
    },
  ]
) {
  Deno.test(`valid ${fixture.name} is accepted`, async () => {
    const harness = dependencies();
    const response = await handleRecruitmentApplicationSubmit(
      request(fixture.bytes, fixture.mime, fixture.filename),
      harness.value,
    );
    assertEquals(response.status, 201);
    assertEquals(
      harness.calls[0].value.objectPath,
      `applications/${applicationId}/cv.${fixture.extension}`,
    );
  });
}

Deno.test("missing and oversized CVs are denied before storage", async () => {
  const missing = dependencies();
  assertEquals(
    (await handleRecruitmentApplicationSubmit(request(null), missing.value))
      .status,
    400,
  );
  assertEquals(missing.calls, []);
  const oversized = dependencies();
  const response = await handleRecruitmentApplicationSubmit(
    request(new Uint8Array(RECRUITMENT_CV_MAX_BYTES + 1)),
    oversized.value,
  );
  assertEquals(response.status, 413);
  assertEquals(oversized.calls, []);
});

Deno.test("executable and fake extension or MIME are denied", async () => {
  for (
    const candidate of [
      request(
        new Uint8Array([0x4d, 0x5a]),
        "application/octet-stream",
        "cv.exe",
      ),
      request(PDF, "application/pdf", "cv.doc"),
      request(PDF, "application/msword", "cv.doc"),
    ]
  ) {
    const harness = dependencies();
    assertEquals(
      (await handleRecruitmentApplicationSubmit(candidate, harness.value))
        .status,
      415,
    );
    assertEquals(harness.calls, []);
  }
});

Deno.test("macro-enabled or generic ZIP content is denied as DOCX", async () => {
  for (
    const entries of [
      ["generic/file.txt"],
      ["[Content_Types].xml", "word/document.xml", "word/vbaProject.bin"],
    ]
  ) {
    const bytes = zipWithEntries(entries);
    const harness = dependencies();
    assertEquals(
      (await handleRecruitmentApplicationSubmit(
        request(
          bytes,
          "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
          "cv.docx",
        ),
        harness.value,
      )).status,
      415,
    );
    assertEquals(harness.calls, []);
  }
});

Deno.test("invalid applicant fields and client-supplied authority fields are denied", async () => {
  const invalidFields: Record<string, string>[] = [
    { first_name: "" },
    { last_name: "x".repeat(101) },
    { email: "invalid" },
    { motivation: "x".repeat(5001) },
    { status: "ACCEPTED" },
    { cv_storage_path: "attacker/path.pdf" },
  ];
  for (const fields of invalidFields) {
    const harness = dependencies();
    assertEquals(
      (await handleRecruitmentApplicationSubmit(
        request(PDF, "application/pdf", "cv.pdf", fields),
        harness.value,
      )).status,
      400,
    );
    assertEquals(harness.calls, []);
  }
});

Deno.test("wrong method and non-multipart requests are denied", async () => {
  const harness = dependencies();
  assertEquals(
    (await handleRecruitmentApplicationSubmit(
      new Request("https://lorenzowebsolutions.be", { method: "GET" }),
      harness.value,
    )).status,
    405,
  );
  assertEquals(
    (await handleRecruitmentApplicationSubmit(
      new Request("https://lorenzowebsolutions.be", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: "{}",
      }),
      harness.value,
    )).status,
    415,
  );
});

Deno.test("upload failure creates no finalized application", async () => {
  const harness = dependencies({
    putObject: async () => {
      throw new Error("storage unavailable");
    },
  });
  const response = await handleRecruitmentApplicationSubmit(
    request(),
    harness.value,
  );
  assertEquals(response.status, 503);
  assertEquals(harness.calls, []);
});

Deno.test("database failure removes the uploaded object and leaks no detail", async () => {
  const harness = dependencies({
    finalizeApplication: async () => {
      throw new Error("private candidate detail");
    },
  });
  const response = await handleRecruitmentApplicationSubmit(
    request(),
    harness.value,
  );
  assertEquals(response.status, 503);
  assertEquals(await body(response), {
    ok: false,
    code: "APPLICATION_NOT_AVAILABLE",
  });
  assertEquals(harness.calls.map((call) => call.type), ["put", "remove"]);
  assertEquals(
    harness.calls[1].value.objectPath,
    `applications/${applicationId}/cv.pdf`,
  );
});
