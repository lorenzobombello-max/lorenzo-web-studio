const assert = require("node:assert/strict");
const test = require("node:test");
const { apiClient, readAndClearFragment, TOKEN_PATTERN } = require("./quotation-acceptance.js");

test("reads the capability from the fragment and immediately clears it", () => {
  const calls = [];
  const location = { hash: `#token=${"A".repeat(43)}`, pathname: "/pages/quotation-acceptance.html", search: "" };
  const token = readAndClearFragment(location, { state: null, replaceState: (...args) => calls.push(args) });
  assert.equal(token, "A".repeat(43));
  assert.deepEqual(calls, [[null, "", "/pages/quotation-acceptance.html"]]);
  assert.equal(TOKEN_PATTERN.test(token), true);
});

test("missing and malformed capabilities are discarded without query fallback", () => {
  for (const hash of ["", "#token=bad", "#other=" + "A".repeat(43)]) {
    const calls = [];
    const token = readAndClearFragment({ hash, pathname: "/pages/quotation-acceptance.html", search: "?token=query-secret&source=email" }, { state: null, replaceState: (...args) => calls.push(args) });
    assert.equal(token, "");
    assert.equal(calls[0][2], "/pages/quotation-acceptance.html?source=email");
  }
});

test("resolve sends the bearer only in an authorization header", async () => {
  const requests = [];
  const api = apiClient("https://example.test/functions/v1", "A".repeat(43), async (url, options) => {
    requests.push({ url, options });
    return { ok: true, status: 200, async json() { return { ok: true, state: "ACTIVE" }; } };
  });
  assert.equal((await api.resolve()).state, "ACTIVE");
  assert.equal(requests[0].url, "https://example.test/functions/v1/quotation-acceptance");
  assert.equal(requests[0].url.includes("token"), false);
  assert.equal(requests[0].options.headers.Authorization, `Bearer ${"A".repeat(43)}`);
  assert.equal(requests[0].options.referrerPolicy, "no-referrer");
});

test("accept sends the exact existing request contract and idempotency header", async () => {
  let request;
  const api = apiClient("https://example.test/functions/v1", "A".repeat(43), async (url, options) => {
    request = { url, options };
    return { ok: true, status: 200, async json() { return { ok: true, state: "ACCEPTED" }; } };
  });
  const payload = { accepting_name: "Naam", accepting_email: "naam@example.test", accepting_organization: null, accepting_role: null, authority_declaration: true, terms_id: "terms", terms_version: "1" };
  assert.equal((await api.accept(payload, "d3e89000-0000-4000-8000-000000000001")).state, "ACCEPTED");
  assert.equal(request.options.method, "POST");
  assert.equal(request.options.headers["Idempotency-Key"], "d3e89000-0000-4000-8000-000000000001");
  assert.deepEqual(JSON.parse(request.options.body), payload);
});

test("network and server failures reject without exposing response details", async () => {
  const server = apiClient("https://example.test/functions/v1", "A".repeat(43), async () => ({ ok: false, status: 500, async json() { return { secret: "not exposed" }; } }));
  await assert.rejects(() => server.resolve(), /REQUEST_FAILED/);
  const network = apiClient("https://example.test/functions/v1", "A".repeat(43), async () => { throw new Error("offline"); });
  await assert.rejects(() => network.resolve(), /offline/);
});

test("source has no token persistence or logging primitives", () => {
  const source = require("node:fs").readFileSync(require.resolve("./quotation-acceptance.js"), "utf8");
  assert.equal(/localStorage|sessionStorage|console\.|location\.search.*token/.test(source), false);
});

test("page exposes only explicit acceptance controls and privacy metadata", () => {
  const fs = require("node:fs");
  const path = require("node:path");
  const html = fs.readFileSync(path.join(__dirname, "../../pages/quotation-acceptance.html"), "utf8");
  const css = fs.readFileSync(path.join(__dirname, "../css/quotation-acceptance.css"), "utf8");
  assert.match(html, /<meta name="referrer" content="no-referrer"/);
  assert.match(html, /<meta name="robots" content="noindex, nofollow, noarchive"/);
  assert.match(html, /id="acceptingName"[^>]+required/);
  assert.match(html, /id="acceptingEmail"[^>]+type="email"[^>]+required/);
  assert.match(html, /id="authorityDeclaration"[^>]+type="checkbox"[^>]+required/);
  assert.doesNotMatch(html, /Afwijzen|Weigeren|decline|reject/i);
  assert.match(css, /\.acceptance-layout\[hidden\].*display:\s*none/s);
});