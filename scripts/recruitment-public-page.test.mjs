import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { createPublicRecruitmentController, groupPublicVacancies, loadPublicVacancies, publicVacanciesResponse } from "../assets/js/recruitment-public.js";

const root = new URL("../", import.meta.url);
const read = (path)=>readFile(new URL(path, root), "utf8");
const vacancy = (overrides = {})=>({
  title: "Frontend developer",
  slug: "frontend-developer",
  department: "Development",
  location: "Lievegem",
  employment_type: "Voltijds",
  summary: "Bouw heldere digitale ervaringen.",
  description: "Je werkt aan publieke websites en applicaties.",
  requirements: "Je schrijft onderhoudbare HTML, CSS en JavaScript.",
  published_at: "2026-08-30T10:00:00.000Z",
  ...overrides,
});

test("public careers route has the required shell SEO heading and empty states", async ()=>{
  const [html, sitemap] = await Promise.all([read("werken-bij/index.html"), read("sitemap.xml")]);
  assert.match(html, /<link rel="canonical" href="https:\/\/lorenzowebsolutions\.be\/werken-bij\/"/);
  assert.match(html, /<h1 id="careers-title">Werken bij Lorenzo Web Solutions<\/h1>/);
  assert.match(html, /Lorenzo Web Solutions zoekt mensen per specialisatie\. Niet iedereen hoeft alles te kunnen\./);
  assert.match(html, /Momenteel zijn er geen openstaande vacatures\./);
  assert.match(html, /Nieuwe vacatures verschijnen hier zodra er een functie beschikbaar is\./);
  assert.match(html, /Vacatures konden momenteel niet worden geladen\./);
  assert.doesNotMatch(html, /JobPosting|Solliciteer spontaan|type="file"|<form\b|testkamer/i);
  assert.match(sitemap, /<loc>https:\/\/lorenzowebsolutions\.be\/werken-bij\/<\/loc>/);
});

test("public navigation uses one careers label across both site script owners", async ()=>{
  const [html, pages, redesign] = await Promise.all([read("werken-bij/index.html"), read("assets/js/pages.js"), read("assets/js/redesign.js")]);
  assert.match(html, /data-careers-link[^>]*aria-current="page"[^>]*>Werken bij ons<\/a>/);
  for (const source of [pages, redesign]) {
    assert.match(source, /data-careers-link/);
    assert.match(source, /\/werken-bij\//);
    assert.match(source, /Werken bij ons/);
  }
});

test("public vacancy DTO is exact and contains no status or internal metadata", ()=>{
  assert.deepEqual(publicVacanciesResponse([vacancy()]), [vacancy()]);
  for (const invalid of [
    { ...vacancy(), status: "PUBLISHED" },
    { ...vacancy(), operator_id: "a1800000-0000-4000-8000-000000000081" },
    { ...vacancy(), published_at: "invalid" },
    { ...vacancy(), summary: "" },
  ]) assert.throws(()=>publicVacanciesResponse([invalid]), /INVALID_PUBLIC_VACANCIES_RESPONSE/);
});

test("public vacancies group generically by department", ()=>{
  const groups = groupPublicVacancies([
    vacancy({ title: "Security engineer", slug: "security-engineer", department: "Security" }),
    vacancy(),
    vacancy({ title: "Backend developer", slug: "backend-developer" }),
  ]);
  assert.deepEqual(groups.map((group)=>[group.department, group.items.map((item)=>item.title)]), [
    ["Development", ["Frontend developer", "Backend developer"]],
    ["Security", ["Security engineer"]],
  ]);
});

test("public loader calls only the anon public-list RPC", async ()=>{
  const calls = [];
  const result = await loadPublicVacancies(async (url, options)=>{
    calls.push({ url, options });
    if (calls.length === 1) return { ok: true, json: async ()=>({ supabaseUrl: "https://xcsptvntvrizwhskaphr.supabase.co", publishableKey: "sb_publishable_public", callbackUrl: "https://lorenzowebsolutions.be/operator/auth/callback/" }) };
    return { ok: true, json: async ()=>[vacancy()] };
  });
  assert.deepEqual(result, [vacancy()]);
  assert.equal(calls[0].url, "/assets/config/public-recruitment.json");
  assert.equal(calls[1].url, "https://xcsptvntvrizwhskaphr.supabase.co/rest/v1/rpc/list_public_recruitment_vacancies_v1");
  assert.deepEqual(JSON.parse(calls[1].options.body), {});
  assert.equal(calls[1].options.headers.apikey, "sb_publishable_public");
  assert.equal(Object.hasOwn(calls[1].options.headers, "Authorization"), false);
  assert.doesNotMatch(JSON.stringify(calls), /\/rest\/v1\/recruitment_vacancies|list_owner_recruitment|commercial-operator-command|create_recruitment|update_recruitment|set_recruitment/);
});

test("controller covers empty grouped and safe error states", async ()=>{
  const states = [];
  const empty = createPublicRecruitmentController({ load: async ()=>[], onChange: (state)=>states.push(state) });
  assert.equal(await empty.start(), true);
  assert.equal(empty.state.status, "empty");

  const populated = createPublicRecruitmentController({ load: async ()=>[vacancy(), vacancy({ title: "Backend developer", slug: "backend-developer" }), vacancy({ title: "Security engineer", slug: "security-engineer", department: "Security" })] });
  assert.equal(await populated.start(), true);
  assert.deepEqual(populated.state.groups.map((group)=>[group.department, group.items.length]), [["Development", 2], ["Security", 1]]);

  const failed = createPublicRecruitmentController({ load: async ()=>{ throw new Error("private database detail"); } });
  assert.equal(await failed.start(), false);
  assert.deepEqual(failed.state, { status: "error", groups: [] });
  assert.deepEqual(states.map((state)=>state.status), ["loading", "empty"]);
});

test("renderer is textContent-only and responsive CSS has desktop and mobile grids", async ()=>{
  const [script, css] = await Promise.all([read("assets/js/recruitment-public.js"), read("assets/css/recruitment-public.css")]);
  assert.doesNotMatch(script, /innerHTML|insertAdjacentHTML/);
  assert.match(script, /root\.createElement\("details"\)/);
  assert.match(script, /copy\.textContent = content/);
  assert.match(css, /\.vacancy-list \{[^}]*grid-template-columns:repeat\(2,minmax\(0,1fr\)\)/);
  assert.match(css, /@media \(max-width:860px\)[\s\S]*\.vacancy-list \{ grid-template-columns:1fr; \}/);
  assert.match(css, /overflow-wrap:anywhere/);
});
