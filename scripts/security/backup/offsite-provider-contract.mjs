export const OFFSITE_BACKUP_CONTRACT = Object.freeze({
  contract_version: "1.0.0",
  implementation_status: "NOT_IMPLEMENTED",
  network_transport_implemented: false,
  provider_dependency: null,
  operations: Object.freeze({
    upload_encrypted_artifact: Object.freeze({ input: ["backup_id", "encrypted_artifact_filename", "encrypted_artifact_sha256"], output: ["immutable_artifact_reference"] }),
    upload_manifest: Object.freeze({ input: ["backup_id", "manifest_sha256"], output: ["immutable_manifest_reference"] }),
    verify_remote_checksum: Object.freeze({ input: ["immutable_artifact_reference", "encrypted_artifact_sha256"], output: ["verified", "verified_at"] }),
    read_retention_metadata: Object.freeze({ input: ["backup_id"], output: ["retention_until", "retention_locked"] }),
    delete_after_retention: Object.freeze({ input: ["backup_id", "retention_until", "separate_owner_approval_reference"], output: ["deletion_evidence_reference"] }),
  }),
  constraints: Object.freeze([
    "encrypted artifact only",
    "manifest contains no credentials",
    "deletion denied before retention expiry",
    "deletion requires separate OWNER approval",
    "no provider adapter or network endpoint in P0-6B",
  ]),
});