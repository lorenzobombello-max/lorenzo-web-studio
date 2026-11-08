import assert from "node:assert/strict";
import test from "node:test";
import { verifyProxyNetwork } from "./preview-build-proxy/check-network.mjs";

test("network gate requires direct isolation, npm allowance and non-npm denial", async () => {
  const calls = [];
  await verifyProxyNetwork("isolated-proxy", async (host, port, target) => {
    calls.push([host, port, target]);
    if (!target) throw new Error("blocked");
    return target === "registry.npmjs.org" ? 200 : 403;
  });
  assert.equal(calls.length, 3);
  for (const [direct, npm, forbidden] of [[true, 200, 403], [false, 403, 403], [false, 200, 200]]) {
    await assert.rejects(() => verifyProxyNetwork("proxy", async (_host, _port, target) =>
      target === undefined ? direct : target === "registry.npmjs.org" ? npm : forbidden));
  }
});
