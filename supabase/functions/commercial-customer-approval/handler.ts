const COOKIE_NAME = "__Host-lws_commercial_session";
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const TOKEN_PATTERN = /^[A-Za-z0-9_-]{32,256}$/;

type RedemptionResult = Readonly<{
  projectId: string;
  previewAccessId: string;
  previewVersionId: string;
  expiresAt: string;
}>;

export type CustomerApprovalContext = Readonly<{
  projectId: string;
  currentState: string;
  revision: number;
  previewAccessId: string;
  previewVersionId: string;
  previewVersionNumber: number;
  previewContentReference: string;
  previewContentSha256: string;
  statementVersion: string;
  statementSha256: string;
  statementText: string;
  statementSection: string;
  sourceFilename: string;
  sourceDriveId: string;
  sourceByteLength: number;
  approvalReplayAvailable: boolean;
  approvalExpectedState: string;
  approvalExpectedRevision: number;
  sessionExpiresAt: string;
  deliveryDocument: Readonly<{
    viewDerivativeId: string;
    documentVersion: number;
    pdfSha256: string;
    sourceDocxSha256: string;
    pdfBytes: number;
  }> | null;
  deliveryDocumentViewed: boolean;
  acceptance: Readonly<{
    acceptedAt: string;
    documentVersion: number;
    pdfSha256: string;
    statementVersion: string;
  }> | null;
}>;

type ApprovalResult = Readonly<{
  projectId: string;
  resultingState: string;
  revision: number;
  commandType: string;
}>;

export type CommercialCustomerApprovalService = Readonly<{
  publicOrigin: string;
  randomBytes(): Uint8Array;
  redeemAccess(input: Readonly<{
    accessTokenDigest: string;
    projectId: string;
    sessionDigest: string;
  }>): PromiseLike<RedemptionResult>;
  resolveContext(input: Readonly<{
    sessionDigest: string;
    projectId: string;
  }>): PromiseLike<CustomerApprovalContext>;
  serveDocument(input: Readonly<{
    sessionDigest: string;
    projectId: string;
  }>): PromiseLike<Response>;
  submitApproval(input: Readonly<{
    sessionDigest: string;
    projectId: string;
    expectedState: string;
    expectedRevision: number;
    idempotencyKey: string;
    previewVersionId: string;
    statementVersion: string;
    statementSha256: string;
    viewedDocumentVersion: number;
    viewedPdfSha256: string;
  }>): PromiseLike<ApprovalResult>;
}>;

const SHA256_PATTERN = /^[0-9a-f]{64}$/;

function text(status: number, code: string): Response {
  return new Response(code, {
    status,
    headers: {
      "cache-control": "private, no-store",
      "content-type": "text/plain; charset=utf-8",
    },
  });
}

function toHex(bytes: Uint8Array): string {
  return [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function sha256(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  return toHex(new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)));
}

function cookieToken(request: Request): string {
  const cookies = request.headers.get("cookie") ?? "";
  return /(?:^|;\s*)__Host-lws_commercial_session=([a-f0-9]{64})(?:;|$)/.exec(cookies)?.[1] ?? "";
}

async function deterministicUuid(value: string): Promise<string> {
  const bytes = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value))).slice(0, 16);
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = toHex(bytes);
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "cache-control": "private, no-store",
      "content-type": "application/json; charset=utf-8",
      "x-content-type-options": "nosniff",
    },
  });
}

function errorResponse(error: unknown): Response {
  const message = error instanceof Error ? error.message : "";
  if (message.includes("ACCESS_DENIED")) return text(401, "SESSION_INVALID");
  if (message.includes("PREVIEW_VERSION_MISMATCH")) return text(409, "PREVIEW_VERSION_MISMATCH");
  if (message.includes("WEBSITE_DELIVERY_VIEW_NOT_FOUND")) return text(404, "DOCUMENT_NOT_AVAILABLE");
  if (message.includes("WEBSITE_DELIVERY_VIEW_HASH_MISMATCH")) return text(409, "DOCUMENT_INTEGRITY_ERROR");
  if (message.includes("WEBSITE_DELIVERY_VIEW_EVIDENCE_REQUIRED")) return text(409, "DOCUMENT_VIEW_REQUIRED");
  if (message.includes("WEBSITE_DELIVERY_DOCUMENT_VERSION_CHANGED")) return text(409, "DOCUMENT_VERSION_CHANGED");
  if (message.includes("WEBSITE_DELIVERY_ACCEPTANCE_INPUT_INVALID")) return text(400, "VIEWED_DOCUMENT_REQUIRED");
  if (message.includes("CONCURRENT_MODIFICATION")) return text(409, "APPROVAL_CONTEXT_CHANGED");
  if (message.includes("WEBSITE_DELIVERY_ALREADY_ACCEPTED")) return text(409, "APPROVAL_NOT_AVAILABLE");
  return text(409, "APPROVAL_NOT_AVAILABLE");
}

function approvalPage(): Response {
  const html = `<!doctype html>
<html lang="nl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="referrer" content="no-referrer"><title>Website oplevering | Lorenzo Web Solutions</title>
<style>
:root{color-scheme:light;--ink:#17211d;--paper:#f5f2ea;--panel:#fffdf8;--line:#c8c4b8;--accent:#14634b;--danger:#9a342c}*{box-sizing:border-box}[hidden]{display:none!important}body{margin:0;background:linear-gradient(135deg,#eef3ee 0,#f5f2ea 48%,#ece7dc 100%);color:var(--ink);font-family:"Trebuchet MS",sans-serif;min-height:100vh}main{width:min(1180px,calc(100% - 32px));margin:clamp(18px,4vh,48px) auto;padding:clamp(20px,4vw,44px);background:var(--panel);border:1px solid var(--line);box-shadow:0 24px 70px #17211d1a}header{border-bottom:3px solid var(--ink);padding-bottom:20px;margin-bottom:24px}.brand{font-size:.78rem;letter-spacing:.12em;text-transform:uppercase;color:var(--accent)}h1{font-family:Georgia,serif;font-size:clamp(2rem,7vw,3.7rem);font-weight:500;line-height:1;margin:.35em 0 0}.meta{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:14px;margin:24px 0}.meta div{border-top:1px solid var(--line);padding-top:9px}.label{display:block;color:#59635e;font-size:.76rem;text-transform:uppercase}.value{overflow-wrap:anywhere}button:focus-visible{outline:3px solid var(--ink);outline-offset:3px}button{min-height:48px;border:0;padding:0 24px;background:var(--accent);color:white;font:700 1rem "Trebuchet MS",sans-serif;cursor:pointer}button:disabled{background:#9ca39f;cursor:not-allowed}.status{min-height:24px;margin:16px 0;color:#47524c}.error{color:var(--danger)}.viewer{width:100%;height:min(76vh,920px);min-height:520px;margin-top:18px;border:1px solid var(--line);background:#e4e2dc}.section-title{font-family:Georgia,serif;font-weight:500;font-size:1.45rem;margin:32px 0 0}.statement{margin:18px 0 8px;padding:4px 0 4px 22px;border-left:4px solid var(--accent);font-family:Georgia,serif;font-size:1.06rem;line-height:1.7}.confirm{display:flex;gap:12px;align-items:flex-start;margin:18px 0}.confirm input{width:22px;height:22px;margin:2px 0 0;accent-color:var(--ink);flex:none}input:focus-visible{outline:3px solid var(--ink);outline-offset:3px}#approve{width:100%}@media(max-width:560px){.meta{grid-template-columns:1fr}main{margin:0;width:100%;min-height:100vh;border:0;box-shadow:none}.viewer{height:72vh;min-height:420px}}
</style></head><body><main><header><div class="brand">Lorenzo Web Solutions</div><h1>Website opleverdocument</h1></header>
<p class="status" id="page-status" role="status">Beveiligde oplevering laden…</p><section id="content" hidden><div class="meta"><div><span class="label">Projectreferentie</span><strong class="value" id="project"></strong></div><div><span class="label">Opleverversie</span><strong class="value" id="version"></strong></div><div><span class="label">Documentbron</span><strong class="value" id="source"></strong></div></div><p class="status" id="status" role="status"></p><button id="view-document" type="button">Opleverdocument bekijken</button><iframe class="viewer" id="document-frame" title="Volledig geregistreerd opleverdocument" hidden></iframe><section id="acceptance" hidden><h2 class="section-title" id="statement-section"></h2><blockquote class="statement" id="statement"></blockquote><p class="status" id="action-status" role="status"></p><label class="confirm" id="confirm-label" for="confirmed"><input type="checkbox" id="confirmed"><span>Ik heb de website gecontroleerd en bevestig deze formele aanvaarding.</span></label><button id="approve" type="button" disabled>Goedkeuring vastleggen</button></section></section></main>
<script type="module">
const pageStatus=document.querySelector('#page-status'),status=document.querySelector('#status'),content=document.querySelector('#content'),button=document.querySelector('#view-document'),frame=document.querySelector('#document-frame'),acceptance=document.querySelector('#acceptance'),actionStatus=document.querySelector('#action-status'),confirmLabel=document.querySelector('#confirm-label'),confirmed=document.querySelector('#confirmed'),approve=document.querySelector('#approve'),endpoint=location.pathname.endsWith('/')?location.pathname.slice(0,-1):location.pathname;let projectId=new URLSearchParams(location.search).get('project_id')||'',documentUrl='',current=null,viewed=null,busy=false;
const showError=(message)=>{const target=content.hidden?pageStatus:status;target.textContent=message;target.className='status error';};
const syncApprove=()=>{approve.disabled=!(confirmed.checked&&viewed&&current&&!current.acceptance&&!busy);};
function showAcceptance(){if(!current)return;if(current.acceptance){acceptance.hidden=false;confirmLabel.hidden=true;approve.hidden=true;actionStatus.className='status';actionStatus.textContent='Uw formele goedkeuring is vastgelegd. Documentversie '+current.acceptance.documentVersion+' · '+new Date(current.acceptance.acceptedAt).toLocaleString('nl-BE');return;}if(viewed&&current.currentState==='M2_PAYMENT_RECEIVED'&&current.deliveryDocument&&current.deliveryDocument.documentVersion===viewed.version&&current.deliveryDocument.pdfSha256===viewed.sha){acceptance.hidden=false;confirmLabel.hidden=false;approve.hidden=false;actionStatus.className='status';actionStatus.textContent='Klaar voor uw beslissing.';}syncApprove();}
async function context(){const response=await fetch(endpoint+'/context?project_id='+encodeURIComponent(projectId),{credentials:'same-origin'});if(!response.ok)throw new Error(await response.text());const data=await response.json();current=data;document.querySelector('#project').textContent=data.projectId;document.querySelector('#version').textContent='Previewversie '+data.previewVersionNumber;document.querySelector('#source').textContent=data.statementVersion+' · '+data.sourceFilename;document.querySelector('#statement-section').textContent=data.statementSection;document.querySelector('#statement').textContent=data.statementText;pageStatus.hidden=true;content.hidden=false;status.textContent='Het geregistreerde opleverdocument is beschikbaar.';showAcceptance();return data;}
const fragment=new URLSearchParams(location.hash.slice(1));const fragmentProject=fragment.get('project_id'),accessToken=fragment.get('access');if(fragmentProject&&accessToken){projectId=fragmentProject;history.replaceState(null,'',location.pathname+'?project_id='+encodeURIComponent(projectId));fetch(endpoint+'/session',{method:'POST',credentials:'same-origin',headers:{'content-type':'application/json'},body:JSON.stringify({projectId,accessToken})}).then(response=>{if(!response.ok)throw new Error('LINK_INVALID');return context();}).catch(()=>showError('Deze opleverlink is ongeldig of verlopen.'));}else if(projectId){context().catch(()=>showError('Deze sessie is ongeldig of verlopen.'));}else{showError('Deze opleverlink is onvolledig.');}
button.addEventListener('click',async()=>{button.disabled=true;status.textContent='Opleverdocument laden…';try{const response=await fetch(endpoint+'/document?project_id='+encodeURIComponent(projectId),{credentials:'same-origin'});if(!response.ok)throw new Error(await response.text());const blob=await response.blob();if(documentUrl)URL.revokeObjectURL(documentUrl);documentUrl=URL.createObjectURL(blob);frame.src=documentUrl;frame.hidden=false;document.querySelector('#version').textContent='Documentversie '+response.headers.get('x-lws-document-version');viewed={version:Number(response.headers.get('x-lws-document-version')),sha:response.headers.get('x-lws-document-sha256')||''};confirmed.checked=false;status.textContent='Volledig geregistreerd opleverdocument.';showAcceptance();}catch{showError('Het opleverdocument kon niet veilig worden geladen.');}finally{button.disabled=false;}});addEventListener('pagehide',()=>{if(documentUrl)URL.revokeObjectURL(documentUrl);});
confirmed.addEventListener('change',syncApprove);
approve.addEventListener('click',async()=>{if(approve.disabled||busy||!viewed)return;busy=true;syncApprove();confirmed.disabled=true;actionStatus.className='status';actionStatus.textContent='Goedkeuring vastleggen…';try{const response=await fetch(endpoint+'/approval',{method:'POST',credentials:'same-origin',headers:{'content-type':'application/json'},body:JSON.stringify({projectId,confirmed:true,viewedDocumentVersion:viewed.version,viewedPdfSha256:viewed.sha})});if(!response.ok)throw new Error(await response.text());await response.text().catch(()=>'');confirmLabel.hidden=true;approve.hidden=true;actionStatus.className='status';actionStatus.textContent='Uw formele goedkeuring is vastgelegd. Documentversie '+viewed.version;context().catch(()=>{});}catch(error){const code=String(error&&error.message||'');actionStatus.className='status error';actionStatus.textContent=code==='DOCUMENT_VERSION_CHANGED'?'Het opleverdocument is intussen gewijzigd. Open het document opnieuw.':code==='DOCUMENT_VIEW_REQUIRED'?'Open eerst het volledige opleverdocument.':'Goedkeuring kon niet worden vastgelegd. Vernieuw de pagina en controleer de actuele versie.';}finally{busy=false;confirmed.disabled=false;syncApprove();}});
</script></body></html>`;
  return new Response(html, {
    status: 200,
    headers: {
      "cache-control": "private, no-store",
      "content-security-policy": "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; frame-src blob:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
      "content-type": "text/html; charset=utf-8",
      "referrer-policy": "no-referrer",
      "x-content-type-options": "nosniff",
    },
  });
}

export async function handleCommercialCustomerApproval(
  request: Request,
  service: CommercialCustomerApprovalService,
): Promise<Response> {
  const url = new URL(request.url);
  const pathname = url.pathname.replace(/\/$/, "");

  if (request.method === "GET" && (pathname === "" || pathname.endsWith("/commercial-customer-approval"))) {
    return approvalPage();
  }

  if (pathname.endsWith("/context")) {
    if (request.method !== "GET") return text(405, "METHOD_NOT_ALLOWED");
    const projectId = url.searchParams.get("project_id") ?? "";
    const sessionToken = cookieToken(request);
    if (!sessionToken) return text(401, "SESSION_REQUIRED");
    if (!UUID_PATTERN.test(projectId)) return text(400, "INVALID_REQUEST");
    try {
      return json(200, await service.resolveContext({
        sessionDigest: await sha256(sessionToken),
        projectId,
      }));
    } catch (error) {
      return errorResponse(error);
    }
  }

  if (pathname.endsWith("/document")) {
    if (request.method !== "GET") return text(405, "METHOD_NOT_ALLOWED");
    const projectId = url.searchParams.get("project_id") ?? "";
    const sessionToken = cookieToken(request);
    if (!sessionToken) return text(401, "SESSION_REQUIRED");
    if (!UUID_PATTERN.test(projectId)) return text(400, "INVALID_REQUEST");
    try {
      return await service.serveDocument({
        sessionDigest: await sha256(sessionToken),
        projectId,
      });
    } catch (error) {
      return errorResponse(error);
    }
  }

  if (pathname.endsWith("/approval")) {
    if (request.method !== "POST") return text(405, "METHOD_NOT_ALLOWED");
    if (!service.publicOrigin || request.headers.get("origin") !== service.publicOrigin) {
      return text(403, "ORIGIN_FORBIDDEN");
    }
    const sessionToken = cookieToken(request);
    if (!sessionToken) return text(401, "SESSION_REQUIRED");

    let body: {
      projectId?: unknown;
      confirmed?: unknown;
      viewedDocumentVersion?: unknown;
      viewedPdfSha256?: unknown;
    };
    try {
      body = await request.json();
    } catch {
      return text(400, "INVALID_REQUEST");
    }
    if (typeof body.projectId !== "string" || !UUID_PATTERN.test(body.projectId) || body.confirmed !== true) {
      return text(400, "EXPLICIT_CONFIRMATION_REQUIRED");
    }
    const viewedDocumentVersion = body.viewedDocumentVersion;
    const viewedPdfSha256 = body.viewedPdfSha256;
    if (
      typeof viewedDocumentVersion !== "number" || !Number.isSafeInteger(viewedDocumentVersion)
      || viewedDocumentVersion < 1
      || typeof viewedPdfSha256 !== "string" || !SHA256_PATTERN.test(viewedPdfSha256)
    ) {
      return text(400, "VIEWED_DOCUMENT_REQUIRED");
    }

    try {
      const sessionDigest = await sha256(sessionToken);
      const context = await service.resolveContext({ sessionDigest, projectId: body.projectId });
      if (context.currentState !== "M2_PAYMENT_RECEIVED" && !context.approvalReplayAvailable) {
        return text(409, "APPROVAL_NOT_AVAILABLE");
      }
      // The browser only states what it viewed; the server re-derives the current document and
      // requires this session's own view receipt. The database re-checks both when recording.
      const document = context.deliveryDocument;
      if (!document) return text(409, "DOCUMENT_NOT_AVAILABLE");
      if (document.documentVersion !== viewedDocumentVersion || document.pdfSha256 !== viewedPdfSha256) {
        return text(409, "DOCUMENT_VERSION_CHANGED");
      }
      if (!context.deliveryDocumentViewed) return text(409, "DOCUMENT_VIEW_REQUIRED");
      const idempotencyKey = await deterministicUuid([
        context.projectId,
        context.previewAccessId,
        context.previewVersionId,
        context.statementVersion,
        String(document.documentVersion),
        document.pdfSha256,
        "customer-approval",
      ].join("|"));
      return json(200, await service.submitApproval({
        sessionDigest,
        projectId: context.projectId,
        expectedState: context.approvalExpectedState,
        expectedRevision: context.approvalExpectedRevision,
        idempotencyKey,
        previewVersionId: context.previewVersionId,
        statementVersion: context.statementVersion,
        statementSha256: context.statementSha256,
        viewedDocumentVersion: document.documentVersion,
        viewedPdfSha256: document.pdfSha256,
      }));
    } catch (error) {
      return errorResponse(error);
    }
  }

  if (!pathname.endsWith("/session")) return text(404, "NOT_FOUND");
  if (request.method !== "POST") return text(405, "METHOD_NOT_ALLOWED");
  if (!service.publicOrigin || request.headers.get("origin") !== service.publicOrigin) {
    return text(403, "ORIGIN_FORBIDDEN");
  }

  let body: { projectId?: unknown; accessToken?: unknown };
  try {
    body = await request.json();
  } catch {
    return text(400, "INVALID_REQUEST");
  }
  if (
    typeof body.projectId !== "string"
    || !UUID_PATTERN.test(body.projectId)
    || typeof body.accessToken !== "string"
    || !TOKEN_PATTERN.test(body.accessToken)
  ) {
    return text(400, "INVALID_REQUEST");
  }

  const sessionToken = toHex(service.randomBytes());
  if (!TOKEN_PATTERN.test(sessionToken)) return text(500, "SERVER_CONFIGURATION_ERROR");
  try {
    const redemption = await service.redeemAccess({
      accessTokenDigest: await sha256(body.accessToken),
      projectId: body.projectId,
      sessionDigest: await sha256(sessionToken),
    });
    const expires = new Date(redemption.expiresAt);
    if (Number.isNaN(expires.getTime())) return text(500, "SERVER_CONFIGURATION_ERROR");
    return new Response(null, {
      status: 204,
      headers: {
        "cache-control": "private, no-store",
        "set-cookie": `${COOKIE_NAME}=${sessionToken}; HttpOnly; Secure; SameSite=Strict; Path=/; Expires=${expires.toUTCString()}`,
      },
    });
  } catch {
    return text(403, "ACCESS_DENIED");
  }
}