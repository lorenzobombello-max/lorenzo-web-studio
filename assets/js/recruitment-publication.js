const PUBLICATION_RPC = "get_public_recruitment_publication_state_v1";
let sharedStatePromise;

function publicConfig(value) {
  const supabaseUrl = String(value?.supabaseUrl || "");
  const publishableKey = String(value?.publishableKey || "");
  if (
    supabaseUrl !== "https://xcsptvntvrizwhskaphr.supabase.co" ||
    !publishableKey || /service_role|secret/i.test(publishableKey)
  ) {
    throw new Error("PUBLIC_RECRUITMENT_CONFIG_INVALID");
  }
  return { supabaseUrl, publishableKey };
}

export function publicRecruitmentPublicationResponse(value) {
  if (
    !value || typeof value !== "object" || Array.isArray(value) ||
    Object.keys(value).length !== 1 || typeof value.enabled !== "boolean"
  ) {
    throw new Error("INVALID_PUBLIC_RECRUITMENT_PUBLICATION_RESPONSE");
  }
  return { enabled: value.enabled };
}

export async function loadPublicRecruitmentPublicationState(fetchImpl = fetch) {
  const configResponse = await fetchImpl(
    "/assets/config/public-recruitment.json",
    {
      cache: "no-store",
      credentials: "same-origin",
      headers: { Accept: "application/json" },
    },
  );
  if (!configResponse.ok) throw new Error("PUBLIC_RECRUITMENT_UNAVAILABLE");
  const config = publicConfig(await configResponse.json());
  const response = await fetchImpl(
    `${config.supabaseUrl}/rest/v1/rpc/${PUBLICATION_RPC}`,
    {
      method: "POST",
      cache: "no-store",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        apikey: config.publishableKey,
      },
      body: "{}",
    },
  );
  if (!response.ok) throw new Error("PUBLIC_RECRUITMENT_UNAVAILABLE");
  return publicRecruitmentPublicationResponse(await response.json());
}

export function loadSharedPublicRecruitmentPublicationState() {
  if (!sharedStatePromise) {
    sharedStatePromise = loadPublicRecruitmentPublicationState();
  }
  return sharedStatePromise;
}

export function publicRecruitmentLinkPlan(enabled) {
  return { header: enabled === true, footer: enabled === true };
}

export function applyPublicRecruitmentLinks(root, enabled) {
  for (const link of root.querySelectorAll("[data-careers-link]")) {
    link.closest("li")?.remove() || link.remove();
  }
  const plan = publicRecruitmentLinkPlan(enabled);
  if (!plan.header) return;

  const navigation = root.getElementById("previewNav");
  if (navigation) {
    const link = root.createElement("a");
    link.href = "/werken-bij/";
    link.dataset.careersLink = "";
    link.textContent = "Werken bij ons";
    if (root.defaultView?.location.pathname === "/werken-bij/") {
      link.setAttribute("aria-current", "page");
    }
    navigation.insertBefore(link, navigation.querySelector(".nav-cta"));
  }

  const footerList = root.querySelector(
    ".preview-footer__top > div:nth-child(3) ul",
  );
  if (footerList && plan.footer) {
    const item = root.createElement("li");
    const link = root.createElement("a");
    link.href = "/werken-bij/";
    link.dataset.careersLink = "";
    link.textContent = "Werken bij ons";
    item.append(link);
    footerList.append(item);
  }
}

export async function initializePublicRecruitmentLinks(root = document) {
  applyPublicRecruitmentLinks(root, false);
  try {
    const state = await loadSharedPublicRecruitmentPublicationState();
    applyPublicRecruitmentLinks(root, state.enabled);
  } catch {
    applyPublicRecruitmentLinks(root, false);
  }
}
