export const OPEN_APPLICATION_INTEREST_AREAS = Object.freeze([
  "Webdesign", "Development", "Security", "SEO", "Content",
  "Administratie", "Sales", "HR", "Finance", "Anders",
]);

const CV_TYPES = new Set([
  "application/pdf",
  "application/msword",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
]);

function publicConfig(value) {
  const supabaseUrl = String(value?.supabaseUrl || "");
  const publishableKey = String(value?.publishableKey || "");
  if (supabaseUrl !== "https://xcsptvntvrizwhskaphr.supabase.co"
    || !publishableKey || /service_role|secret/i.test(publishableKey)) throw new Error("OPEN_APPLICATION_UNAVAILABLE");
  return { supabaseUrl, publishableKey };
}

export function openApplicationFormData(form) {
  const data = form instanceof FormData ? form : new FormData(form);
  data.set("vacancy_id", "");
  if (!(form instanceof FormData)) data.set("privacy_consent", form.elements.namedItem("privacy_consent")?.checked ? "accepted" : "");
  const interestArea = String(data.get("interest_area") || "");
  const cv = data.get("cv");
  if (!OPEN_APPLICATION_INTEREST_AREAS.includes(interestArea)
    || !(cv instanceof File) || !cv.size || cv.size > 10 * 1024 * 1024 || !CV_TYPES.has(cv.type)
    || data.get("privacy_consent") !== "accepted") throw new Error("OPEN_APPLICATION_INVALID");
  return data;
}

export async function submitOpenApplication(form, fetchImpl = fetch) {
  const configResponse = await fetchImpl("/assets/config/public-recruitment.json", {
    cache: "no-store", credentials: "same-origin", headers: { Accept: "application/json" },
  });
  if (!configResponse.ok) throw new Error("OPEN_APPLICATION_UNAVAILABLE");
  const config = publicConfig(await configResponse.json());
  const response = await fetchImpl(`${config.supabaseUrl}/functions/v1/recruitment-application-submit`, {
    method: "POST",
    headers: { apikey: config.publishableKey },
    body: openApplicationFormData(form),
  });
  const result = await response.json().catch(()=>({}));
  if (!response.ok || result.code !== "SUBMITTED") throw new Error(String(result.code || "OPEN_APPLICATION_FAILED"));
  return result;
}

export function initializeOpenApplication(root = document) {
  const dialog = root.getElementById("openApplicationDialog");
  const form = root.getElementById("openApplicationForm");
  const trigger = root.getElementById("openApplicationTrigger");
  if (!dialog || !form || !trigger) return null;
  const message = root.getElementById("openApplicationMessage");
  const submit = form.querySelector('button[type="submit"]');
  trigger.addEventListener("click", ()=>dialog.showModal());
  root.getElementById("openApplicationCancel").addEventListener("click", ()=>dialog.close());
  form.addEventListener("submit", async (event)=>{
    event.preventDefault();
    if (!form.reportValidity()) return;
    submit.disabled = true;
    message.textContent = "Spontane kandidatuur veilig verzenden...";
    try {
      await submitOpenApplication(form);
      form.reset();
      form.hidden = true;
      root.getElementById("openApplicationSuccess").hidden = false;
    } catch {
      message.textContent = "Verzenden is niet gelukt. Controleer uw gegevens en cv.";
      submit.disabled = false;
    }
  });
  dialog.addEventListener("close", ()=>{
    form.hidden = false;
    submit.disabled = false;
    message.textContent = "";
    root.getElementById("openApplicationSuccess").hidden = true;
  });
  return Object.freeze({ open: ()=>dialog.showModal() });
}

if (typeof document !== "undefined") initializeOpenApplication();