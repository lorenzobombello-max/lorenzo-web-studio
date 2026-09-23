import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  buildWebsiteProjectPreviewArtifactManifest,
  readWebsiteProjectPreviewArtifactFinalBytes,
  WebsiteProjectPreviewArtifactManifestError,
} from "./website-project-preview-artifact-manifest.ts";

async function tempTree(
  build: (root: string) => Promise<void>,
): Promise<string> {
  const root = await Deno.makeTempDir({ prefix: "lws-artifact-manifest-" });
  await build(root);
  return root;
}

async function cleanup(root: string) {
  await Deno.remove(root, { recursive: true });
}

Deno.test("accepts a legitimate multi-file static build with no rejections", async () => {
  const root = await tempTree(async (dir) => {
    await Deno.mkdir(`${dir}/_astro`, { recursive: true });
    await Deno.writeTextFile(`${dir}/index.html`, "<html><body>hi</body></html>");
    await Deno.writeTextFile(`${dir}/404.html`, "<html><body>404</body></html>");
    await Deno.writeTextFile(`${dir}/robots.txt`, "User-agent: *\n");
    await Deno.writeTextFile(`${dir}/_astro/style.css`, "body{}");
  });
  try {
    const manifest = await buildWebsiteProjectPreviewArtifactManifest(root);
    assertEquals(manifest.rejected, []);
    assertEquals(manifest.accepted.length, 4);
    const index = manifest.accepted.find((entry) => entry.path === "index.html");
    assertEquals(index?.contentType, "text/html; charset=utf-8");
    assertEquals(typeof index?.sha256, "string");
    assertEquals(index?.sha256.length, 64);
    const css = manifest.accepted.find((entry) => entry.path === "_astro/style.css");
    assertEquals(css?.contentType, "text/css; charset=utf-8");
  } finally {
    await cleanup(root);
  }
});

Deno.test("rejects a file symlink escaping the build root, without exposing its target", async () => {
  const outside = await Deno.makeTempDir({ prefix: "lws-artifact-outside-" });
  await Deno.writeTextFile(`${outside}/secret.txt`, "TOP-SECRET-HOST-FILE");
  const root = await tempTree(async (dir) => {
    await Deno.writeTextFile(`${dir}/index.html`, "<html><body>hi</body></html>");
    await Deno.symlink(`${outside}/secret.txt`, `${dir}/evil-symlink.txt`);
  });
  try {
    const manifest = await buildWebsiteProjectPreviewArtifactManifest(root);
    assertEquals(manifest.rejected, [
      { path: "evil-symlink.txt", reason: "SYMLINK_REJECTED" },
    ]);
    assertEquals(
      manifest.accepted.some((entry) => entry.path === "evil-symlink.txt"),
      false,
    );
  } finally {
    await cleanup(root);
    await cleanup(outside);
  }
});

Deno.test("rejects a directory symlink escaping the build root without ever walking into it", async () => {
  const outside = await Deno.makeTempDir({ prefix: "lws-artifact-outside-dir-" });
  await Deno.writeTextFile(`${outside}/secret.txt`, "TOP-SECRET-HOST-FILE");
  const root = await tempTree(async (dir) => {
    await Deno.writeTextFile(`${dir}/index.html`, "<html><body>hi</body></html>");
    await Deno.symlink(outside, `${dir}/evil-dir-symlink`, { type: "dir" });
  });
  try {
    const manifest = await buildWebsiteProjectPreviewArtifactManifest(root);
    assertEquals(manifest.rejected, [
      { path: "evil-dir-symlink", reason: "SYMLINK_REJECTED" },
    ]);
    // Proves the symlinked directory's contents were never read/exposed.
    assertEquals(
      manifest.accepted.some((entry) => entry.path.includes("secret.txt")),
      false,
    );
  } finally {
    await cleanup(root);
    await cleanup(outside);
  }
});

Deno.test("rejects an individual file over the per-file size limit", async () => {
  const root = await tempTree(async (dir) => {
    await Deno.writeTextFile(`${dir}/index.html`, "<html><body>hi</body></html>");
    await Deno.writeFile(`${dir}/huge.bin`, new Uint8Array(2048));
  });
  try {
    const manifest = await buildWebsiteProjectPreviewArtifactManifest(root, {
      maxFileBytes: 1024,
      maxTotalBytes: 50 * 1024 * 1024,
      maxFileCount: 500,
    });
    assertEquals(manifest.rejected, [
      { path: "huge.bin", reason: "FILE_TOO_LARGE" },
    ]);
  } finally {
    await cleanup(root);
  }
});

Deno.test("fails closed on total build size exceeding the aggregate limit", async () => {
  const root = await tempTree(async (dir) => {
    await Deno.writeFile(`${dir}/a.bin`, new Uint8Array(600));
    await Deno.writeFile(`${dir}/b.bin`, new Uint8Array(600));
  });
  try {
    await assertRejects(
      () =>
        buildWebsiteProjectPreviewArtifactManifest(root, {
          maxFileBytes: 1000,
          maxTotalBytes: 1000,
          maxFileCount: 500,
        }),
      WebsiteProjectPreviewArtifactManifestError,
      "TOTAL_SIZE_EXCEEDED",
    );
  } finally {
    await cleanup(root);
  }
});

Deno.test("fails closed when the accepted file count exceeds the configured maximum", async () => {
  const root = await tempTree(async (dir) => {
    for (let index = 0; index < 5; index += 1) {
      await Deno.writeTextFile(`${dir}/file-${index}.txt`, "x");
    }
  });
  try {
    await assertRejects(
      () =>
        buildWebsiteProjectPreviewArtifactManifest(root, {
          maxFileBytes: 1024,
          maxTotalBytes: 1024 * 1024,
          maxFileCount: 3,
        }),
      WebsiteProjectPreviewArtifactManifestError,
      "TOO_MANY_FILES",
    );
  } finally {
    await cleanup(root);
  }
});

Deno.test("blocks every SVG asset by extension while the rest of the build still passes", async () => {
  const root = await tempTree(async (dir) => {
    await Deno.writeTextFile(`${dir}/index.html`, "<html><body>hi</body></html>");
    await Deno.writeTextFile(`${dir}/favicon.svg`, "<svg><script>alert(1)</script></svg>");
  });
  try {
    const manifest = await buildWebsiteProjectPreviewArtifactManifest(root);
    assertEquals(manifest.rejected, [
      { path: "favicon.svg", reason: "ASSET_TYPE_BLOCKED" },
    ]);
    assertEquals(
      manifest.accepted.some((entry) => entry.path === "favicon.svg"),
      false,
    );
    assertEquals(
      manifest.accepted.some((entry) => entry.path === "index.html"),
      true,
    );
  } finally {
    await cleanup(root);
  }
});

Deno.test("sanitizes HTML instead of blocking it - safe AND still functional", async () => {
  const root = await tempTree(async (dir) => {
    await Deno.writeTextFile(
      `${dir}/index.html`,
      '<html><body onclick="steal()">hi<script>alert(1)</script></body></html>',
    );
  });
  try {
    const manifest = await buildWebsiteProjectPreviewArtifactManifest(root);
    assertEquals(manifest.rejected, []);
    const bytes = await readWebsiteProjectPreviewArtifactFinalBytes(
      root,
      "index.html",
    );
    const text = new TextDecoder().decode(bytes);
    assertEquals(text.includes("<script>"), false);
    assertEquals(text.includes("onclick"), false);
    // The visible page content is preserved - the file was sanitized, not
    // just discarded or blocked outright.
    assertEquals(text.includes("hi"), true);
    const index = manifest.accepted.find((entry) => entry.path === "index.html");
    const hash = await crypto.subtle.digest("SHA-256", Uint8Array.from(bytes).buffer);
    const hex = [...new Uint8Array(hash)].map((b) => b.toString(16).padStart(2, "0")).join("");
    assertEquals(index?.sha256, hex);
  } finally {
    await cleanup(root);
  }
});

Deno.test("rejects HTML containing an irreparably dangerous construct (e.g. an iframe) as MARKUP_UNSAFE", async () => {
  const root = await tempTree(async (dir) => {
    await Deno.writeTextFile(
      `${dir}/index.html`,
      "<html><body><iframe src='https://evil.test'></iframe></body></html>",
    );
  });
  try {
    const manifest = await buildWebsiteProjectPreviewArtifactManifest(root);
    assertEquals(manifest.rejected, [
      { path: "index.html", reason: "MARKUP_UNSAFE" },
    ]);
  } finally {
    await cleanup(root);
  }
});

Deno.test("readWebsiteProjectPreviewArtifactFinalBytes independently re-derives bytes and re-applies every check", async () => {
  const outside = await Deno.makeTempDir({ prefix: "lws-artifact-reread-outside-" });
  await Deno.writeTextFile(`${outside}/secret.txt`, "TOP-SECRET-HOST-FILE");
  const root = await tempTree(async (dir) => {
    await Deno.writeTextFile(`${dir}/index.html`, "<html><body>hi</body></html>");
    await Deno.symlink(`${outside}/secret.txt`, `${dir}/evil-symlink.txt`);
    await Deno.writeTextFile(`${dir}/favicon.svg`, "<svg></svg>");
  });
  try {
    const bytes = await readWebsiteProjectPreviewArtifactFinalBytes(root, "index.html");
    assertEquals(new TextDecoder().decode(bytes).includes("hi"), true);
    await assertRejects(
      () => readWebsiteProjectPreviewArtifactFinalBytes(root, "evil-symlink.txt"),
      WebsiteProjectPreviewArtifactManifestError,
      "SYMLINK_REJECTED",
    );
    await assertRejects(
      () => readWebsiteProjectPreviewArtifactFinalBytes(root, "favicon.svg"),
      WebsiteProjectPreviewArtifactManifestError,
      "ASSET_TYPE_BLOCKED",
    );
  } finally {
    await cleanup(root);
    await cleanup(outside);
  }
});
