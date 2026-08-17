import { OPERATOR_ROUTES, requireOperatorSession, safeAuthMessage, signOutOperator, watchOperatorSession } from "./operator-auth-core.mjs";
import { getOperatorClient } from "./operator-auth-client.mjs";

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
  const session = await requireOperatorSession(client);
  if (!session) redirectToLogin();
  else {
    email.textContent = session.user.email || "Aangemelde operator";
    loading.hidden = true;
    shell.hidden = false;
  }

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
} catch {
  redirectToLogin();
}
