(function (global) {
  "use strict";

  const TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;
  const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  const MAX_FILE_BYTES = 8388608;
  const ALLOWED_TYPES = new Map([
    ["application/pdf", new Set(["pdf"])],
    ["image/png", new Set(["png"])],
    ["image/jpeg", new Set(["jpg", "jpeg"])],
  ]);

  function readAndClearFragment(location, history) {
    const fragment = new URLSearchParams((location.hash || "").replace(/^#/, ""));
    const query = new URLSearchParams(location.search || "");
    const token = fragment.get("token") || "";
    query.delete("token");
    const sanitized = query.toString();
    history.replaceState(history.state, "", `${location.pathname}${sanitized ? `?${sanitized}` : ""}`);
    return TOKEN_PATTERN.test(token) ? token : "";
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

  function apiClient(baseUrl, token, fetchImpl) {
    const endpoint = `${baseUrl.replace(/\/$/, "")}/customer-request-upload`;
    const authorization = { Authorization: `Bearer ${token}` };
    async function mutate(action, payload, idempotencyKey) {
      return parseResponse(await fetchImpl(endpoint, {
        method: "POST",
        headers: { ...authorization, "Content-Type": "application/json", "Idempotency-Key": idempotencyKey },
        body: JSON.stringify({ action, ...payload }),
        cache: "no-store",
        referrerPolicy: "no-referrer",
      }));
    }
    return {
      resolve: async () => parseResponse(await fetchImpl(endpoint, { method: "GET", headers: authorization, cache: "no-store", referrerPolicy: "no-referrer" })),
      prepare: (payload, key) => mutate("prepare", payload, key),
      finalize: (fileId, key) => mutate("finalize", { file_id: fileId }, key),
      complete: (key) => mutate("complete", {}, key),
    };
  }

  function extension(name) {
    const match = String(name || "").toLowerCase().match(/\.([a-z0-9]+)$/);
    return match ? match[1] : "";
  }

  function validateFile(file) {
    if (!file || !Number.isSafeInteger(file.size) || file.size < 1 || file.size > MAX_FILE_BYTES) return "FILE_TOO_LARGE";
    const extensions = ALLOWED_TYPES.get(file.type);
    if (!extensions || !extensions.has(extension(file.name))) return "FILE_TYPE_NOT_ALLOWED";
    return null;
  }

  async function uploadToSignedUrl(signedUrl, file, fetchImpl) {
    const response = await fetchImpl(signedUrl, {
      method: "PUT",
      headers: { "Content-Type": file.type, "x-upsert": "false" },
      body: file,
      referrerPolicy: "no-referrer",
    });
    if (!response.ok) throw new Error("UPLOAD_FAILED");
  }

  function text(node, value) {
    if (node) node.textContent = value == null ? "" : String(value);
  }

  function renderFiles(document, files) {
    const list = document.getElementById("uploadFileList");
    const empty = document.getElementById("uploadFileEmpty");
    list.replaceChildren();
    const accepted = Array.isArray(files) ? files.filter((file) => file.status === "ACCEPTED") : [];
    empty.hidden = accepted.length > 0;
    for (const file of accepted) {
      const item = document.createElement("li");
      const name = document.createElement("strong");
      const details = document.createElement("span");
      text(name, file.original_file_name || "Bestand");
      text(details, `${Math.ceil(Number(file.byte_count || 0) / 1024)} KB · Geaccepteerd`);
      item.append(name, details);
      list.append(item);
    }
  }

  function page(document, dependencies) {
    const root = document.getElementById("uploadApp");
    const active = document.getElementById("activeUpload");
    const result = document.getElementById("uploadResult");
    const status = document.getElementById("uploadStatus");
    const message = document.getElementById("uploadMessage");
    const input = document.getElementById("uploadFiles");
    const submit = document.getElementById("uploadSubmit");
    const complete = document.getElementById("uploadComplete");
    let contract = null;
    let busy = false;

    function render(data) {
      contract = data;
      if (data.state !== "ACTIVE") {
        active.hidden = true;
        result.hidden = false;
        text(status, data.state === "COMPLETED" ? "Upload afgerond" : "Link niet geldig");
        text(document.getElementById("uploadResultTitle"), data.state === "COMPLETED" ? "Bestanden ontvangen" : "Upload niet beschikbaar");
        text(document.getElementById("uploadResultMessage"), data.state === "COMPLETED" ? "De upload is veilig afgerond." : "Deze persoonlijke link is ongeldig, verlopen of ingetrokken.");
        return;
      }
      active.hidden = false;
      result.hidden = true;
      text(status, "Upload beschikbaar");
      text(message, `Nog ${Math.max(0, 5 - Number(data.file_count || 0))} bestand(en) mogelijk.`);
      renderFiles(document, data.files);
      complete.disabled = Number(data.accepted_file_count || 0) < 1;
    }

    input.addEventListener("change", () => {
      const files = Array.from(input.files || []);
      submit.disabled = busy || files.length < 1 || files.some(validateFile) || files.length > 5;
      text(message, files.length > 5 ? "Selecteer maximaal vijf bestanden." : files.find((file) => validateFile(file)) ? "Alleen PDF, PNG of JPEG tot 8 MiB." : "");
    });

    document.getElementById("uploadForm").addEventListener("submit", async (event) => {
      event.preventDefault();
      if (busy || !contract) return;
      const files = Array.from(input.files || []);
      if (!files.length || files.some(validateFile)) return;
      busy = true;
      submit.disabled = true;
      try {
        for (const file of files) {
          text(message, `${file.name} wordt voorbereid...`);
          const prepared = await dependencies.api.prepare({ file_name: file.name, content_type: file.type, byte_count: file.size }, dependencies.randomUUID());
          if (prepared.state !== "PREPARED" || !UUID_PATTERN.test(prepared.file_id) || typeof prepared.signed_upload_url !== "string") throw new Error("PREPARE_FAILED");
          await dependencies.upload(prepared.signed_upload_url, file);
          const finalized = await dependencies.api.finalize(prepared.file_id, dependencies.randomUUID());
          if (finalized.state !== "ACTIVE") throw new Error("FINALIZE_FAILED");
          render(finalized);
        }
        input.value = "";
        text(message, "De geselecteerde bestanden zijn veilig ontvangen.");
      } catch {
        text(message, "De upload kon niet worden afgerond. Probeer opnieuw.");
      } finally {
        busy = false;
        submit.disabled = true;
      }
    });

    complete.addEventListener("click", async () => {
      if (busy) return;
      busy = true;
      complete.disabled = true;
      try { render(await dependencies.api.complete(dependencies.randomUUID())); }
      catch { text(message, "Afronden is tijdelijk niet gelukt."); complete.disabled = false; }
      finally { busy = false; }
    });

    dependencies.api.resolve().then((data) => { root.dataset.state = "ready"; render(data); }).catch(() => {
      root.dataset.state = "error";
      render({ state: "INVALID_OR_EXPIRED_LINK" });
    });
  }

  function boot(windowObject, document) {
    const token = readAndClearFragment(windowObject.location, windowObject.history);
    const baseUrl = document.querySelector('meta[name="lws-functions-base-url"]')?.content || "";
    if (!token || !baseUrl) {
      document.getElementById("activeUpload").hidden = true;
      document.getElementById("uploadResult").hidden = false;
      text(document.getElementById("uploadResultTitle"), "Link niet geldig");
      text(document.getElementById("uploadResultMessage"), "Open de persoonlijke uploadlink opnieuw.");
      return;
    }
    const fetchImpl = windowObject.fetch.bind(windowObject);
    page(document, {
      api: apiClient(baseUrl, token, fetchImpl),
      randomUUID: () => windowObject.crypto.randomUUID(),
      upload: (url, file) => uploadToSignedUrl(url, file, fetchImpl),
    });
  }

  const exported = { TOKEN_PATTERN, readAndClearFragment, apiClient, parseResponse, validateFile, uploadToSignedUrl, page, boot };
  if (typeof module !== "undefined" && module.exports) module.exports = exported;
  if (global && global.document) boot(global, global.document);
})(typeof window !== "undefined" ? window : globalThis);