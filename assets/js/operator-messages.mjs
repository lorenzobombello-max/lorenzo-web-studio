import { createOperatorAutoRefresh } from "./operator-auto-refresh.mjs?v=20260903-auto-refresh-8s";
import { createOperatorRefreshHeartbeat } from "./operator-refresh-heartbeat.mjs?v=20260903-live-heartbeat";

const MESSAGE_SCOPES = new Set(["PERSONAL", "ALL"]);
const MAILBOXES = new Set(["received", "sent"]);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function messageTimestamp(value) {
  const date = new Date(value);
  if (!Number.isFinite(date.getTime())) return "Onbekend";
  return new Intl.DateTimeFormat("nl-BE", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(date);
}

function messagePreview(body) {
  const value = String(body || "").replace(/\s+/g, " ").trim();
  return value.length > 92 ? `${value.slice(0, 89)}...` : value;
}

function validMessage(message, mailbox) {
  if (!message || typeof message !== "object" || !UUID.test(String(message.id || ""))) return false;
  if (!MESSAGE_SCOPES.has(message.message_scope) || typeof message.body !== "string") return false;
  if (typeof message.sender_display_name !== "string" || !Number.isFinite(Date.parse(message.created_at))) return false;
  if (mailbox === "received" && !(message.read_at === null || Number.isFinite(Date.parse(message.read_at)))) return false;
  return mailbox !== "sent" || Array.isArray(message.recipients);
}

function recipientContext(message, mailbox) {
  if (message.message_scope === "ALL") return `Iedereen (${message.recipient_count} ontvangers)`;
  if (mailbox === "sent") return message.recipients?.[0]?.display_name || "Persoonlijk bericht";
  return "Persoonlijk aan jou";
}

function validRecipient(recipient) {
  if (!recipient || typeof recipient !== "object" || Array.isArray(recipient)) return false;
  if (Object.keys(recipient).sort().join(",") !== "display_name,operator_id") return false;
  return UUID.test(String(recipient.operator_id || "")) && String(recipient.display_name || "").trim().length > 0;
}

export function createOperatorMessagesRealtime({ client, onInvalidate, channelName = `operator-messages:${crypto.randomUUID()}` }) {
  if (typeof client?.channel !== "function" || typeof client?.removeChannel !== "function") return null;
  let disposed = false;
  let subscribed = false;
  const invalidate = ()=>{ if (!disposed) void onInvalidate(); };
  const channel = client
    .channel(channelName)
    .on("postgres_changes", {
      event: "INSERT",
      schema: "public",
      table: "operator_message_recipients",
    }, invalidate)
    .on("postgres_changes", {
      event: "UPDATE",
      schema: "public",
      table: "operator_message_recipients",
    }, invalidate)
    .subscribe((status)=>{
      if (status !== "SUBSCRIBED") return;
      if (subscribed) invalidate();
      subscribed = true;
    });
  return Object.freeze({
    dispose() {
      if (disposed) return;
      disposed = true;
      void client.removeChannel(channel);
    },
  });
}

export function initializeOperatorMessages(root, client, identity, { onInvalidate = ()=>{} } = {}) {
  const workspace = root.getElementById("messagesWorkspace");
  if (!workspace) return null;
  if (workspace.dataset.initialized === "true") return workspace.operatorMessagesController || null;
  workspace.dataset.initialized = "true";

  const list = root.getElementById("messagesList");
  const empty = root.getElementById("messagesEmpty");
  const status = root.getElementById("messagesStatus");
  const listTitle = root.getElementById("messagesListTitle");
  const unreadCount = root.getElementById("messagesUnreadCount");
  const detail = root.getElementById("messagesDetail");
  const detailEmpty = root.getElementById("messagesDetailEmpty");
  const compose = root.getElementById("messagesCompose");
  const body = root.getElementById("messagesBody");
  const send = root.getElementById("messagesSend");
  const composeStatus = root.getElementById("messagesComposeStatus");
  const characterCount = root.getElementById("messagesCharacterCount");
  const recipientField = root.getElementById("messagesRecipientField");
  const recipient = root.getElementById("messagesRecipient");
  const recipientRetry = root.getElementById("messagesRecipientRetry");
  let mailbox = "received";
  let scope = "PERSONAL";
  let messages = [];
  let recipients = [];
  let recipientState = "loading";
  let selectedId = null;
  let loading = false;
  let messageLoadError = false;
  let sending = false;
  let returnMobileView = "list";
  let destroyed = false;
  let invalidationPublisher = onInvalidate;
  const abortController = new AbortController();
  const markingRead = new Set();

  async function rpc(name, parameters) {
    const request = client.rpc(name, parameters);
    const response = typeof request?.abortSignal === "function" ? await request.abortSignal(abortController.signal) : await request;
    if (destroyed) throw new Error("MESSAGES_DESTROYED");
    return response;
  }

  function setMobileView(view) {
    workspace.dataset.mobileView = view;
  }

  function setPanelMode(mode) {
    workspace.dataset.panelMode = mode;
    const composing = mode === "compose";
    compose.hidden = !composing;
    if (composing) {
      detail.hidden = true;
      detailEmpty.hidden = true;
      return;
    }
    showDetail(messages.find((message)=>message.id === selectedId));
  }

  function updateComposer() {
    const trimmed = body.value.trim();
    characterCount.textContent = `${body.value.length} / 4000`;
    recipientField.hidden = scope === "ALL";
    const recipientReady = scope === "ALL" || (recipientState === "ready" && UUID.test(recipient.value));
    send.disabled = sending || !recipientReady || !trimmed || identity?.role !== "owner";
  }

  function setRecipientOption(label, disabled = true) {
    const option = root.createElement("option");
    option.value = "";
    option.textContent = label;
    option.disabled = disabled;
    option.selected = true;
    recipient.replaceChildren(option);
  }

  function updatePersonalStatus() {
    if (scope !== "PERSONAL") return;
    composeStatus.textContent = recipientState === "loading" ? "Bevoegde ontvangers laden..."
      : recipientState === "error" ? "De ontvangers konden niet worden geladen. Probeer opnieuw."
      : recipientState === "empty" ? "Geen bevoegde ontvangers beschikbaar."
      : "Kies één bevoegde operator als ontvanger.";
  }

  async function loadRecipients() {
    if (destroyed || (recipientState === "loading" && recipients.length > 0)) return;
    const selectedRecipient = recipient.value;
    recipientState = "loading";
    recipient.disabled = true;
    recipientRetry.hidden = true;
    setRecipientOption("Bevoegde ontvangers laden...");
    updatePersonalStatus();
    updateComposer();
    try {
      const { data, error } = await rpc("list_operator_message_recipients_v1");
      if (error) throw error;
      if (!Array.isArray(data) || !data.every(validRecipient)) throw new Error("INVALID_RECIPIENT_ROSTER");
      if (new Set(data.map((item)=>item.operator_id)).size !== data.length) throw new Error("DUPLICATE_RECIPIENT");
      recipients = data;
      if (recipients.length === 0) {
        recipientState = "empty";
        setRecipientOption("Geen bevoegde ontvangers beschikbaar");
      } else {
        recipientState = "ready";
        const placeholder = root.createElement("option");
        placeholder.value = "";
        placeholder.textContent = "Kies een ontvanger";
        recipient.replaceChildren(placeholder);
        for (const item of recipients) {
          const option = root.createElement("option");
          option.value = item.operator_id;
          option.textContent = item.display_name;
          recipient.append(option);
        }
        recipient.disabled = false;
        if (recipients.some((item)=>item.operator_id === selectedRecipient)) recipient.value = selectedRecipient;
      }
    } catch {
      recipients = [];
      recipientState = "error";
      setRecipientOption("Ontvangers niet beschikbaar");
      recipientRetry.hidden = false;
    }
    updatePersonalStatus();
    updateComposer();
  }

  function showDetail(message) {
    if (workspace.dataset.panelMode === "compose") return;
    if (!message) {
      detail.hidden = true;
      detailEmpty.hidden = false;
      return;
    }
    detailEmpty.hidden = true;
    detail.hidden = false;
    root.getElementById("messagesDetailContext").textContent = message.message_scope === "ALL" ? "Iedereen" : "Persoon";
    root.getElementById("messagesDetailTitle").textContent = mailbox === "sent" ? recipientContext(message, mailbox) : message.sender_display_name;
    root.getElementById("messagesDetailSender").textContent = message.sender_display_name;
    root.getElementById("messagesDetailScope").textContent = recipientContext(message, mailbox);
    root.getElementById("messagesDetailTime").textContent = messageTimestamp(message.created_at);
    root.getElementById("messagesDetailBody").textContent = message.body;
    const state = root.getElementById("messagesDetailState");
    state.textContent = mailbox === "sent" ? "Verzonden" : message.read_at ? "Gelezen" : "Ongelezen";
    state.className = `badge ${mailbox === "received" && !message.read_at ? "badge--cyan" : ""}`.trim();
  }

  function renderList() {
    list.replaceChildren();
    unreadCount.textContent = String(messages.filter((message)=>mailbox === "received" && !message.read_at).length);
    empty.hidden = messages.length > 0 || loading || messageLoadError;
    for (const message of messages) {
      const item = root.createElement("li");
      const button = root.createElement("button");
      const heading = root.createElement("span");
      const meta = root.createElement("span");
      const sender = root.createElement("strong");
      const preview = root.createElement("span");
      const context = root.createElement("small");
      const time = root.createElement("time");
      const unread = mailbox === "received" && !message.read_at;
      const scopeLabel = message.message_scope === "ALL" ? "Iedereen" : "Persoon";
      button.type = "button";
      button.className = "messages-list-item";
      button.dataset.unread = String(unread);
      button.setAttribute("aria-current", String(message.id === selectedId));
      sender.textContent = mailbox === "sent" ? recipientContext(message, mailbox) : message.sender_display_name;
      preview.textContent = messagePreview(message.body);
      context.textContent = mailbox === "received" ? `${scopeLabel} · ${unread ? "Ongelezen" : "Gelezen"}` : scopeLabel;
      time.dateTime = message.created_at;
      time.textContent = messageTimestamp(message.created_at);
      button.setAttribute("aria-label", `${sender.textContent}. ${preview.textContent}. ${time.textContent}. ${unread ? "Ongelezen" : mailbox === "received" ? "Gelezen" : "Verzonden"}.`);
      heading.append(sender, preview);
      meta.append(context, time);
      button.append(heading, meta);
      button.addEventListener("click", async ()=>{
        if (destroyed) return;
        selectedId = message.id;
        setPanelMode("detail");
        if (unread && !markingRead.has(message.id)) {
          markingRead.add(message.id);
          status.textContent = "Leesstatus bijwerken...";
          const { data, error } = await rpc("mark_operator_message_read_v1", { p_message_id: message.id });
          if (!error && Number.isFinite(Date.parse(data?.read_at))) {
            message.read_at = data.read_at;
            status.textContent = "Bericht gemarkeerd als gelezen.";
            invalidationPublisher("messages");
          } else {
            status.textContent = "Het bericht is geopend, maar de leesstatus kon niet worden bijgewerkt. Probeer opnieuw.";
          }
          markingRead.delete(message.id);
        }
        renderList();
        showDetail(message);
        setMobileView("detail");
      });
      item.append(button);
      list.append(item);
    }
    showDetail(messages.find((message)=>message.id === selectedId));
  }

  async function loadMessages({ background = false } = {}) {
    if (destroyed || loading || !MAILBOXES.has(mailbox)) return false;
    loading = true;
    if (!background) {
      messageLoadError = false;
      status.textContent = "Berichten laden...";
      list.setAttribute("aria-busy", "true");
    }
    let refreshed = false;
    try {
      const { data, error } = await rpc("list_operator_messages_v1", { p_mailbox: mailbox, p_limit: 50 });
      if (error) throw error;
      if (!Array.isArray(data) || !data.every((message)=>validMessage(message, mailbox))) throw new Error("INVALID_MESSAGE_RESPONSE");
      messages = data;
      selectedId = messages.some((message)=>message.id === selectedId) ? selectedId : null;
      status.textContent = `${messages.length} ${messages.length === 1 ? "bericht" : "berichten"}`;
      refreshed = true;
    } catch {
      if (!background) {
        messages = [];
        selectedId = null;
        messageLoadError = true;
        status.textContent = "De berichten konden niet veilig worden geladen.";
      }
    } finally {
      loading = false;
      if (!background) list.setAttribute("aria-busy", "false");
      if (refreshed || !background) renderList();
    }
    return refreshed;
  }

  for (const button of root.querySelectorAll("[data-message-mailbox]")) {
    button.addEventListener("click", ()=>{
      mailbox = button.dataset.messageMailbox;
      for (const option of root.querySelectorAll("[data-message-mailbox]")) option.setAttribute("aria-pressed", String(option === button));
      listTitle.textContent = mailbox === "received" ? "Ontvangen" : "Verzonden";
      selectedId = null;
      setPanelMode("detail");
      setMobileView("list");
      void loadMessages();
    });
  }

  for (const button of root.querySelectorAll("[data-message-scope]")) {
    button.addEventListener("click", ()=>{
      scope = button.dataset.messageScope;
      for (const option of root.querySelectorAll("[data-message-scope]")) option.setAttribute("aria-pressed", String(option === button));
      composeStatus.textContent = scope === "ALL"
        ? "De server bepaalt alle actieve ontvangers en sluit de afzender uit."
        : "";
      updatePersonalStatus();
      updateComposer();
    });
  }

  body.addEventListener("input", updateComposer);
  recipient.addEventListener("change", updateComposer);
  recipientRetry.addEventListener("click", ()=>void loadRecipients());
  root.getElementById("messagesRefresh").addEventListener("click", ()=>void loadMessages());
  root.getElementById("messagesBack").addEventListener("click", ()=>{
    setPanelMode("detail");
    setMobileView("list");
  });
  root.getElementById("messagesComposeOpen").addEventListener("click", ()=>{
    returnMobileView = workspace.dataset.mobileView === "detail" ? "detail" : "list";
    setPanelMode("compose");
    setMobileView("compose");
    body.focus();
  });
  root.getElementById("messagesComposeCancel").addEventListener("click", ()=>{
    setPanelMode("detail");
    setMobileView(returnMobileView);
  });
  compose.addEventListener("submit", async (event)=>{
    event.preventDefault();
    const draft = body.value;
    const recipientId = scope === "PERSONAL" ? recipient.value : null;
    if (destroyed || sending || !draft.trim() || (scope === "PERSONAL" && !UUID.test(recipientId))) return;
    sending = true;
    composeStatus.textContent = "Bericht wordt veilig verzonden...";
    updateComposer();
    const { data: sentMessage, error } = await rpc("send_operator_message_v1", {
      p_message_scope: scope,
      p_recipient_operator_id: recipientId,
      p_body: draft,
    });
    sending = false;
    if (error) {
      composeStatus.textContent = "Verzenden is niet gelukt. Je concept is bewaard.";
    } else {
      invalidationPublisher("messages");
      body.value = "";
      recipient.value = "";
      composeStatus.textContent = "Bericht verzonden en blijvend opgeslagen.";
      selectedId = UUID.test(String(sentMessage?.id || "")) ? sentMessage.id : null;
      mailbox = "sent";
      for (const option of root.querySelectorAll("[data-message-mailbox]")) option.setAttribute("aria-pressed", String(option.dataset.messageMailbox === mailbox));
      listTitle.textContent = "Verzonden";
      await loadMessages();
      setPanelMode("detail");
      setMobileView("list");
    }
    updateComposer();
  });

  const controller = {
    destroy() {
      if (destroyed) return;
      destroyed = true;
      autoRefresh.dispose();
      heartbeat.dispose();
      realtime?.dispose();
      abortController.abort();
      sending = false;
      messages = [];
      recipients = [];
      selectedId = null;
      body.value = "";
      send.disabled = true;
      list.replaceChildren();
      for (const id of ["messagesDetailTitle", "messagesDetailSender", "messagesDetailScope", "messagesDetailTime", "messagesDetailBody"]) {
        root.getElementById(id).textContent = "";
      }
      detail.hidden = true;
      compose.hidden = true;
      workspace.hidden = true;
    },
    refresh() {
      if (!destroyed) return loadMessages();
      return undefined;
    },
    setInvalidationPublisher(publisher) {
      invalidationPublisher = typeof publisher === "function" ? publisher : ()=>{};
    },
  };
  const panel = workspace.closest?.("[data-module-panel]");
  const heartbeat = createOperatorRefreshHeartbeat({ root, moduleKey: "messages", titleElement: root.getElementById("messagesModuleTitle") });
  const autoRefresh = createOperatorAutoRefresh({
    moduleKey: "messages",
    refresh: ()=>loadMessages({ background: true }),
    isActive: ()=>!panel?.hidden,
    isBlocked: ()=>workspace.dataset.panelMode === "compose" || sending || markingRead.size > 0,
    documentTarget: root,
    windowTarget: root.defaultView,
    onLifecycle: heartbeat.update,
  });
  const realtime = createOperatorMessagesRealtime({ client, onInvalidate: autoRefresh.request });
  workspace.operatorMessagesController = controller;
  updateComposer();
  void loadRecipients();
  void loadMessages();
  return controller;
}