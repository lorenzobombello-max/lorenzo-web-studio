import { loadSharedPublicRecruitmentPublicationState } from "./recruitment-publication.js";

const PUBLIC_VACANCY_RPC = "list_public_recruitment_vacancies_v1";
const PUBLIC_VACANCY_KEYS = ["title", "slug", "department", "location", "employment_type", "summary", "description", "requirements", "published_at"];

function exactKeys(value, keys) {
  return value && typeof value === "object" && !Array.isArray(value)
    && Object.keys(value).length === keys.length && keys.every((key)=>Object.hasOwn(value, key));
}

export function publicVacanciesResponse(value) {
  if (!Array.isArray(value)) throw new Error("INVALID_PUBLIC_VACANCIES_RESPONSE");
  for (const vacancy of value) {
    if (!exactKeys(vacancy, PUBLIC_VACANCY_KEYS)
      || !PUBLIC_VACANCY_KEYS.slice(0, 8).every((key)=>typeof vacancy[key] === "string" && vacancy[key].trim().length > 0)
      || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(vacancy.slug)
      || typeof vacancy.published_at !== "string" || !Number.isFinite(Date.parse(vacancy.published_at))) {
      throw new Error("INVALID_PUBLIC_VACANCIES_RESPONSE");
    }
  }
  return value;
}

export function groupPublicVacancies(vacancies) {
  const grouped = new Map();
  for (const vacancy of publicVacanciesResponse(vacancies)) {
    if (!grouped.has(vacancy.department)) grouped.set(vacancy.department, []);
    grouped.get(vacancy.department).push(vacancy);
  }
  return [...grouped.entries()]
    .sort(([left], [right])=>left.localeCompare(right, "nl-BE"))
    .map(([department, items])=>({ department, items }));
}

function publicConfig(value) {
  const supabaseUrl = String(value?.supabaseUrl || "");
  const publishableKey = String(value?.publishableKey || "");
  if (supabaseUrl !== "https://xcsptvntvrizwhskaphr.supabase.co"
    || !publishableKey || /service_role|secret/i.test(publishableKey)) throw new Error("PUBLIC_RECRUITMENT_CONFIG_INVALID");
  return { supabaseUrl, publishableKey };
}

export async function loadPublicVacancies(fetchImpl = fetch) {
  const configResponse = await fetchImpl("/assets/config/public-recruitment.json", {
    cache: "no-store",
    credentials: "same-origin",
    headers: { Accept: "application/json" },
  });
  if (!configResponse.ok) throw new Error("PUBLIC_RECRUITMENT_UNAVAILABLE");
  const config = publicConfig(await configResponse.json());
  const response = await fetchImpl(`${config.supabaseUrl}/rest/v1/rpc/${PUBLIC_VACANCY_RPC}`, {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
      apikey: config.publishableKey,
    },
    body: "{}",
  });
  if (!response.ok) throw new Error("PUBLIC_RECRUITMENT_UNAVAILABLE");
  return publicVacanciesResponse(await response.json());
}

export function redirectUnavailablePublicRecruitmentRoute(location) {
  if (location?.pathname !== "/werken-bij/" && location?.pathname !== "/werken-bij") return false;
  location.replace("/");
  return true;
}

export function createPublicRecruitmentController({ loadState, load, redirect = ()=>{}, onChange = ()=>{} }) {
  let state = { status: "idle", groups: [] };
  const update = (next)=>{ state = next; onChange(state); };
  return {
    get state() { return state; },
    async start() {
      update({ status: "checking", groups: [] });
      let publication;
      try {
        publication = await loadState();
      } catch {
        update({ status: "redirecting", groups: [] });
        redirect();
        return false;
      }
      if (!publication.enabled) {
        update({ status: "redirecting", groups: [] });
        redirect();
        return false;
      }
      update({ status: "loading", groups: [] });
      try {
        const groups = groupPublicVacancies(await load());
        update({ status: groups.length ? "ready" : "empty", groups });
        return true;
      } catch {
        update({ status: "error", groups: [] });
        return false;
      }
    },
  };
}

export function renderPublicRecruitment(root, state) {
  const published = root.getElementById("careersPublishedContent");
  const loading = root.getElementById("vacancyLoading");
  const empty = root.getElementById("vacancyEmpty");
  const error = root.getElementById("vacancyError");
  const groups = root.getElementById("vacancyGroups");
  published.hidden = ["checking", "redirecting"].includes(state.status);
  loading.hidden = state.status !== "loading";
  empty.hidden = state.status !== "empty";
  error.hidden = state.status !== "error";
  groups.hidden = state.status !== "ready";
  groups.replaceChildren();
  if (state.status !== "ready") return;
  for (const group of state.groups) {
    const section = root.createElement("section");
    const heading = root.createElement("div");
    const title = root.createElement("h2");
    const count = root.createElement("span");
    const list = root.createElement("div");
    section.className = "vacancy-department";
    heading.className = "vacancy-department__heading";
    title.textContent = group.department;
    count.textContent = `${group.items.length} ${group.items.length === 1 ? "functie" : "functies"}`;
    list.className = "vacancy-list";
    for (const vacancy of group.items) {
      const article = root.createElement("article");
      const vacancyTitle = root.createElement("h3");
      const metadata = root.createElement("p");
      const summary = root.createElement("p");
      const details = root.createElement("details");
      const detailsToggle = root.createElement("summary");
      const detailBody = root.createElement("div");
      article.className = "vacancy-card";
      vacancyTitle.textContent = vacancy.title;
      metadata.className = "vacancy-card__meta";
      metadata.textContent = `${vacancy.location} · ${vacancy.employment_type}`;
      summary.textContent = vacancy.summary;
      detailsToggle.textContent = "Bekijk de functie";
      detailBody.className = "vacancy-card__detail";
      for (const [label, content] of [["Over de functie", vacancy.description], ["Wat we zoeken", vacancy.requirements]]) {
        const block = root.createElement("section");
        const blockTitle = root.createElement("h4");
        const copy = root.createElement("p");
        blockTitle.textContent = label;
        copy.textContent = content;
        block.append(blockTitle, copy);
        detailBody.append(block);
      }
      details.append(detailsToggle, detailBody);
      article.append(vacancyTitle, metadata, summary, details);
      list.append(article);
    }
    heading.append(title, count);
    section.append(heading, list);
    groups.append(section);
  }
}

if (typeof document !== "undefined" && document.getElementById("vacancyGroups")) {
  let controller;
  controller = createPublicRecruitmentController({
    loadState: ()=>loadSharedPublicRecruitmentPublicationState(),
    load: ()=>loadPublicVacancies(),
    redirect: ()=>redirectUnavailablePublicRecruitmentRoute(window.location),
    onChange: (state)=>renderPublicRecruitment(document, state),
  });
  void controller.start();
}
