const MAX_SNAPSHOT_BYTES = 32 * 1024 * 1024;

export type GitHubSnapshotDigestEntry = Readonly<{
  path: string;
  mode: string;
  type: "blob";
  content: Uint8Array;
}>;

export class GitHubSnapshotDigestError extends Error {
  constructor(readonly code: "SNAPSHOT_INVALID" | "DIGEST_CALCULATE") {
    super(code);
    this.name = "GitHubSnapshotDigestError";
  }
}

function exactKeys(value: object, keys: readonly string[]): boolean {
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  return actual.length === expected.length &&
    actual.every((key, index) => key === expected[index]);
}

function hasControlCharacter(value: string): boolean {
  return [...value].some((character) => {
    const code = character.charCodeAt(0);
    return code <= 31 || code === 127;
  });
}

function validPath(path: string): boolean {
  return path.length > 0 && path.length <= 1024 && !path.startsWith("/") &&
    !path.includes("\\") && !hasControlCharacter(path) &&
    !path.split("/").includes("..") &&
    path !== ".lws/project.json";
}

function hex(bytes: ArrayBuffer): string {
  return [...new Uint8Array(bytes)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

async function sha256(value: Uint8Array): Promise<string> {
  try {
    return hex(await crypto.subtle.digest("SHA-256", Uint8Array.from(value)));
  } catch {
    throw new GitHubSnapshotDigestError("DIGEST_CALCULATE");
  }
}

export async function computeGitHubSnapshotDigest(
  entries: readonly GitHubSnapshotDigestEntry[],
): Promise<string> {
  if (!Array.isArray(entries) || entries.length === 0) {
    throw new GitHubSnapshotDigestError("SNAPSHOT_INVALID");
  }
  const paths = new Set<string>();
  let totalBytes = 0;
  const manifest: string[] = [];
  for (const entry of entries) {
    if (
      !entry || typeof entry !== "object" || Array.isArray(entry) ||
      !exactKeys(entry, ["path", "mode", "type", "content"]) ||
      typeof entry.path !== "string" || typeof entry.mode !== "string" ||
      !validPath(entry.path) || paths.has(entry.path) ||
      !/^[0-7]{6}$/.test(entry.mode) || entry.type !== "blob" ||
      !(entry.content instanceof Uint8Array)
    ) throw new GitHubSnapshotDigestError("SNAPSHOT_INVALID");
    paths.add(entry.path);
    totalBytes += entry.content.byteLength;
    if (totalBytes > MAX_SNAPSHOT_BYTES) {
      throw new GitHubSnapshotDigestError("SNAPSHOT_INVALID");
    }
  }
  for (
    const entry of [...entries].sort((left, right) =>
      left.path.localeCompare(right.path)
    )
  ) {
    manifest.push(
      `${entry.mode}\t${entry.type}\t${await sha256(
        entry.content,
      )}\t${entry.path}`,
    );
  }
  return await sha256(new TextEncoder().encode(`${manifest.join("\n")}\n`));
}
