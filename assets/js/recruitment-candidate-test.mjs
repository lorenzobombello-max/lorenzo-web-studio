const TOKEN = /^[0-9a-f]{64}$/;
const STATUS_LABELS = Object.freeze({ BESCHIKBAAR: "Beschikbaar", BEZIG: "Bezig", INGEDIEND: "Ingediend", BEOORDEELD: "Beoordeeld" });

function readToken(location, history) {
  const token = new URLSearchParams(location.hash.slice(1)).get("token") || "";
  history.replaceState(null, "", `${location.pathname}${location.search}`);
  if (!TOKEN.test(token)) throw new Error("CANDIDATE_TEST_UNAVAILABLE");
  return token;
}

function validateConfig(value, pageOrigin) {
  const localPage = /^http:\/\/(?:127\.0\.0\.1|localhost)(?::\d+)?$/.test(pageOrigin || "");
  const allowedUrl = value?.supabaseUrl === "https://xcsptvntvrizwhskaphr.supabase.co"
    || (localPage && /^http:\/\/(?:127\.0\.0\.1|localhost):54321$/.test(value?.supabaseUrl || ""));
  if (!allowedUrl
    || typeof value?.publishableKey !== "string" || !value.publishableKey
    || /service_role|secret/i.test(value.publishableKey)) throw new Error("CANDIDATE_TEST_UNAVAILABLE");
  return value;
}

export function candidateTestResponse(value) {
  const keys = ["assignment_id", "candidate_id", "candidate_name", "test_profile", "tests", "status", "draft_answers", "submitted_answers", "started_at", "submitted_at"];
  if (!value || typeof value !== "object" || Object.keys(value).length !== keys.length || !keys.every((key)=>Object.hasOwn(value, key))
    || !Array.isArray(value.tests) || ![4, 5].includes(value.tests.length)
    || value.tests.some((test)=>typeof test?.test_code !== "string" || typeof test?.title !== "string" || typeof test?.instructions !== "string" || !Array.isArray(test?.questions) || !test.questions.length)
    || !["BEZIG", "INGEDIEND", "BEOORDEELD"].includes(value.status)) throw new Error("INVALID_CANDIDATE_TEST_RESPONSE");
  return value;
}

export function createCandidateTestClient({ fetchImpl = fetch, config, token, pageOrigin }) {
  if (!TOKEN.test(token)) throw new Error("CANDIDATE_TEST_UNAVAILABLE");
  const safeConfig = validateConfig(config, pageOrigin);
  async function call(name, parameters = {}) {
    const response = await fetchImpl(`${safeConfig.supabaseUrl}/rest/v1/rpc/${name}`, {
      method: "POST",
      headers: { Accept: "application/json", "Content-Type": "application/json", apikey: safeConfig.publishableKey },
      body: JSON.stringify({ p_access_token: token, ...parameters }),
    });
    if (!response.ok) throw new Error("CANDIDATE_TEST_REQUEST_FAILED");
    return response.json();
  }
  return Object.freeze({
    load: async ()=>candidateTestResponse(await call("get_recruitment_candidate_test_v1")),
    save: (answers)=>call("save_recruitment_candidate_test_v1", { p_answers: answers }),
    submit: (answers)=>call("submit_recruitment_candidate_test_v1", { p_answers: answers }),
  });
}

function assessmentQuestions(tests) {
  return tests.flatMap((test)=>test.questions.map((question)=>({ ...question, key: `${test.test_code}__${question.id}` })));
}

function answersFrom(form, questions) {
  return Object.fromEntries(questions.map((question)=>[question.key, String(form.elements.namedItem(question.key)?.value || "").trim()]));
}

async function start(root = document) {
  const loading = root.getElementById("candidateTestLoading");
  const unavailable = root.getElementById("candidateTestUnavailable");
  const workspace = root.getElementById("candidateTestWorkspace");
  const form = root.getElementById("candidateTestForm");
  const message = root.getElementById("candidateTestMessage");
  let token;
  try { token = readToken(root.defaultView.location, root.defaultView.history); } catch { loading.hidden = true; unavailable.hidden = false; return; }
  try {
    const configResponse = await fetch("/assets/config/public-recruitment.json", { cache: "no-store", credentials: "same-origin" });
    if (!configResponse.ok) throw new Error();
    const client = createCandidateTestClient({ config: await configResponse.json(), token, pageOrigin: root.defaultView.location.origin });
    let assessment = await client.load();
    root.getElementById("candidateTestName").textContent = assessment.candidate_name;
    root.getElementById("candidateTestCode").textContent = `${assessment.tests.length} tests`;
    root.getElementById("candidateTestTitle").textContent = `${assessment.test_profile} kandidaatassessment`;
    root.getElementById("candidateTestProfile").textContent = assessment.test_profile;
    root.getElementById("candidateTestInstructions").textContent = "Werk alle geselecteerde tests af. U kunt tussentijds opslaan en dient de volledige set één keer definitief in.";
    root.getElementById("candidateTestStatus").textContent = STATUS_LABELS[assessment.status];
    const questions = assessmentQuestions(assessment.tests);
    for (const [index, test] of assessment.tests.entries()) {
      const section = root.createElement("section");
      section.className = "candidate-test-block";
      const sequence = root.createElement("p");
      sequence.className = "eyebrow";
      sequence.textContent = `Test ${index + 1} van ${assessment.tests.length} · ${test.test_code}`;
      const heading = root.createElement("h2");
      heading.textContent = test.title;
      const instructions = root.createElement("p");
      instructions.className = "candidate-instructions";
      instructions.textContent = test.instructions;
      section.append(sequence, heading, instructions);
      for (const question of test.questions) {
        const key = `${test.test_code}__${question.id}`;
        const label = root.createElement("label");
        label.textContent = question.label;
        const field = root.createElement("textarea");
        field.name = key;
        field.rows = 7;
        field.maxLength = 10000;
        field.required = true;
        field.value = assessment.submitted_answers?.[key] || assessment.draft_answers?.[key] || "";
        field.disabled = ["INGEDIEND", "BEOORDEELD"].includes(assessment.status);
        label.append(field);
        section.append(label);
      }
      form.insertBefore(section, root.getElementById("candidateTestActions"));
    }
    const locked = ["INGEDIEND", "BEOORDEELD"].includes(assessment.status);
    root.getElementById("candidateTestSave").hidden = locked;
    root.getElementById("candidateTestSubmit").hidden = locked;
    root.getElementById("candidateTestLocked").hidden = !locked;
    loading.hidden = true;
    workspace.hidden = false;
    form.addEventListener("input", ()=>{ if (!locked) message.textContent = "Niet-opgeslagen wijzigingen"; });
    root.getElementById("candidateTestSave").addEventListener("click", async ()=>{
      try { await client.save(answersFrom(form, questions)); message.textContent = "Antwoorden opgeslagen."; } catch { message.textContent = "Opslaan is niet gelukt."; }
    });
    form.addEventListener("submit", async (event)=>{
      event.preventDefault();
      if (!form.reportValidity() || locked || !confirm("Definitief indienen? Daarna kunt u niets meer wijzigen.")) return;
      try {
        await client.submit(answersFrom(form, questions));
        assessment = await client.load();
        for (const field of form.elements) if (field.tagName === "TEXTAREA") field.disabled = true;
        root.getElementById("candidateTestSave").hidden = true;
        root.getElementById("candidateTestSubmit").hidden = true;
        root.getElementById("candidateTestLocked").hidden = false;
        root.getElementById("candidateTestStatus").textContent = STATUS_LABELS[assessment.status];
        message.textContent = "Test definitief ingediend.";
      } catch { message.textContent = "Indienen is niet gelukt."; }
    });
  } catch {
    loading.hidden = true;
    unavailable.hidden = false;
  }
}

if (typeof document !== "undefined") void start();
