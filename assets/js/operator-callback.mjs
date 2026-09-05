import { OPERATOR_ROUTES, resolveAuthCallback, safeAuthMessage } from "./operator-auth-core.mjs?v=20260902-login-stability";
import { getOperatorClient } from "./operator-auth-client.mjs?v=20260902-login-stability";

const message = document.querySelector("#operatorCallbackMessage");
const returnLink = document.querySelector("#operatorCallbackReturn");

try {
  const { client } = await getOperatorClient();
  const result = await resolveAuthCallback(client, {
    history: window.history,
    location: window.location,
    nowSeconds: () => Math.floor(Date.now() / 1000),
  });
  if (!result.ok) throw new Error(result.code);
  message.textContent = "Sessie bevestigd. De operatoromgeving wordt geopend.";
  window.location.replace(OPERATOR_ROUTES.profile);
} catch (error) {
  window.history.replaceState(window.history.state, "", OPERATOR_ROUTES.callback);
  message.textContent = safeAuthMessage(error.message);
  message.dataset.state = "error";
  returnLink.hidden = false;
}
