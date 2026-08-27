import { OPERATOR_ROUTES, requireAuthorizedOperator, signOutOperator, watchOperatorSession } from "./operator-auth-core.mjs";
import { getOperatorClient } from "./operator-auth-client.mjs";
import { startOperatorDashboard } from "./operator-dashboard.js?v=20260827-owner-smoke-a-ui";

const gate = document.querySelector("#operatorDashboardGate");
const gateTitle = document.querySelector("#operatorDashboardGateTitle");
const gateMessage = document.querySelector("#operatorDashboardGateMessage");
const logout = document.querySelector("#operatorDashboardLogout");
const activeLogout = document.querySelector("#operatorDashboardLogoutActive");
const dashboard = document.querySelector("#operatorDashboard");

function redirectToLogin() {
  window.location.replace(OPERATOR_ROUTES.login);
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
  window.addEventListener("pagehide", stopWatching, { once: true });

  async function logoutOperator(event) {
    event.currentTarget.disabled = true;
    await signOutOperator(client);
    redirectToLogin();
  }
  logout?.addEventListener("click", logoutOperator);
  activeLogout?.addEventListener("click", logoutOperator);
  if (access.status === "unauthorized") logout.hidden = false;
  else if (access.status === "authorized") {
    await startOperatorDashboard({ client, functionsBaseUrl: `${config.supabaseUrl}/functions/v1` });
    gate.hidden = true;
    dashboard.hidden = false;
  }
} catch {
  redirectToLogin();
}