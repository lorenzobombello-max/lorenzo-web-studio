const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const {
  apiClient,
  readAndClearFragment,
  uploadToSignedUrl,
  validateFile,
} = require("./customer-request-upload.js");

const TOKEN = "A".repeat(43);

test("reads the capability from the fragment and immediately clears it", () => {
  const calls = [];
  const location = {
    hash: `#token=${TOKEN}`,
    pathname: "/pages/customer-request-upload.html",
    search: "?source=email&token=query-secret",
  };
  const token = readAndClearFragment(location, {
    state: null,
    replaceState: (...args) => calls.push(args),
  });
  assert.equal(token, TOKEN);
  assert.deepEqual(calls, [[null, "", "/pages/customer-request-upload.html?source=email"]]);
});

test("capability requests use only an authorization bearer", async () => {
  const requests = [];
  const api = apiClient("https://example.test/functions/v1", TOKEN, async (url, options) => {
    requests.push({ url, options });
    return { ok: true, status: 200, async json() { return { ok: true, state: "ACTIVE" }; } };
  });
  await api.resolve();
  assert.equal(requests[0].url, "https://example.test/functions/v1/customer-request-upload");
  assert.equal(requests[0].url.includes(TOKEN), false);
  assert.equal(requests[0].options.headers.Authorization, `Bearer ${TOKEN}`);
  assert.equal(requests[0].options.referrerPolicy, "no-referrer");
});

test("prepare and finalize use idempotency without browser authority ids", async () => {
  const requests = [];
  const api = apiClient("https://example.test/functions/v1", TOKEN, async (url, options) => {
    requests.push({ url, options });
    return { ok: true, status: 200, async json() { return { ok: true, state: "PREPARED" }; } };
  });
  await api.prepare({ file_name: "bewijs.pdf", content_type: "application/pdf", byte_count: 42 }, "d3e89000-0000-4000-8000-000000000001");
  await api.finalize("d3e89000-0000-4000-8000-000000000002", "d3e89000-0000-4000-8000-000000000003");
  const bodies = requests.map((request) => JSON.parse(request.options.body));
  assert.deepEqual(Object.keys(bodies[0]).sort(), ["action", "byte_count", "content_type", "file_name"]);
  assert.deepEqual(Object.keys(bodies[1]).sort(), ["action", "file_id"]);
  assert.equal(requests.every((request) => request.options.headers["Idempotency-Key"]), true);
});

test("signed upload never overwrites and sends the declared MIME", async () => {
  let request;
  const file = { type: "image/png" };
  await uploadToSignedUrl("https://storage.example.test/signed", file, async (url, options) => {
    request = { url, options };
    return { ok: true, status: 200 };
  });
  assert.equal(request.options.method, "PUT");
  assert.equal(request.options.headers["Content-Type"], "image/png");
  assert.equal(request.options.headers["x-upsert"], "false");
});

test("client validation mirrors the hard file contract", () => {
  assert.equal(validateFile({ name: "bewijs.pdf", type: "application/pdf", size: 8388608 }), null);
  assert.equal(validateFile({ name: "foto.jpeg", type: "image/jpeg", size: 1 }), null);
  assert.equal(validateFile({ name: "te-groot.png", type: "image/png", size: 8388609 }), "FILE_TOO_LARGE");
  assert.equal(validateFile({ name: "script.exe", type: "application/octet-stream", size: 1 }), "FILE_TYPE_NOT_ALLOWED");
});

test("source and page prohibit capability persistence", () => {
  const source = fs.readFileSync(path.join(__dirname, "customer-request-upload.js"), "utf8");
  const html = fs.readFileSync(path.join(__dirname, "../../pages/customer-request-upload.html"), "utf8");
  assert.equal(/localStorage|sessionStorage|document\.cookie|console\./.test(source), false);
  assert.match(html, /<meta name="referrer" content="no-referrer"/);
  assert.match(html, /<meta name="robots" content="noindex, nofollow, noarchive"/);
});