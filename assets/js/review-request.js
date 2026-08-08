(function () {
  const statusNode = document.getElementById("reviewStatus");
  const messageNode = document.getElementById("reviewMessage");
  const detailsNode = document.getElementById("reviewDetails");
  const approveButton = document.getElementById("approveButton");
  const rejectButton = document.getElementById("rejectButton");
  const retryConfirmationButton = document.getElementById("retryConfirmationButton");
  const sendIntakeInvitationButton = document.getElementById("sendIntakeInvitationButton");
  const intakeInvitationStatus = document.getElementById("intakeInvitationStatus");
  const approvalModal = document.getElementById("reviewApprovalModal");
  const approvalModalPanel = document.getElementById("reviewApprovalModalPanel");
  const approvalModalClose = document.getElementById("reviewApprovalModalClose");
  const approvalModalOverlay = document.getElementById("reviewApprovalModalOverlay");

  const metaBase = document.querySelector('meta[name="lws-functions-base-url"]');
  const functionsBaseUrl = (metaBase?.getAttribute("content") || "").replace(/\/$/, "");

  let locked = false;
  let currentRequest = null;
  let currentReviewState = null;
  let confirmationDeliveryStatus = null;
  let currentIntakeExists = false;
  let currentInvitationExists = false;
  let currentInvitationDeliveryStatus = null;
  let approvalModalTimer = null;
  const token = new URLSearchParams(window.location.search).get("token") || "";
  if (token) {
    const sanitizedUrl = new URL(window.location.href);
    sanitizedUrl.searchParams.delete("token");
    window.history.replaceState(window.history.state, "", `${sanitizedUrl.pathname}${sanitizedUrl.search}${sanitizedUrl.hash}`);
  }

  function setMessage(text, type) {
    if (!messageNode) return;
    messageNode.textContent = text;
    messageNode.classList.remove("is-error", "is-success");
    if (type === "error") messageNode.classList.add("is-error");
    if (type === "success") messageNode.classList.add("is-success");
  }

  function setStatus(text) {
    if (!statusNode) return;
    statusNode.textContent = text;
  }

  function setButtons(enabled) {
    const disabled = !enabled || locked;
    if (approveButton) approveButton.disabled = disabled;
    if (rejectButton) rejectButton.disabled = disabled;
  }

  function setRetryButton(visible) {
    if (!retryConfirmationButton) return;
    retryConfirmationButton.hidden = !visible;
    retryConfirmationButton.style.display = visible ? "" : "none";
    retryConfirmationButton.disabled = !visible || locked;
  }

  function setIntakeInvitationState(data) {
    if (!sendIntakeInvitationButton || !intakeInvitationStatus) return;

    if (Object.prototype.hasOwnProperty.call(data || {}, "intake_exists")) {
      currentIntakeExists = data.intake_exists === true;
    }
    if (Object.prototype.hasOwnProperty.call(data || {}, "intake_invitation_exists")) {
      currentInvitationExists = data.intake_invitation_exists === true;
    }
    if (Object.prototype.hasOwnProperty.call(data || {}, "intake_invitation_delivery_status")) {
      currentInvitationDeliveryStatus = data.intake_invitation_delivery_status || null;
    }

    const approved = currentReviewState === "approved";
    const canSend = approved && !currentIntakeExists && !currentInvitationExists;

    sendIntakeInvitationButton.hidden = !canSend;
    sendIntakeInvitationButton.style.display = canSend ? "" : "none";
    sendIntakeInvitationButton.disabled = !canSend || locked;

    let status = "";
    let type = null;
    if (approved && currentInvitationExists) {
      if (currentInvitationDeliveryStatus === "sent") {
        status = "Intake-uitnodiging verzonden.";
        type = "success";
      } else if (
        currentInvitationDeliveryStatus === "pending" ||
        currentInvitationDeliveryStatus === "processing" ||
        currentInvitationDeliveryStatus === "retry_wait"
      ) {
        status = "Intake-uitnodiging wacht op verzending.";
      } else {
        status = "Intake-uitnodiging kon niet worden verzonden.";
        type = "error";
      }
    } else if (approved && currentIntakeExists) {
      status = "Voor deze aanvraag bestaat al een intake.";
    }

    intakeInvitationStatus.textContent = status;
    intakeInvitationStatus.hidden = !status;
    intakeInvitationStatus.classList.remove("is-error", "is-success");
    if (type === "error") intakeInvitationStatus.classList.add("is-error");
    if (type === "success") intakeInvitationStatus.classList.add("is-success");
  }

  function showApprovalModal() {
    if (!approvalModal || !approvalModalPanel) return;

    if (approvalModalTimer) window.clearTimeout(approvalModalTimer);
    approvalModal.hidden = false;
    document.body.classList.add("modal-open");
    approvalModalPanel.focus();

    function closeModal() {
      if (approvalModalTimer) {
        window.clearTimeout(approvalModalTimer);
        approvalModalTimer = null;
      }
      approvalModal.hidden = true;
      document.body.classList.remove("modal-open");
      approveButton?.focus();
      document.removeEventListener("keydown", handleEscape);
    }

    function handleEscape(event) {
      if (event.key === "Escape") closeModal();
    }

    document.addEventListener("keydown", handleEscape);
    approvalModalClose?.addEventListener("click", closeModal, { once: true });
    approvalModalOverlay?.addEventListener("click", closeModal, { once: true });
    approvalModalTimer = window.setTimeout(closeModal, 4000);
  }

  function fillDetails(request) {
    if (!detailsNode) return;

    const map = new Map([
      ["Aanvraagnummer", request?.id || "-"],
      ["Ontvangstdatum", request?.created_at ? new Date(request.created_at).toLocaleString("nl-BE") : "-"],
      ["Naam", request?.name || "-"],
      ["Bedrijfsnaam", request?.company || "Niet ingevuld"],
      ["E-mailadres", request?.email || "-"],
      ["Telefoon", request?.phone || "Niet ingevuld"],
      ["Type website", request?.website_type || "-"],
      ["Budget", request?.budget || "-"],
      ["Timing", request?.timing || "-"],
      ["Projectomschrijving", request?.description || "-"],
    ]);

    detailsNode.querySelectorAll("div").forEach((row) => {
      const dt = row.querySelector("dt")?.textContent?.trim() || "";
      const dd = row.querySelector("dd");
      if (!dd) return;
      dd.textContent = map.get(dt) || "-";
    });
  }

  function getReviewEndpoint() {
    if (!functionsBaseUrl) return "";
    return `${functionsBaseUrl}/review-quote-request`;
  }

  async function fetchState() {
    if (!token) {
      setStatus("Ongeldig token");
      setMessage("De beoordelingslink is ongeldig of onvolledig.", "error");
      setButtons(false);
      setRetryButton(false);
      currentReviewState = "invalid";
      setIntakeInvitationState({});
      return;
    }

    const endpoint = getReviewEndpoint();
    if (!endpoint) {
      setStatus("Configuratie ontbreekt");
      setMessage("De functies-URL is nog niet ingesteld.", "error");
      setButtons(false);
      setRetryButton(false);
      currentReviewState = "invalid";
      setIntakeInvitationState({});
      return;
    }

    setStatus("Status wordt gecontroleerd...");
    setMessage("", null);
    setButtons(false);
    setRetryButton(false);
    currentReviewState = null;
    setIntakeInvitationState({});

    try {
      const response = await fetch(endpoint, {
        method: "GET",
        headers: { Authorization: `Bearer ${token}` },
      });

      const data = await response.json();
      renderState(data);
    } catch {
      setStatus("Status onbekend");
      setMessage("De status kon niet worden opgehaald. Probeer later opnieuw.", "error");
      setButtons(false);
      setRetryButton(false);
      currentReviewState = "invalid";
      setIntakeInvitationState({});
    }
  }

  function renderState(data) {
    const state = data?.state;
    currentReviewState = state || null;
    if (Object.prototype.hasOwnProperty.call(data || {}, "delivery_status")) {
      confirmationDeliveryStatus = data.delivery_status;
    }
    if (data?.request) currentRequest = { ...currentRequest, ...data.request };
    fillDetails(currentRequest);
    setIntakeInvitationState(data);

    if (state === "pending") {
      setStatus("Pending - wacht op beoordeling");
      setRetryButton(false);
      setButtons(true);
      return;
    }

    if (state === "approved") {
      setStatus("Goedgekeurd");
      const deliveryStatus = confirmationDeliveryStatus;
      const confirmationSent = data?.mail_sent === true || deliveryStatus === "sent";
      setMessage(
        confirmationSent
          ? "Deze aanvraag werd goedgekeurd en de bevestigingsmail is verzonden."
          : "Deze aanvraag werd goedgekeurd. De bevestigingsmail wacht nog op verzending of een nieuwe poging.",
        confirmationSent ? "success" : "error"
      );
      setRetryButton(!confirmationSent);
      setButtons(false);
      return;
    }

    if (state === "rejected") {
      setStatus("Afgewezen");
      setMessage("Deze aanvraag werd al afgewezen.", "success");
      setRetryButton(false);
      setButtons(false);
      return;
    }

    if (state === "expired") {
      setStatus("Token verlopen");
      setMessage("De beoordelingslink is verlopen.", "error");
      setRetryButton(false);
      setButtons(false);
      return;
    }

    setStatus("Ongeldig token");
    setMessage("De beoordelingslink is ongeldig.", "error");
    setRetryButton(false);
    setButtons(false);
  }

  async function submitAction(action) {
    if (locked) return;
    locked = true;
    setButtons(false);
    if (sendIntakeInvitationButton) sendIntakeInvitationButton.disabled = true;
    setMessage("Actie wordt verwerkt...", null);

    const endpoint = getReviewEndpoint();

    try {
      const response = await fetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ token, action }),
      });

      const data = await response.json();
      locked = false;
      if (action === "send_intake_invitation" && (data?.invitation_outcome === "invitation_created" || data?.invitation_outcome === "already_invited")) {
        renderState({
          ...data,
          delivery_status: confirmationDeliveryStatus,
          intake_exists: true,
          intake_status: "invited",
          intake_invitation_exists: true,
          intake_invitation_delivery_status: data.delivery_status || null,
        });
      } else {
        renderState(data);
      }
      if (action === "approved" && data?.state === "approved" && (data?.mail_sent === true || data?.delivery_status === "sent")) {
        showApprovalModal();
      }
    } catch {
      setMessage("De actie kon niet worden verwerkt. Probeer later opnieuw.", "error");
      locked = false;
      setButtons(currentReviewState === "pending");
      setRetryButton(currentReviewState === "approved" && confirmationDeliveryStatus !== "sent");
      setIntakeInvitationState({});
    }
  }

  if (approveButton) {
    approveButton.addEventListener("click", () => submitAction("approved"));
  }

  if (rejectButton) {
    rejectButton.addEventListener("click", () => submitAction("rejected"));
  }

  if (retryConfirmationButton) {
    retryConfirmationButton.addEventListener("click", () => submitAction("retry_confirmation"));
  }

  if (sendIntakeInvitationButton) {
    sendIntakeInvitationButton.addEventListener("click", () => submitAction("send_intake_invitation"));
  }

  fetchState();
})();
