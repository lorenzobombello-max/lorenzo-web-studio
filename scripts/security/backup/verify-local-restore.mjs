import { decodeEncryptionKey, parseArguments, verifyLocalRestore } from "./backup-foundation.mjs";

try {
  const args = parseArguments(process.argv.slice(2));
  const manifest = await verifyLocalRestore({
    packageDirectory: args.package,
    manifestFilename: args.manifest,
    target: {
      environment: args.environment,
      host: args.host,
      port: args.port,
      database: args.database,
      user: args.user,
      projectReference: args["target-project-reference"],
    },
    encryptionKey: decodeEncryptionKey(process.env.LWS_LOCAL_BACKUP_ENCRYPTION_KEY_B64),
    encryptionKeyReference: args["key-reference"],
    databasePassword: process.env.LWS_LOCAL_BACKUP_DB_PASSWORD,
    logger: (event) => process.stdout.write(`${JSON.stringify(event)}\n`),
  });
  process.stdout.write(`${JSON.stringify({ event: "restore_verification_complete", backup_id: manifest.backup_id, verification_status: manifest.verification_status })}\n`);
} catch (error) {
  process.stderr.write(`${JSON.stringify({ event: "restore_verification_failed", code: error?.code || "RESTORE_FAILED" })}\n`);
  process.exitCode = 1;
}