import { assertEquals, assertFalse, assertStringIncludes } from "jsr:@std/assert@1";

const source = await Deno.readTextFile(new URL("./intake.js", import.meta.url));
const token = "A".repeat(43);

function sourceFunction(name: string): string {
  const signatures = [`function ${name}(`, `async function ${name}(`];
  const start = Math.min(...signatures.map((signature) => source.indexOf(signature)).filter((index) => index >= 0));
  assertFalse(!Number.isFinite(start), `${name} must exist`);
  const bodyStart = source.indexOf("{", start);
  let depth = 0;
  for (let index = bodyStart; index < source.length; index += 1) {
    if (source[index] === "{") depth += 1;
    if (source[index] === "}") depth -= 1;
    if (depth === 0) return source.slice(start, index + 1);
  }
  throw new Error(`Could not extract ${name}`);
}

type MockResult = {
  response: { ok: boolean; status: number };
  body: Record<string, any>;
};

function buildHarness(
  request: (action: string, data: undefined, signal: AbortSignal) => Promise<MockResult>,
  runTimeout = false,
) {
  const loading = { hidden: false };
  const unavailable = { hidden: true };
  const workspace = { hidden: true };
  const unavailableMessage = { textContent: "" };
  const contextName = { textContent: "" };
  const contextType = { textContent: "" };
  const contextStatus = { textContent: "" };
  const document = {
    getElementById(id: string) {
      return id === "contextName" ? contextName : contextType;
    },
  };
  let pricingScheduled = false;
  let shownStep: number | null = null;

  function showUnavailable(text: string) {
    loading.hidden = true;
    workspace.hidden = true;
    unavailableMessage.textContent = text;
    unavailable.hidden = false;
  }

  const window = {
    setTimeout(callback: () => void, milliseconds: number) {
      assertEquals(milliseconds, 15_000);
      if (runTimeout) callback();
      return 1;
    },
    clearTimeout() {},
  };
  const initialInspectErrorMessage = Function(
    `"use strict"; return (${sourceFunction("initialInspectErrorMessage")});`,
  )();
  const inspect = Function(
    "token",
    "endpoint",
    "showUnavailable",
    "AbortController",
    "window",
    "request",
    "restoreData",
    "document",
    "contextStatus",
    "loading",
    "workspace",
    "showStep",
    "setMessage",
    "setReadOnly",
    "schedulePricingPreview",
    "initialInspectErrorMessage",
    "INITIAL_INSPECT_TIMEOUT_MS",
    `"use strict";
      let previewStopped = false;
      let draftRevision = null;
      return (${sourceFunction("inspect")});`,
  )(
    token,
    "https://example.test/intake-quote-request",
    showUnavailable,
    AbortController,
    window,
    request,
    () => {},
    document,
    contextStatus,
    loading,
    workspace,
    (step: number) => shownStep = step,
    () => {},
    () => {},
    () => pricingScheduled = true,
    initialInspectErrorMessage,
    15_000,
  ) as () => Promise<void>;

  return {
    inspect,
    loading,
    unavailable,
    workspace,
    unavailableMessage,
    state: () => ({ pricingScheduled, shownStep }),
  };
}

function response(status: number, body: Record<string, any>): Promise<MockResult> {
  return Promise.resolve({ response: { ok: status >= 200 && status < 300, status }, body });
}

Deno.test("initial inspect success hides loading and shows the workspace", async () => {
  const harness = buildHarness(() => response(200, {
    ok: true,
    intake: { revision: 0, status: "invited" },
    request: { company: "Voorbeeld", website_type: "Website" },
    data: {},
  }));

  await harness.inspect();

  assertEquals(harness.loading.hidden, true);
  assertEquals(harness.workspace.hidden, false);
  assertEquals(harness.unavailable.hidden, true);
  assertEquals(harness.state(), { pricingScheduled: true, shownStep: 0 });
});

Deno.test("known access failures always enter the terminal unavailable state", async () => {
  const cases = [
    [401, "INVALID_INTAKE_TOKEN"],
    [403, "INTAKE_ACCESS_INTERRUPTED"],
    [410, "INTAKE_ACCESS_EXPIRED"],
    [410, "INTAKE_ACCESS_CANCELLED"],
  ] as const;

  for (const [status, code] of cases) {
    const harness = buildHarness(() => response(status, { ok: false, code }));
    await harness.inspect();
    assertEquals(harness.loading.hidden, true, code);
    assertEquals(harness.workspace.hidden, true, code);
    assertEquals(harness.unavailable.hidden, false, code);
  }
});

Deno.test("500 and 503 failures cannot leave the spinner active", async () => {
  for (const status of [500, 503]) {
    const harness = buildHarness(() => response(status, {
      ok: false,
      code: "INTAKE_INSPECT_FAILED",
      message: "SQL stack and internal identifier",
    }));
    await harness.inspect();
    assertEquals(harness.loading.hidden, true, String(status));
    assertEquals(harness.workspace.hidden, true, String(status));
    assertEquals(harness.unavailable.hidden, false, String(status));
    assertEquals(harness.unavailableMessage.textContent, "De intake kon tijdelijk niet worden geladen. Probeer later opnieuw.");
  }
});

Deno.test("network rejection enters the terminal unavailable state", async () => {
  const harness = buildHarness(() => Promise.reject(new TypeError("network details")));
  await harness.inspect();
  assertEquals(harness.loading.hidden, true);
  assertEquals(harness.workspace.hidden, true);
  assertEquals(harness.unavailable.hidden, false);
});

Deno.test("the 15 second abort enters the terminal unavailable state", async () => {
  const harness = buildHarness((_action, _data, signal) => {
    if (signal.aborted) return Promise.reject(new DOMException("Aborted", "AbortError"));
    return new Promise(() => {});
  }, true);
  await harness.inspect();
  assertEquals(harness.loading.hidden, true);
  assertEquals(harness.workspace.hidden, true);
  assertEquals(harness.unavailable.hidden, false);
});

Deno.test("terminal errors never expose tokens or backend details", async () => {
  const secretToken = token;
  const harness = buildHarness(() => response(503, {
    ok: false,
    code: "INTAKE_INSPECT_FAILED",
    message: `${secretToken} public.inspect_quote_request_intake_details_v5 SQL stacktrace`,
  }));
  await harness.inspect();
  const visibleMessage = harness.unavailableMessage.textContent;
  assertFalse(visibleMessage.includes(secretToken));
  assertFalse(/sql|rpc|supabase|stack|inspect_quote_request/i.test(visibleMessage));
  assertStringIncludes(visibleMessage, "tijdelijk niet worden geladen");
});