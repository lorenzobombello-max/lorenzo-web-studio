import { OPERATOR_ROUTES, requireAuthorizedOperator, safeAuthMessage, signOutOperator, watchOperatorSession } from "./operator-auth-core.mjs?v=20260902-login-stability";
import { getOperatorClient } from "./operator-auth-client.mjs?v=20260902-login-stability";

const loading = document.querySelector("#operatorLoading");
const shell = document.querySelector("#operatorShell");
const email = document.querySelector("#operatorSessionEmail");
const message = document.querySelector("#operatorShellMessage");
const logout = document.querySelector("#operatorLogout");

function redirectToLogin() {
  window.location.replace(OPERATOR_ROUTES.login);
}

try {
  const { client } = await getOperatorClient();
  const access = await requireAuthorizedOperator(client);
  if (access.status !== "authorized") {
    if (access.status === "unauthorized") await signOutOperator(client);
    redirectToLogin();
  }
  else {
    email.textContent = access.session.user.email || "Aangemelde operator";
    const stopWatching = watchOperatorSession(client, (nextSession) => {
      email.textContent = nextSession.user.email || "Aangemelde operator";
    }, redirectToLogin);
    window.addEventListener("pagehide", stopWatching, { once: true });

    logout?.addEventListener("click", async () => {
      logout.disabled = true;
      try {
        await signOutOperator(client);
        redirectToLogin();
      } catch (error) {
        message.textContent = safeAuthMessage(error.message);
        message.dataset.state = "error";
        logout.disabled = false;
      }
    });
    loading.hidden = true;
    shell.hidden = false;
  }
} catch {
  redirectToLogin();
}
