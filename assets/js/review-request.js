(function () {
  const statusNode = document.getElementById("reviewStatus");
  const messageNode = document.getElementById("reviewMessage");
  const detailsNode = document.getElementById("reviewDetails");
  const approveButton = document.getElementById("approveButton");
  const rejectButton = document.getElementById("rejectButton");

  const metaBase = document.querySelector('meta[name="lws-functions-base-url"]');
  const functionsBaseUrl = (metaBase?.getAttribute("content") || "").replace(/\/$/, "");

  let locked = false;
  const token = new URLSearchParams(window.location.search).get("token") || "";

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
      return;
    }

    const endpoint = getReviewEndpoint();
    if (!endpoint) {
      setStatus("Configuratie ontbreekt");
      setMessage("De functies-URL is nog niet ingesteld.", "error");
      setButtons(false);
      return;
    }

    setStatus("Status wordt gecontroleerd...");
    setMessage("", null);
    setButtons(false);

    try {
      const response = await fetch(`${endpoint}?token=${encodeURIComponent(token)}`, {
        method: "GET",
        headers: { "Content-Type": "application/json" },
      });

      const data = await response.json();
      renderState(data);
    } catch {
      setStatus("Status onbekend");
      setMessage("De status kon niet worden opgehaald. Probeer later opnieuw.", "error");
      setButtons(false);
    }
  }

  function renderState(data) {
    const state = data?.state;
    fillDetails(data?.request || null);

    if (state === "pending") {
      setStatus("Pending - wacht op beoordeling");
      setButtons(true);
      return;
    }

    if (state === "approved") {
      setStatus("Goedgekeurd");
      setMessage("Deze aanvraag werd al goedgekeurd.", "success");
      setButtons(false);
      return;
    }

    if (state === "rejected") {
      setStatus("Afgewezen");
      setMessage("Deze aanvraag werd al afgewezen.", "success");
      setButtons(false);
      return;
    }

    if (state === "expired") {
      setStatus("Token verlopen");
      setMessage("De beoordelingslink is verlopen.", "error");
      setButtons(false);
      return;
    }

    setStatus("Ongeldig token");
    setMessage("De beoordelingslink is ongeldig.", "error");
    setButtons(false);
  }

  async function submitAction(action) {
    if (locked) return;
    locked = true;
    setButtons(false);
    setMessage("Actie wordt verwerkt...", null);

    const endpoint = getReviewEndpoint();

    try {
      const response = await fetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ token, action }),
      });

      const data = await response.json();
      renderState(data);

      if (data?.state === "approved") {
        setMessage("Aanvraag werd goedgekeurd.", "success");
      } else if (data?.state === "rejected") {
        setMessage("Aanvraag werd afgewezen.", "success");
      }
    } catch {
      setMessage("De actie kon niet worden verwerkt. Probeer later opnieuw.", "error");
      locked = false;
      setButtons(true);
    }
  }

  if (approveButton) {
    approveButton.addEventListener("click", () => submitAction("approved"));
  }

  if (rejectButton) {
    rejectButton.addEventListener("click", () => submitAction("rejected"));
  }

  fetchState();
})();
