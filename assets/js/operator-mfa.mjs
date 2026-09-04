export const MFA_OPERATOR_SUBJECTS = Object.freeze([
  "c9bcd3ef-1e7e-4889-8a12-db827f1b97b0",
  "bd2ab636-0d42-4069-88a9-60bd97f2b335",
]);

const MFA_OPERATOR_SUBJECT_SET = new Set(MFA_OPERATOR_SUBJECTS);

function assertResult(result, fallback) {
  if (result?.error) throw new Error(result.error.message || fallback);
  return result?.data;
}

function validTotp(code) {
  return /^\d{6}$/.test(String(code || "").trim());
}

export function isMfaOperatorSubject(subject) {
  return MFA_OPERATOR_SUBJECT_SET.has(String(subject || ""));
}

export function createOperatorMfaService(client) {
  let enrollmentFactorId = null;
  let challenge = null;

  async function context() {
    const data = assertResult(await client.auth.getSession(), "MFA_SESSION_REQUIRED");
    const subject = data?.session?.user?.id;
    if (!isMfaOperatorSubject(subject)) throw new Error("MFA_OPERATOR_NOT_ELIGIBLE");
    return { session: data.session, subject };
  }

  async function assurance() {
    await context();
    const data = assertResult(
      await client.auth.mfa.getAuthenticatorAssuranceLevel(),
      "MFA_ASSURANCE_UNAVAILABLE",
    );
    return { currentLevel: data?.currentLevel || null, nextLevel: data?.nextLevel || null };
  }

  async function verifiedTotpFactors() {
    await context();
    const data = assertResult(await client.auth.mfa.listFactors(), "MFA_FACTORS_UNAVAILABLE");
    return (Array.isArray(data?.totp) ? data.totp : []).filter((factor)=>factor.status === "verified");
  }

  async function startEnrollment() {
    await context();
    if ((await verifiedTotpFactors()).length) return { status: "already_enrolled" };
    const data = assertResult(await client.auth.mfa.enroll({
      factorType: "totp",
      friendlyName: "LWS Operator",
    }), "MFA_ENROLL_FAILED");
    if (!data?.id || !data?.totp?.qr_code) throw new Error("MFA_ENROLL_FAILED");
    enrollmentFactorId = data.id;
    return { status: "pending", factorId: data.id, qrCode: data.totp.qr_code };
  }

  async function verifyEnrollment(code) {
    if (!enrollmentFactorId || !validTotp(code)) throw new Error("MFA_CODE_INVALID");
    const challengeData = assertResult(
      await client.auth.mfa.challenge({ factorId: enrollmentFactorId }),
      "MFA_CHALLENGE_FAILED",
    );
    if (!challengeData?.id) throw new Error("MFA_CHALLENGE_FAILED");
    assertResult(await client.auth.mfa.verify({
      factorId: enrollmentFactorId,
      challengeId: challengeData.id,
      code: String(code).trim(),
    }), "MFA_VERIFY_FAILED");
    const level = await assurance();
    if (level.currentLevel !== "aal2") throw new Error("AAL2_REQUIRED");
    enrollmentFactorId = null;
    return level;
  }

  async function cancelEnrollment() {
    if (!enrollmentFactorId) return;
    const factorId = enrollmentFactorId;
    enrollmentFactorId = null;
    assertResult(await client.auth.mfa.unenroll({ factorId }), "MFA_CLEANUP_FAILED");
  }

  async function startStepUp() {
    const level = await assurance();
    if (level.currentLevel === "aal2") return { status: "aal2" };
    const [factor] = await verifiedTotpFactors();
    if (!factor?.id) return { status: "enrollment_required" };
    const data = assertResult(
      await client.auth.mfa.challenge({ factorId: factor.id }),
      "MFA_CHALLENGE_FAILED",
    );
    if (!data?.id) throw new Error("MFA_CHALLENGE_FAILED");
    challenge = { factorId: factor.id, challengeId: data.id };
    return { status: "challenge" };
  }

  async function verifyStepUp(code) {
    if (!challenge || !validTotp(code)) throw new Error("MFA_CODE_INVALID");
    const activeChallenge = challenge;
    challenge = null;
    assertResult(await client.auth.mfa.verify({
      factorId: activeChallenge.factorId,
      challengeId: activeChallenge.challengeId,
      code: String(code).trim(),
    }), "MFA_VERIFY_FAILED");
    const level = await assurance();
    if (level.currentLevel !== "aal2") throw new Error("AAL2_REQUIRED");
    return level;
  }

  return {
    assurance,
    cancelEnrollment,
    startEnrollment,
    startStepUp,
    verifiedTotpFactors,
    verifyEnrollment,
    verifyStepUp,
  };
}

function dialogMarkup() {
  return `<dialog class="operator-mfa" data-operator-mfa-dialog aria-labelledby="operatorMfaTitle">
    <form class="operator-mfa__panel" data-operator-mfa-form method="dialog">
      <div class="operator-mfa__signal" aria-hidden="true"></div>
      <p class="kicker" data-operator-mfa-eyebrow>Extra beveiliging</p>
      <h2 id="operatorMfaTitle" data-operator-mfa-title></h2>
      <p class="operator-mfa__intro" data-operator-mfa-description></p>
      <div class="operator-mfa__qr" data-operator-mfa-qr-wrap hidden><img data-operator-mfa-qr alt="Scan deze QR-code met je authenticator-app" /></div>
      <label class="operator-mfa__label" for="operatorMfaCode">6-cijferige verificatiecode</label>
      <input id="operatorMfaCode" data-operator-mfa-code type="text" inputmode="numeric" autocomplete="one-time-code" pattern="[0-9]{6}" minlength="6" maxlength="6" required />
      <p class="operator-mfa__message" data-operator-mfa-message role="status" aria-live="polite"></p>
      <div class="operator-mfa__actions">
        <button class="button button--secondary" data-operator-mfa-cancel type="button">Annuleren</button>
        <button class="button" data-operator-mfa-submit type="submit">Verifiëren</button>
      </div>
    </form>
  </dialog>`;
}

export function createOperatorMfaDialog({ client, documentObject = document } = {}) {
  const service = createOperatorMfaService(client);
  const host = documentObject.createElement("div");
  host.innerHTML = dialogMarkup();
  const dialog = host.firstElementChild;
  documentObject.body.append(dialog);
  const form = dialog.querySelector("[data-operator-mfa-form]");
  const title = dialog.querySelector("[data-operator-mfa-title]");
  const description = dialog.querySelector("[data-operator-mfa-description]");
  const qrWrap = dialog.querySelector("[data-operator-mfa-qr-wrap]");
  const qr = dialog.querySelector("[data-operator-mfa-qr]");
  const code = dialog.querySelector("[data-operator-mfa-code]");
  const message = dialog.querySelector("[data-operator-mfa-message]");
  const submit = dialog.querySelector("[data-operator-mfa-submit]");
  const cancel = dialog.querySelector("[data-operator-mfa-cancel]");
  let mode = null;
  let pending = null;
  let activePromise = null;

  function showMessage(text, state = "info") {
    message.textContent = text;
    message.dataset.state = state;
  }

  function settle(value, error) {
    const active = pending;
    pending = null;
    activePromise = null;
    mode = null;
    qr.removeAttribute("src");
    qrWrap.hidden = true;
    code.value = "";
    if (dialog.open) dialog.close();
    if (error) active?.reject(error);
    else active?.resolve(value);
  }

  function waitForDialog() {
    activePromise = new Promise((resolve, reject)=>{ pending = { resolve, reject }; });
    return activePromise;
  }

  async function enroll() {
    if (pending) return activePromise;
    mode = "enroll";
    title.textContent = "Authenticator instellen";
    description.textContent = "Scan de QR-code met je authenticator-app en voer daarna de actuele code in.";
    submit.textContent = "Authenticator activeren";
    showMessage("Beveiligde QR-code wordt voorbereid.");
    dialog.showModal();
    const completion = waitForDialog();
    try {
      const result = await service.startEnrollment();
      if (result.status === "already_enrolled") {
        showMessage("TOTP is al actief voor dit operatoraccount.", "success");
        settle(true);
        return completion;
      }
      qr.src = result.qrCode;
      qrWrap.hidden = false;
      showMessage("QR-code gereed. Voer de code uit je authenticator-app in.");
      code.focus();
    } catch (error) {
      settle(false, error);
    }
    return completion;
  }

  async function stepUp() {
    if (pending) throw new Error("MFA_FLOW_ACTIVE");
    const state = await service.startStepUp();
    if (state.status === "aal2") return true;
    if (state.status === "enrollment_required") {
      await enroll();
      return true;
    }
    mode = "step-up";
    title.textContent = "Bevestig kritieke actie";
    description.textContent = "Deze actie vereist een extra verificatie. Open je authenticator-app en voer de actuele code in.";
    submit.textContent = "Actie vrijgeven";
    showMessage("De server wacht op je tweede factor.");
    dialog.showModal();
    const completion = waitForDialog();
    code.focus();
    return completion;
  }

  form.addEventListener("submit", async (event)=>{
    event.preventDefault();
    submit.disabled = true;
    cancel.disabled = true;
    showMessage("Verificatie wordt gecontroleerd.");
    try {
      if (mode === "enroll") await service.verifyEnrollment(code.value);
      else await service.verifyStepUp(code.value);
      showMessage("Extra verificatie geslaagd.", "success");
      settle(true);
    } catch (error) {
      code.value = "";
      showMessage("De code kon niet worden geverifieerd. Probeer opnieuw.", "error");
      code.focus();
      if (error?.message === "MFA_OPERATOR_NOT_ELIGIBLE") settle(false, error);
    } finally {
      submit.disabled = false;
      cancel.disabled = false;
    }
  });

  cancel.addEventListener("click", async ()=>{
    cancel.disabled = true;
    try {
      if (mode === "enroll") await service.cancelEnrollment();
      settle(false, new Error("MFA_CANCELLED"));
    } catch (error) {
      showMessage("MFA-cleanup is niet bevestigd. Meld je af en neem contact op met beheer.", "error");
      cancel.disabled = false;
    }
  });

  dialog.addEventListener("cancel", (event)=>{
    event.preventDefault();
    cancel.click();
  });

  return { dialog, enroll, service, stepUp };
}

export function mountOperatorMfaButton({ controller, documentObject = document } = {}) {
  const status = documentObject.querySelector(".topbar__status");
  if (!status || status.querySelector("[data-operator-mfa-enroll]")) return null;
  const button = documentObject.createElement("button");
  button.type = "button";
  button.className = "topbar__mfa";
  button.dataset.operatorMfaEnroll = "";
  button.textContent = "MFA instellen";
  button.addEventListener("click", ()=>void controller.enroll().catch(()=>{}));
  status.prepend(button);
  return button;
}