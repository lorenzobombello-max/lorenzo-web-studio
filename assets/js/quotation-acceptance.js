(function (global) {
  "use strict";

  const TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;
  const ACTIVE = "ACTIVE";

  function readAndClearFragment(location, history) {
    const parameters = new URLSearchParams((location.hash || "").replace(/^#/, ""));
    const query = new URLSearchParams(location.search || "");
    const token = parameters.get("token") || "";
    query.delete("token");
    const sanitizedQuery = query.toString();
    history.replaceState(history.state, "", `${location.pathname}${sanitizedQuery ? `?${sanitizedQuery}` : ""}`);
    return TOKEN_PATTERN.test(token) ? token : "";
  }

  function apiClient(baseUrl, token, fetchImpl) {
    const endpoint = `${baseUrl.replace(/\/$/, "")}/quotation-acceptance`;
    const authorization = { Authorization: `Bearer ${token}` };
    return {
      async resolve() {
        const response = await fetchImpl(endpoint, {
          method: "GET",
          headers: authorization,
          cache: "no-store",
          referrerPolicy: "no-referrer",
        });
        return parseResponse(response);
      },
      async accept(payload, idempotencyKey) {
        const response = await fetchImpl(endpoint, {
          method: "POST",
          headers: {
            ...authorization,
            "Content-Type": "application/json",
            "Idempotency-Key": idempotencyKey,
          },
          body: JSON.stringify(payload),
          cache: "no-store",
          referrerPolicy: "no-referrer",
        });
        return parseResponse(response);
      },
    };
  }

  async function parseResponse(response) {
    let data = null;
    try { data = await response.json(); } catch { /* Invalid provider response. */ }
    if (!response.ok || !data || typeof data !== "object") {
      const error = new Error("REQUEST_FAILED");
      error.status = response.status;
      throw error;
    }
    return data;
  }

  function text(node, value) {
    if (node) node.textContent = value == null ? "" : String(value);
  }

  function formatMinor(value) {
    if (!Number.isSafeInteger(value)) return "-";
    return new Intl.NumberFormat("nl-BE", { style: "currency", currency: "EUR" }).format(value / 100);
  }

  function createElement(document, name, value) {
    const node = document.createElement(name);
    text(node, value);
    return node;
  }

  function renderRows(document, target, rows) {
    target.replaceChildren();
    for (const [label, value] of rows) {
      const row = document.createElement("div");
      row.append(createElement(document, "dt", label), createElement(document, "dd", value));
      target.append(row);
    }
  }

  function renderLines(document, target, lines) {
    target.replaceChildren();
    for (const line of Array.isArray(lines) ? lines : []) {
      const item = document.createElement("li");
      const copy = document.createElement("div");
      copy.append(createElement(document, "strong", line.description || "Offerteonderdeel"));
      copy.append(createElement(document, "span", `${line.quantity ?? "-"} × ${line.unit || "-"}`));
      item.append(copy, createElement(document, "b", formatMinor(line.line_net_amount_minor)));
      target.append(item);
    }
  }

  function page(document, dependencies) {
    const root = document.getElementById("acceptanceApp");
    const form = document.getElementById("acceptanceForm");
    const submit = document.getElementById("acceptanceSubmit");
    const declaration = document.getElementById("authorityDeclaration");
    const status = document.getElementById("acceptanceStatus");
    const message = document.getElementById("acceptanceMessage");
    const details = document.getElementById("quotationDetails");
    const lines = document.getElementById("quotationLines");
    const schedule = document.getElementById("paymentSchedule");
    const activeContent = document.getElementById("activeAcceptance");
    const resultContent = document.getElementById("acceptanceResult");
    const resultTitle = document.getElementById("resultTitle");
    const resultMessage = document.getElementById("resultMessage");
    const terms = document.getElementById("acceptanceTerms");
    let contract = null;
    let locked = false;

    function showResult(title, copy, tone) {
      activeContent.hidden = true;
      resultContent.hidden = false;
      resultContent.dataset.tone = tone || "neutral";
      text(status, title);
      text(message, copy);
      text(resultTitle, title);
      text(resultMessage, copy);
      resultTitle.focus();
    }

    function renderState(data) {
      if (data.state === ACTIVE && data.quotation && data.acceptance_terms) {
        contract = data.acceptance_terms;
        const quotation = data.quotation;
        text(status, `Offerte ${quotation.number || ""}`);
        text(message, "Controleer de offerte en registreer alleen na expliciete bevestiging je aanvaarding.");
        text(terms, contract.content_reference || "");
        renderRows(document, details, [
          ["Versie", quotation.version ?? "-"],
          ["Klant", quotation.customer?.legal_name || "-"],
          ["Project", quotation.project?.title || "-"],
          ["Scope", quotation.project?.scope_summary || "-"],
          ["Geldig tot", quotation.validity?.valid_until || "-"],
          ["Eenmalig", formatMinor(quotation.totals?.one_time_subtotal_minor)],
          ["Terugkerend", formatMinor(quotation.totals?.recurring_subtotal_minor)],
          ["Korting", formatMinor(quotation.totals?.discount_total_minor)],
          ["Btw-basis", formatMinor(quotation.totals?.vat_base_minor)],
          ["Btw", formatMinor(quotation.totals?.vat_amount_minor)],
          ["Totaal incl. btw", formatMinor(quotation.totals?.total_gross_minor)],
        ]);
        renderLines(document, lines, quotation.lines);
        renderRows(document, schedule, (quotation.payment_schedule?.milestones || []).map((milestone) => [
          milestone.label || `Betalingsfase ${milestone.sequence || ""}`,
          milestone.percentage != null ? `${milestone.percentage}%` : formatMinor(milestone.amount_minor),
        ]));
        document.getElementById("acceptingName").value = "";
        document.getElementById("acceptingEmail").value = quotation.customer?.email || "";
        document.getElementById("acceptingOrganization").value = quotation.customer?.legal_name || "";
        activeContent.hidden = false;
        resultContent.hidden = true;
        submit.disabled = true;
        return;
      }
      if (data.state === "ACCEPTED") {
        showResult("Aanvaarding geregistreerd", `De aanvaarding${data.quotation_number ? ` voor offerte ${data.quotation_number}` : ""} is reeds veilig geregistreerd.`, "success");
      } else if (data.state === "ACCEPTANCE_NOT_AVAILABLE") {
        showResult("Aanvaarding niet beschikbaar", "Deze offerte kan momenteel niet via deze link worden aanvaard.", "warning");
      } else {
        showResult("Link niet geldig", "Deze persoonlijke link is ongeldig, verlopen of ingetrokken.", "warning");
      }
    }

    declaration.addEventListener("change", () => { submit.disabled = locked || !declaration.checked; });
    form.addEventListener("submit", async (event) => {
      event.preventDefault();
      if (locked || !declaration.checked || !contract) return;
      locked = true;
      submit.disabled = true;
      submit.setAttribute("aria-busy", "true");
      text(message, "Aanvaarding wordt veilig geregistreerd...");
      try {
        if (!form.reportValidity()) {
          locked = false;
          submit.removeAttribute("aria-busy");
          submit.disabled = !declaration.checked;
          return;
        }
        const data = await dependencies.api.accept({
          accepting_name: document.getElementById("acceptingName").value.trim(),
          accepting_email: document.getElementById("acceptingEmail").value.trim(),
          accepting_organization: document.getElementById("acceptingOrganization").value.trim() || null,
          accepting_role: document.getElementById("acceptingRole").value.trim() || null,
          authority_declaration: true,
          terms_id: contract.terms_id,
          terms_version: contract.terms_version,
        }, dependencies.randomUUID());
        if (data.state === "ACCEPTED") {
          const confirmation = data.confirmation_status === "failed"
            ? " De registratie is geldig; de bevestigingsmail kon nog niet worden afgeleverd."
            : " Je ontvangt een bevestiging per e-mail.";
          showResult("Aanvaarding geregistreerd", `Bedankt. Je aanvaarding is definitief geregistreerd.${confirmation}`, "success");
        } else if (data.state === "INVALID_OR_EXPIRED_LINK") {
          showResult("Link niet geldig", "De persoonlijke link is verlopen of niet langer beschikbaar.", "warning");
        } else {
          locked = false;
          submit.removeAttribute("aria-busy");
          submit.disabled = !declaration.checked;
          text(message, "De aanvaarding kon niet worden geregistreerd. Controleer je gegevens en probeer opnieuw.");
        }
      } catch {
        locked = false;
        submit.removeAttribute("aria-busy");
        submit.disabled = !declaration.checked;
        text(message, "Er is tijdelijk geen verbinding. Probeer het later opnieuw.");
      }
    });

    root.dataset.state = "loading";
    dependencies.api.resolve().then((data) => {
      root.dataset.state = "ready";
      renderState(data);
    }).catch(() => {
      root.dataset.state = "error";
      showResult("Offerte niet bereikbaar", "De offerte kon tijdelijk niet worden geladen. Probeer het later opnieuw.", "warning");
    });
  }

  function boot(windowObject, document) {
    const token = readAndClearFragment(windowObject.location, windowObject.history);
    const baseUrl = document.querySelector('meta[name="lws-functions-base-url"]')?.content || "";
    if (!token || !baseUrl) {
      const app = document.getElementById("acceptanceApp");
      if (app) app.dataset.state = "invalid";
      const active = document.getElementById("activeAcceptance");
      const result = document.getElementById("acceptanceResult");
      if (active) active.hidden = true;
      if (result) result.hidden = false;
      text(document.getElementById("resultTitle"), "Link niet geldig");
      text(document.getElementById("resultMessage"), "Open de persoonlijke link uit de offerte-e-mail opnieuw.");
      return;
    }
    page(document, {
      api: apiClient(baseUrl, token, windowObject.fetch.bind(windowObject)),
      randomUUID: () => windowObject.crypto.randomUUID(),
    });
  }

  const exported = { TOKEN_PATTERN, readAndClearFragment, apiClient, parseResponse, formatMinor, page, boot };
  if (typeof module !== "undefined" && module.exports) module.exports = exported;
  if (global && global.document) boot(global, global.document);
})(typeof window !== "undefined" ? window : globalThis);