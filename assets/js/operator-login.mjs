import {
  buildEmailOtpRequest,
  buildEmailOtpVerification,
  classifyAuthError,
  isUsableSession,
  OPERATOR_ROUTES,
  requireOperatorSession,
  safeAuthMessage,
} from "./operator-auth-core.mjs";
import { getOperatorClient } from "./operator-auth-client.mjs";

export const LOCAL_RESEND_COOLDOWN_SECONDS = 60;

export function createOperatorLoginController({
  client,
  elements,
  navigate,
  now = () => Date.now(),
  setTimer = (callback) => window.setInterval(callback, 1000),
  clearTimer = (timer) => window.clearInterval(timer),
  cooldownSeconds = LOCAL_RESEND_COOLDOWN_SECONDS,
}) {
  let retainedEmail = "";
  let sending = false;
  let verifying = false;
  let cooldownUntil = 0;
  let cooldownTimer = null;
  let lastError = null;

  function show(text, state = "info") {
    elements.message.textContent = text;
    elements.message.dataset.state = state;
  }

  function remainingCooldown() {
    return Math.max(0, Math.ceil((cooldownUntil - now()) / 1000));
  }

  function updateControls() {
    const remaining = remainingCooldown();
    elements.emailSubmit.disabled = sending || remaining > 0;
    elements.verifySubmit.disabled = verifying;
    elements.resendButton.disabled = sending || remaining > 0;
    elements.resendStatus.textContent = remaining > 0
      ? `Nieuwe code aanvragen over ${remaining} s.`
      : "Je kunt een nieuwe code aanvragen.";
    if (!remaining && cooldownTimer !== null) {
      clearTimer(cooldownTimer);
      cooldownTimer = null;
    }
  }

  function startCooldown(seconds = cooldownSeconds) {
    const safeSeconds = Number.isFinite(Number(seconds)) ? Math.max(0, Math.ceil(Number(seconds))) : cooldownSeconds;
    cooldownUntil = now() + safeSeconds * 1000;
    if (cooldownTimer !== null) clearTimer(cooldownTimer);
    cooldownTimer = safeSeconds > 0 ? setTimer(updateControls) : null;
    updateControls();
  }

  function showCodeStep() {
    elements.emailForm.hidden = true;
    elements.codeForm.hidden = false;
    elements.codeInput.focus();
  }

  function showEmailStep() {
    elements.emailForm.hidden = false;
    elements.codeForm.hidden = true;
    elements.emailInput.focus();
  }

  async function requestCode(candidateEmail = elements.emailInput.value) {
    if (sending || remainingCooldown() > 0) return false;
    sending = true;
    lastError = null;
    updateControls();
    show("Een eenmalige aanmeldcode wordt aangevraagd.");
    try {
      const request = buildEmailOtpRequest(candidateEmail);
      const { error } = await client.auth.signInWithOtp(request);
      if (error) {
        lastError = classifyAuthError(error);
        if (lastError.safeCode === "AUTH_RATE_LIMITED") {
          startCooldown(lastError.retryAfterSeconds ?? cooldownSeconds);
        }
        show(safeAuthMessage(lastError.safeCode), "error");
        return false;
      }
      retainedEmail = request.email;
      elements.codeInput.value = "";
      showCodeStep();
      startCooldown(cooldownSeconds);
      show("De eenmalige code is per e-mail verzonden.", "success");
      return true;
    } catch (error) {
      if (error.message === "EMAIL_INVALID") {
        show(safeAuthMessage(error.message), "error");
      } else {
        lastError = classifyAuthError(error);
        if (lastError.safeCode === "AUTH_RATE_LIMITED") {
          startCooldown(lastError.retryAfterSeconds ?? cooldownSeconds);
        }
        show(safeAuthMessage(lastError.safeCode), "error");
      }
      return false;
    } finally {
      sending = false;
      updateControls();
    }
  }

  async function verifyCode(candidateToken = elements.codeInput.value) {
    if (verifying) return false;
    let request;
    try {
      request = buildEmailOtpVerification(retainedEmail, candidateToken);
    } catch (error) {
      show(safeAuthMessage(error.message), "error");
      return false;
    }

    verifying = true;
    lastError = null;
    updateControls();
    show("De aanmeldcode wordt gecontroleerd.");
    try {
      const { data, error } = await client.auth.verifyOtp(request);
      if (error) {
        lastError = classifyAuthError(error);
        elements.codeInput.value = "";
        show(safeAuthMessage(lastError.safeCode), "error");
        return false;
      }
      if (!isUsableSession(data?.session)) {
        show(safeAuthMessage("SESSION_ESTABLISHMENT_FAILED"), "error");
        return false;
      }
      elements.codeInput.value = "";
      retainedEmail = "";
      if (cooldownTimer !== null) clearTimer(cooldownTimer);
      cooldownTimer = null;
      navigate(OPERATOR_ROUTES.home);
      return true;
    } catch (error) {
      lastError = classifyAuthError(error);
      elements.codeInput.value = "";
      show(safeAuthMessage(lastError.safeCode), "error");
      return false;
    } finally {
      verifying = false;
      updateControls();
    }
  }

  function useDifferentEmail() {
    retainedEmail = "";
    elements.codeInput.value = "";
    cooldownUntil = 0;
    if (cooldownTimer !== null) clearTimer(cooldownTimer);
    cooldownTimer = null;
    showEmailStep();
    updateControls();
    show("");
  }

  async function resendCode() {
    if (!retainedEmail || remainingCooldown() > 0) return false;
    return requestCode(retainedEmail);
  }

  updateControls();
  return {
    requestCode,
    resendCode,
    useDifferentEmail,
    verifyCode,
    getState: () => ({ lastError, retainedEmail, sending, verifying, cooldownRemaining: remainingCooldown() }),
  };
}

async function boot() {
  const elements = {
    emailForm: document.querySelector("[data-operator-email-step]"),
    codeForm: document.querySelector("[data-operator-code-step]"),
    emailInput: document.querySelector("#operatorEmail"),
    codeInput: document.querySelector("#operatorCode"),
    emailSubmit: document.querySelector("[data-send-code]"),
    verifySubmit: document.querySelector("[data-verify-code]"),
    resendButton: document.querySelector("[data-resend-code]"),
    resendStatus: document.querySelector("[data-resend-status]"),
    differentEmailButton: document.querySelector("[data-different-email]"),
    message: document.querySelector("#operatorLoginMessage"),
  };

  try {
    const { client } = await getOperatorClient();
    if (await requireOperatorSession(client)) {
      window.location.replace(OPERATOR_ROUTES.home);
      return;
    }
    const controller = createOperatorLoginController({
      client,
      elements,
      navigate: (path) => window.location.replace(path),
    });
    elements.emailForm.addEventListener("submit", (event) => {
      event.preventDefault();
      void controller.requestCode();
    });
    elements.codeForm.addEventListener("submit", (event) => {
      event.preventDefault();
      void controller.verifyCode();
    });
    elements.resendButton.addEventListener("click", () => void controller.resendCode());
    elements.differentEmailButton.addEventListener("click", controller.useDifferentEmail);
  } catch (error) {
    elements.message.textContent = safeAuthMessage(error.message);
    elements.message.dataset.state = "error";
    elements.emailSubmit.disabled = true;
  }
}

if (typeof document !== "undefined") void boot();
