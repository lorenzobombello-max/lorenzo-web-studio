import assert from "node:assert/strict";
import { dossier006DeadlineClient } from "./deadline.ts";
import { sweepPreviewDeadlines } from "../_shared/website-project-preview-cleanup.ts";

Deno.test("scheduled sweep uses scoped authority for every RPC and deletes only authorized paths", async () => {
  const buildId = "22222222-2222-4222-8222-222222222222";
  const otherPath = "33333333-3333-4333-8333-333333333333/index.html";
  const objects = new Set([`${buildId}/index.html`, otherPath]);
  const calls: string[] = [];
  const client = dossier006DeadlineClient({
    rpc: async (name, args) => {
      calls.push(name);
      assert.match(name, /_dossier006_v1$/);
      if (name.startsWith("expire_")) return { data: 1, error: null };
      if (name.includes("cleanup_candidates")) return { data: [buildId], error: null };
      assert.equal(args.p_build_id, buildId);
      return { data: name.includes("storage_paths") ? [`${buildId}/index.html`] : true, error: null };
    },
  });
  assert.deepEqual(await sweepPreviewDeadlines(client, {
    remove: async (paths) => {
      paths.forEach((path) => objects.delete(path));
      return { error: null };
    },
  }), { expired: 1, cleanupChecked: 1 });
  assert.deepEqual([...objects], [otherPath]);
  assert.equal(calls.length, 4);
  assert.throws(() => client.rpc("arbitrary_rpc", {}), /AUTHORITY_INVALID/);
});
