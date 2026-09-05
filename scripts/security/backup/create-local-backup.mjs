import { createLocalBackup, decodeEncryptionKey, parseArguments } from "./backup-foundation.mjs";

try {
  const args = parseArguments(process.argv.slice(2));
  const retentionDays = Number(args["retention-days"]);
  if (!Number.isInteger(retentionDays) || retentionDays < 1) throw Object.assign(new Error(), { code: "RETENTION_DAYS_INVALID" });
  const result = await createLocalBackup({
    source: {
      environment: args.environment,
      host: args.host,
      port: args.port,
      database: args.database,
      user: args.user,
      projectReference: args["source-project-reference"],
    },
    outputDirectory: args.output,
    encryptionKey: decodeEncryptionKey(process.env.LWS_LOCAL_BACKUP_ENCRYPTION_KEY_B64),
    encryptionKeyReference: args["key-reference"],
    databasePassword: process.env.LWS_LOCAL_BACKUP_DB_PASSWORD,
    retentionUntil: new Date(Date.now() + retentionDays * 86400000),
    schemaMigrationReference: args["schema-migration-reference"],
    logger: (event) => process.stdout.write(`${JSON.stringify(event)}\n`),
  });
  process.stdout.write(`${JSON.stringify({ event: "backup_package_ready", backup_id: result.manifest.backup_id, manifest: result.manifestPath })}\n`);
} catch (error) {
  process.stderr.write(`${JSON.stringify({ event: "backup_failed", code: error?.code || "BACKUP_FAILED" })}\n`);
  process.exitCode = 1;
}