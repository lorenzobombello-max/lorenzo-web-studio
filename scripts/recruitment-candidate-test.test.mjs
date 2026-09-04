import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  executeRecruitmentTestRequest,
  recruitmentCandidateCreateRequest,
  recruitmentTestReviewRequest,
} from "../assets/js/operator-recruitment-tests.mjs";
import { candidateTestResponse, createCandidateTestClient } from "../assets/js/recruitment-candidate-test.mjs";

const candidateId = "a1800000-0000-4000-8000-000000000091";
const testId = "a1800000-0000-4000-8000-000000000092";
const assignmentId = "a1800000-0000-4000-8000-000000000093";
const token = "a".repeat(64);

test("owner invitation uses one authenticated worker and review keeps its narrow RPC", async ()=>{
  const calls = [];
  const client = {
    functions: { invoke: async (name, parameters)=>{ calls.push(["function", name, parameters]); return { data: { ok: true, selection_count: 5 }, error: null }; } },
    rpc: async (name, parameters)=>{ calls.push(["rpc", name, parameters]); return { data: {}, error: null }; },
  };
  await executeRecruitmentTestRequest(client, recruitmentCandidateCreateRequest({ name: "Synthetic Kandidaat", email: "TEST@EXAMPLE.INVALID", test_profile: "Development" }));
  await executeRecruitmentTestRequest(client, recruitmentTestReviewRequest(assignmentId, "Heldere lokale beoordeling."));
  assert.deepEqual(calls, [
    ["function", "recruitment-candidate-invitation", { body: { name: "Synthetic Kandidaat", email: "test@example.invalid", test_profile: "Development" } }],
    ["rpc", "review_recruitment_candidate_test_v1", { p_assignment_id: assignmentId, p_review_notes: "Heldere lokale beoordeling." }],
  ]);
});

test("candidate capability client sends only token and assignment answers to dedicated RPCs", async ()=>{
  const calls = [];
  const assessment = {
    assignment_id: assignmentId, candidate_id: candidateId, candidate_name: "Synthetic Kandidaat",
    test_profile: "Development",
    tests: ["API", "DATA", "DEBUG", "TEST"].map((suffix)=>({ test_code: `TEST-DEV-${suffix}`, title: suffix, instructions: "Beantwoord alles.", questions: [{ id: "q1", label: "Vraag" }] })),
    status: "BEZIG",
    draft_answers: {}, submitted_answers: null, started_at: "2026-09-04T10:00:00Z", submitted_at: null,
  };
  const fetchImpl = async (url, options)=>{
    calls.push([url, JSON.parse(options.body), options.headers]);
    return { ok: true, json: async ()=>url.endsWith("get_recruitment_candidate_test_v1") ? assessment : { status: "BEZIG" } };
  };
  const client = createCandidateTestClient({ fetchImpl, token, config: { supabaseUrl: "https://xcsptvntvrizwhskaphr.supabase.co", publishableKey: "public-browser-key" } });
  assert.equal((await client.load()).candidate_id, candidateId);
  await client.save({ q1: "Concept" });
  await client.submit({ q1: "Definitief" });
  assert.deepEqual(calls.map(([url])=>url.split("/").at(-1)), ["get_recruitment_candidate_test_v1", "save_recruitment_candidate_test_v1", "submit_recruitment_candidate_test_v1"]);
  assert.deepEqual(calls.map(([, body])=>body), [
    { p_access_token: token },
    { p_access_token: token, p_answers: { q1: "Concept" } },
    { p_access_token: token, p_answers: { q1: "Definitief" } },
  ]);
  assert.ok(calls.every(([, , headers])=>headers.apikey === "public-browser-key"));
});

test("candidate response rejects expanded or malformed authority data", ()=>{
  assert.throws(()=>candidateTestResponse({ status: "BEZIG", questions: [] }), /INVALID_CANDIDATE_TEST_RESPONSE/);
  assert.throws(()=>createCandidateTestClient({ token: "short", config: {} }), /CANDIDATE_TEST_UNAVAILABLE/);
});

test("candidate room is isolated and never persists or query-transmits its capability", async ()=>{
  const [source, html] = await Promise.all([
    readFile(new URL("../assets/js/recruitment-candidate-test.mjs", import.meta.url), "utf8"),
    readFile(new URL("../recruitment/test/index.html", import.meta.url), "utf8"),
  ]);
  assert.match(source, /location\.hash/);
  assert.match(source, /history\.replaceState/);
  assert.doesNotMatch(source, /localStorage|sessionStorage|document\.cookie|\?token=|operator-auth/);
  assert.match(html, /noindex, nofollow/);
  assert.doesNotMatch(html, /operator\/|dashboard|vacature|sollicitatie/i);
});