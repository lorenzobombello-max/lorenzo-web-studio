import { buildMagicLinkRequest, OPERATOR_ROUTES, requireOperatorSession, safeAuthMessage } from "./operator-auth-core.mjs";
import { getOperatorClient } from "./operator-auth-client.mjs";

const form = document.querySelector("[data-operator-login]");
const email = document.querySelector("#operatorEmail");
const message = document.querySelector("#operatorLoginMessage");
const submit = form?.querySelector("button[type='submit']");

function show(text, state = "info") {
  message.textContent = text;
  message.dataset.state = state;
}

try {
  const { client, config } = await getOperatorClient();
  if (await requireOperatorSession(client)) window.location.replace(OPERATOR_ROUTES.home);

  form?.addEventListener("submit", async (event) => {
    event.preventDefault();
    submit.disabled = true;
    show("Beveiligde aanmeldlink wordt aangevraagd.");
    try {
      const request = buildMagicLinkRequest(email.value, config.callbackUrl);
      const { error } = await client.auth.signInWithOtp(request);
      if (error) throw new Error("LOGIN_REQUEST_FAILED");
      form.hidden = true;
      show("Controleer je mailbox en open de beveiligde aanmeldlink.", "success");
    } catch (error) {
      show(safeAuthMessage(error.message), "error");
      submit.disabled = false;
    }
  });
} catch (error) {
  show(safeAuthMessage(error.message), "error");
  if (submit) submit.disabled = true;
}
