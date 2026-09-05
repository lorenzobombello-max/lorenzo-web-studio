import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";
import { verifyActivationArtifacts } from "./storage-backup-s3-minimum-authority.mjs";

const root = new URL("../../../", import.meta.url);

export async function runLocalVerification(activationEvidence = {}) {
  const [candidateSql, rollbackSql] = await Promise.all([
    readFile(new URL("supabase/migrations-candidates/p0_6e6b_storage_backup_reader_rls.sql", root), "utf8"),
    readFile(new URL("supabase/migrations-candidates/p0_6e6b_storage_backup_reader_rls_rollback.sql", root), "utf8"),
  ]);
  return verifyActivationArtifacts({ candidateSql, rollbackSql, activationEvidence });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  runLocalVerification()
    .then((result) => {
      process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
      if (!result.structureValid) process.exitCode = 1;
    })
    .catch((error) => {
      process.stderr.write(`${JSON.stringify({ structureValid: false, error: { code: error?.code || "P0_6E6B_VERIFICATION_FAILED" } })}\n`);
      process.exitCode = 1;
    });
}