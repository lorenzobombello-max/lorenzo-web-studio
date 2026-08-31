import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

test("Pages artifact allowlist includes every Website intake module", async () => {
  const source = await readFile(new URL("./prepare-pages-dist.ps1", import.meta.url), "utf8");
  assert.match(source, /"pages\/intake\.html"/);
  assert.match(source, /"assets\/js\/intake\.js"/);
  assert.match(source, /"assets\/js\/intake-customer-context\.js"/);
  assert.match(source, /"operator\/dashboard\/index\.html"/);
});