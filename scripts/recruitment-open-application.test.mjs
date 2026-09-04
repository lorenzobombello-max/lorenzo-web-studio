import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { OPEN_APPLICATION_INTEREST_AREAS, openApplicationFormData, submitOpenApplication } from "../assets/js/recruitment-open-application.mjs";

const read = (path)=>readFile(new URL(`../${path}`, import.meta.url), "utf8");

function form() {
  const fields = new FormData();
  for (const [key, value] of Object.entries({
    first_name: "Ada", last_name: "Lovelace", email: "ada@example.test", phone: "",
    interest_area: "Development", motivation: "Ik kan iets betekenen met zorgvuldige software.",
    experience_skills: "TypeScript en API-integraties.", portfolio_url: "https://github.com/example",
    availability: "Volgende maand", privacy_consent: "accepted",
  })) fields.set(key, value);
  fields.set("cv", new File(["%PDF-test"], "cv.pdf", { type: "application/pdf" }));
  return fields;
}

test("open application exposes the exact approved interest areas", ()=>{
  assert.deepEqual(OPEN_APPLICATION_INTEREST_AREAS, ["Webdesign", "Development", "Security", "SEO", "Content", "Administratie", "Sales", "HR", "Finance", "Anders"]);
});

test("open application submission uses only the Recruitment function and multipart body", async ()=>{
  const calls = [];
  const result = await submitOpenApplication(form(), async (url, options)=>{
    calls.push({ url, options });
    return calls.length === 1
      ? { ok: true, json: async()=>({ supabaseUrl: "https://xcsptvntvrizwhskaphr.supabase.co", publishableKey: "public-browser-key" }) }
      : { ok: true, json: async()=>({ ok: true, code: "SUBMITTED" }) };
  });
  assert.equal(result.code, "SUBMITTED");
  assert.equal(calls[1].url, "https://xcsptvntvrizwhskaphr.supabase.co/functions/v1/recruitment-application-submit");
  assert.equal(calls[1].options.method, "POST");
  assert.ok(calls[1].options.body instanceof FormData);
  assert.equal(calls[1].options.body.get("vacancy_id"), "");
  assert.equal(calls[1].options.body.get("privacy_consent"), "accepted");
});

test("public client never stores candidate or capability material", async ()=>{
  const source = await read("assets/js/recruitment-open-application.mjs");
  assert.doesNotMatch(source, /localStorage|sessionStorage|Deno\.env|SUPABASE_SERVICE_ROLE_KEY|APPROVAL_TOKEN_SECRET/i);
  assert.match(source, /new FormData\(form\)/);
});