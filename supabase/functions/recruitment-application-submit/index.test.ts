import { assertEquals } from "jsr:@std/assert@1";
import { finalizationSucceeded } from "./index.ts";

Deno.test("service finalization accepts only the minimal submitted result", () => {
  assertEquals(
    finalizationSucceeded({
      id: "fa100000-0000-4000-8000-000000000001",
      status: "SUBMITTED",
    }, null),
    true,
  );
  assertEquals(
    finalizationSucceeded({
      id: "fa100000-0000-4000-8000-000000000001",
      status: "ACCEPTED",
    }, null),
    false,
  );
});

Deno.test("service finalization rejects RPC errors and malformed results", () => {
  assertEquals(finalizationSucceeded(null, { message: "failed" }), false);
  assertEquals(finalizationSucceeded([], null), false);
  assertEquals(finalizationSucceeded({ status: "SUBMITTED" }, null), false);
});
