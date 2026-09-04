import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { executeOpenApplicationRequest, inviteOpenApplicationToTest, openApplicationsResponse, updateOpenApplicationRequest } from "../assets/js/operator-recruitment-applications.mjs";

const applicationId = "fa200000-0000-4000-8000-000000000001";
const candidateId = "fa300000-0000-4000-8000-000000000001";
const application = { id: applicationId, application_type: "OPEN_SOLLICITATIE", first_name: "Ada", last_name: "Lovelace", email: "ada@example.test", phone: null, motivation: "Veilige software.", interest_area: "Development", experience_skills: "TypeScript", portfolio_url: null, availability: "Volgende maand", cv_storage_path: `applications/${applicationId}/cv.pdf`, workflow_status: "OPEN", linked_test_profile: null, linked_test_candidate_id: null, submitted_at: "2026-09-04T10:00:00Z", updated_at: "2026-09-04T10:00:00Z" };

test("owner projection is exact and labelled open application", ()=>{
  assert.deepEqual(openApplicationsResponse([application]), [application]);
  assert.throws(()=>openApplicationsResponse([{ ...application, contract_id: applicationId }]), /INVALID_OPEN_APPLICATION_RESPONSE/);
});

test("owner actions use only narrow Recruitment RPCs", async ()=>{
  const calls = [];
  const client = { rpc: async (name, parameters)=>{ calls.push([name, parameters]); return { data: name.startsWith("list_") ? [application] : { id: applicationId }, error: null }; } };
  await executeOpenApplicationRequest(client, { action: "list_open_applications" });
  await executeOpenApplicationRequest(client, updateOpenApplicationRequest(applicationId, "BEWAARD", "Development"));
  assert.deepEqual(calls.map(([name])=>name), ["list_owner_recruitment_open_applications_v1", "update_owner_recruitment_open_application_v1"]);
});

test("existing automatic test invitation is reused and linked", async ()=>{
  const calls = [];
  const client = {
    functions: { invoke: async (name, options)=>{ calls.push(["function", name, options]); return { data: { ok: true, candidate_id: candidateId }, error: null }; } },
    rpc: async (name, parameters)=>{ calls.push(["rpc", name, parameters]); return { data: { id: applicationId }, error: null }; },
  };
  await inviteOpenApplicationToTest(client, application, "Development", {});
  assert.equal(calls[0][1], "recruitment-candidate-invitation");
  assert.equal(calls[1][1], "update_owner_recruitment_open_application_v1");
  assert.equal(calls[1][2].p_linked_test_candidate_id, candidateId);
});

test("owner module contains no HR or contract authority", async ()=>{
  const source = await readFile(new URL("../assets/js/operator-recruitment-applications.mjs", import.meta.url), "utf8");
  assert.doesNotMatch(source, /contract|employment|employee|workforce|finance|dossier|sdf/i);
});

test("open application finalizer verifies the SHA from Storage user metadata", async ()=>{
  const migration = await readFile(new URL("../supabase/migrations/20260904130000_add_recruitment_open_applications_v1.sql", import.meta.url), "utf8");
  assert.match(migration, /object\.metadata, object\.user_metadata into v_storage_metadata, v_storage_user_metadata/);
  assert.match(migration, /v_storage_user_metadata->>'sha256'/);
  assert.match(migration, /v_storage_metadata->>'size'/);
  assert.match(migration, /v_storage_metadata->>'mimetype'/);
});

test("owner dashboard exposes the complete open-application review contract", async ()=>{
  const html = await readFile(new URL("../operator/dashboard/index.html", import.meta.url), "utf8");
  for (const id of [
    "recruitmentOpenApplicationList", "recruitmentOpenApplicationMessage", "recruitmentOpenApplicationEmpty",
    "recruitmentOpenApplicationRefresh", "recruitmentOpenApplicationDetailDialog", "recruitmentOpenApplicationDetail",
    "recruitmentOpenApplicationCv", "recruitmentOpenApplicationDetailClose", "recruitmentOpenApplicationProfileDialog",
    "recruitmentOpenApplicationProfileForm", "recruitmentOpenApplicationProfileCancel", "recruitmentOpenApplicationProfileMessage",
  ]) assert.match(html, new RegExp(`id="${id}"`));
  assert.match(html, /OPEN SOLLICITATIE/);
});

test("profile linking does not claim invitation before worker success", async ()=>{
  const source = await readFile(new URL("../assets/js/operator-recruitment-applications.mjs", import.meta.url), "utf8");
  assert.match(source, /update\(selected, selected\.workflow_status, profileForm/);
  assert.match(source, /inviteOpenApplicationToTest[\s\S]*updateOpenApplicationRequest\(application\.id, "UITGENODIGD"/);
});