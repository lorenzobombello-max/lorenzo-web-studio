import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  createRecruitmentPublicationController,
  createRecruitmentVacancyController,
  executeOperatorRecruitmentRequest,
  initializeOperatorRecruitment,
  recruitmentPublicationRequest,
  recruitmentVacancyCreateRequest,
  recruitmentVacancyStatusRequest,
  recruitmentVacancyUpdateRequest,
} from "../assets/js/operator-recruitment.mjs";

const vacancyId = "a1800000-0000-4000-8000-000000000081";
const content = {
  title: "Synthetic QA engineer",
  slug: "synthetic-qa-engineer",
  department: "Quality",
  location: "Antwerpen",
  employment_type: "Voltijds",
  summary: "Synthetic vacature voor lokale tests.",
  description: "Alleen lokale synthetische inhoud.",
  requirements: "Geen echte kandidaatdata.",
};
const vacancy = {
  id: vacancyId,
  ...content,
  status: "DRAFT",
  published_at: null,
  closed_at: null,
  created_at: "2026-09-02T12:00:00.000Z",
  updated_at: "2026-09-02T12:00:00.000Z",
};

async function callsFor(request, data) {
  const calls = [];
  const result = await executeOperatorRecruitmentRequest({ rpc: async (name, parameters)=>{
    calls.push([name, parameters]);
    return { data, error: null };
  } }, request);
  return { calls, result };
}

test("dedicated Recruitment module uses exact narrow caller-JWT RPCs", async ()=>{
  assert.deepEqual((await callsFor({ action: "list_recruitment_vacancies" }, [])).calls, [["list_owner_recruitment_vacancies_v1", {}]]);
  assert.deepEqual((await callsFor({ action: "get_recruitment_publication_state" }, { enabled: false })).calls, [["get_public_recruitment_publication_state_v1", {}]]);
  assert.deepEqual((await callsFor(recruitmentPublicationRequest(true), { enabled: true })).calls, [["set_recruitment_publication_enabled_v1", { p_enabled: true }]]);
  assert.deepEqual((await callsFor(recruitmentVacancyCreateRequest(content), { id: vacancyId, slug: content.slug, status: "DRAFT" })).calls, [["create_recruitment_vacancy_v1", {
    p_slug: content.slug,
    p_title: content.title,
    p_department: content.department,
    p_location: content.location,
    p_employment_type: content.employment_type,
    p_summary: content.summary,
    p_description: content.description,
    p_requirements: content.requirements,
  }]]);
  assert.deepEqual((await callsFor(recruitmentVacancyUpdateRequest(vacancyId, content), { id: vacancyId, slug: content.slug, status: "DRAFT" })).calls[0][0], "update_recruitment_vacancy_v1");
  assert.deepEqual((await callsFor(recruitmentVacancyStatusRequest(vacancyId, "PUBLISHED"), { id: vacancyId, slug: content.slug, status: "PUBLISHED", published_at: "2026-09-02T12:00:00.000Z", closed_at: null })).calls, [["set_recruitment_vacancy_status_v1", { p_vacancy_id: vacancyId, p_status: "PUBLISHED" }]]);
});

test("Recruitment authorization failure fast-locks through the generic callback", async ()=>{
  const failures = [];
  await assert.rejects(()=>executeOperatorRecruitmentRequest({ rpc: async()=>({ data: null, error: { code: "42501", message: "RECRUITMENT_OWNER_REQUIRED" } }) }, { action: "list_recruitment_vacancies" }, { onAuthorizationFailure: (error)=>failures.push(error.message) }));
  assert.deepEqual(failures, ["RECRUITMENT_OWNER_REQUIRED"]);
});

test("Recruitment controllers dispose pending work without later state or DOM callbacks", async ()=>{
  let resolveVacancies;
  let resolvePublication;
  const vacancyRenders = [];
  const publicationRenders = [];
  const vacancyController = createRecruitmentVacancyController({
    execute: ()=>new Promise((resolve)=>{ resolveVacancies = resolve; }),
    onChange: (state)=>vacancyRenders.push(state),
  });
  const publicationController = createRecruitmentPublicationController({
    execute: ()=>new Promise((resolve)=>{ resolvePublication = resolve; }),
    onChange: (state)=>publicationRenders.push(state),
  });
  const vacancyPending = vacancyController.refresh();
  const publicationPending = publicationController.refresh();
  vacancyController.dispose();
  publicationController.dispose();
  resolveVacancies([vacancy]);
  resolvePublication({ enabled: true });
  assert.equal(await vacancyPending, false);
  assert.equal(await publicationPending, false);
  assert.equal(vacancyRenders.length, 1);
  assert.equal(publicationRenders.length, 1);
  assert.equal(await vacancyController.refresh(), false);
  assert.equal(await publicationController.refresh(), false);
});

test("Recruitment initializer rejects browser identity that is not owner before any RPC", ()=>{
  let rpcCalls = 0;
  const root = { getElementById: (id)=>id === "recruitmentVacancyList" ? { dataset: {} } : null };
  assert.throws(()=>initializeOperatorRecruitment(root, { rpc() { rpcCalls += 1; } }, { role: "admin" }), /RECRUITMENT_OWNER_REQUIRED/);
  assert.equal(rpcCalls, 0);
});

test("Recruitment module has no Website SDF mixed-gateway or local-only dependency", async ()=>{
  const source = await readFile(new URL("../assets/js/operator-recruitment.mjs", import.meta.url), "utf8");
  assert.doesNotMatch(source, /commercial-operator-command|callCommercialOperator|recruitment-public|application-dossier|sdf-qualification|Website|SDF/);
  assert.doesNotMatch(source, /localhost|127\.0\.0\.1|Mailpit|Playwright|SERVICE_ROLE|JWT_SECRET/);
  assert.match(source, /new AbortController\(\)/);
  assert.match(source, /listenerController\.abort\(\)/);
});
