import { OPERATOR_ROUTES, requireAuthorizedOperator, signOutOperator, watchOperatorSession } from "./operator-auth-core.mjs";
import { getOperatorClient } from "./operator-auth-client.mjs";

const gate = document.querySelector("#operatorDashboardGate");
const gateTitle = document.querySelector("#operatorDashboardGateTitle");
const gateMessage = document.querySelector("#operatorDashboardGateMessage");
const logout = document.querySelector("#operatorDashboardLogout");
const dashboard = document.querySelector("#operatorDashboard");

function redirectToLogin() {
  window.location.replace(OPERATOR_ROUTES.login);
}

function loadScript(src) {
  return new Promise((resolve, reject) => {
    const script = document.createElement("script");
    script.src = src;
    script.addEventListener("load", resolve, { once: true });
    script.addEventListener("error", reject, { once: true });
    document.head.append(script);
  });
}

try {
  const { client } = await getOperatorClient();
  const access = await requireAuthorizedOperator(client);
  if (access.status === "unauthenticated") redirectToLogin();
  else if (access.status === "unauthorized") {
    gateTitle.textContent = "Geen toegang";
    gateMessage.textContent = "Deze sessie heeft geen actieve operatorautorisatie.";
  }

  const stopWatching = watchOperatorSession(client, () => {}, redirectToLogin);
  window.addEventListener("pagehide", stopWatching, { once: true });

  logout?.addEventListener("click", async () => {
    logout.disabled = true;
    await signOutOperator(client);
    redirectToLogin();
  });
  if (access.status === "unauthorized") logout.hidden = false;
  else if (access.status === "authorized") {
    await loadScript("/assets/js/operator-dashboard-contract.js");
    await loadScript("/assets/js/operator-dashboard.js");
    gate.hidden = true;
    dashboard.hidden = false;
  }
} catch {
  redirectToLogin();
}