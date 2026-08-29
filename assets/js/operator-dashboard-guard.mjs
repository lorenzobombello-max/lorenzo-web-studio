import { OPERATOR_ROUTES, requireAuthorizedOperator, signOutOperator, watchOperatorSession } from "./operator-auth-core.mjs";
import { getOperatorClient } from "./operator-auth-client.mjs";
import { createOperatorModuleNavigation, operatorModuleFromUrl, presentOperatorModule, startOperatorDashboard } from "./operator-dashboard.js?v=20260830-operator-nav-perf-2";

const gate = document.querySelector("#operatorDashboardGate");
const gateTitle = document.querySelector("#operatorDashboardGateTitle");
const gateMessage = document.querySelector("#operatorDashboardGateMessage");
const logout = document.querySelector("#operatorDashboardLogout");
const activeLogout = document.querySelector("#operatorDashboardLogoutActive");
const dashboard = document.querySelector("#operatorDashboard");
let moduleNavigation = null;

function redirectToLogin() {
  moduleNavigation?.invalidateIdentity();
  window.location.replace(OPERATOR_ROUTES.login);
}

function moduleNavigationTarget(event, link) {
  if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return null;
  const url = new URL(link.href, window.location.href);
  return url.origin === window.location.origin && url.pathname === window.location.pathname ? url : null;
}

try {
  const { client, config } = await getOperatorClient();
  const access = await requireAuthorizedOperator(client);
  if (access.status === "unauthenticated") redirectToLogin();
  else if (access.status === "unauthorized") {
    gateTitle.textContent = "Geen toegang";
    gateMessage.textContent = "Deze sessie heeft geen actieve operatorautorisatie.";
  }

  const stopWatching = watchOperatorSession(client, () => {}, redirectToLogin);

  async function logoutOperator(event) {
    event.currentTarget.disabled = true;
    await signOutOperator(client);
    redirectToLogin();
  }
  logout?.addEventListener("click", logoutOperator);
  activeLogout?.addEventListener("click", logoutOperator);
  if (access.status === "unauthorized") logout.hidden = false;
  else if (access.status === "authorized") {
    const functionsBaseUrl = `${config.supabaseUrl}/functions/v1`;
    const identity = await startOperatorDashboard({ client, functionsBaseUrl, onAuthorizationFailure: redirectToLogin });
    gate.hidden = true;
    dashboard.hidden = false;
    const moduleLinks = Array.from(document.querySelectorAll("[data-operator-module]"));
    const dossierWorkspaces = ["internalSmokePanel", "internalSmokeBPanel", "personalQueueWorkspace", "managerWorkspace"]
      .map((id)=>document.getElementById(id)).filter(Boolean);
    let activeModule = operatorModuleFromUrl(window.location.href, identity.role);
    let dossierVisibility = new Map(dossierWorkspaces.map((workspace)=>[workspace, workspace.hidden]));

    function activateModule(module) {
      if (activeModule === "dossiers" && module !== "dossiers") {
        dossierVisibility = new Map(dossierWorkspaces.map((workspace)=>[workspace, workspace.hidden]));
      }
      presentOperatorModule(document, module);
      for (const workspace of dossierWorkspaces) {
        workspace.hidden = module === "dossiers" ? dossierVisibility.get(workspace) ?? true : true;
      }
      activeModule = module;
    }

    moduleNavigation = createOperatorModuleNavigation({
      identity,
      initialUrl: window.location.href,
      activateModule,
      pushUrl: (url)=>window.history.pushState(null, "", url),
      loadModule: async (_module, context)=>{
        await startOperatorDashboard({
          client,
          functionsBaseUrl,
          verifiedIdentity: context.identity,
          isCurrent: context.isCurrent,
          onAuthorizationFailure: redirectToLogin,
          onDossierRoute: (route)=>{
            dossierVisibility = new Map(dossierWorkspaces.map((workspace)=>[
              workspace,
              route === "manager" ? workspace.id !== "managerWorkspace"
                : route === "personal" ? workspace.id !== "personalQueueWorkspace" : true,
            ]));
          },
        });
        return true;
      },
    });

    for (const link of moduleLinks) {
      link.addEventListener("click", (event)=>{
        const target = moduleNavigationTarget(event, link);
        if (!target) return;
        event.preventDefault();
        void moduleNavigation.navigate(target);
      });
    }
    window.addEventListener("popstate", ()=>void moduleNavigation.navigate(window.location.href, { push: false }));
  }
  window.addEventListener("pagehide", stopWatching, { once: true });
} catch {
  redirectToLogin();
}