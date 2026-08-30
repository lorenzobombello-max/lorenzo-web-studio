import { corsHeaders, rejectIfOriginNotAllowed } from "../_shared/cors.ts";
export const SDF_CONFIRMATION_VERSION = "SDF_QUALIFICATION_CONFIRMATION_NL_BE_v1";
export const SDF_CONFIRMATION_TEXT = "Ik bevestig dat de ingevulde informatie naar best vermogen volledig en correct is. Ik begrijp dat deze kwalificatie geen offerte, prijsbevestiging of aanvaarding van een opdracht vormt.";
const MAX_BODY_BYTES = 24 * 1024;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

interface RpcResult { data: unknown; error: { message?: string; code?: string } | null }
export interface SdfQualificationDependencies { hashCapability(rawToken: string): Promise<string>; rpc(name: string, parameters: Record<string, unknown>): Promise<RpcResult> }
class RequestError extends Error { constructor(readonly status: number, readonly code: string) { super(code); } }

function json(status: number, body: Record<string, unknown>, origin: string | null) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders(origin), "content-type": "application/json", "cache-control": "no-store", "referrer-policy": "no-referrer" } });
}

async function body(request: Request): Promise<Record<string, unknown>> {
  if (request.headers.get("content-type")?.split(";",1)[0].trim().toLowerCase() !== "application/json") throw new RequestError(415,"UNSUPPORTED_CONTENT_TYPE");
  const text = await request.text();
  if (new TextEncoder().encode(text).byteLength > MAX_BODY_BYTES) throw new RequestError(413,"BODY_TOO_LARGE");
  try { const value=JSON.parse(text); if (!value || typeof value!=="object" || Array.isArray(value)) throw new Error(); return value; }
  catch { throw new RequestError(400,"INVALID_JSON"); }
}

function bearer(request: Request) {
  const match=(request.headers.get("authorization")||"").match(/^Bearer\s+([A-Za-z0-9_-]{32,256})$/);
  if (!match) throw new RequestError(401,"INVALID_SDF_INTAKE_TOKEN");
  return match[1];
}
async function sha256(value: string) { const bytes=new Uint8Array(await crypto.subtle.digest("SHA-256",new TextEncoder().encode(value))); return Array.from(bytes,b=>b.toString(16).padStart(2,"0")).join(""); }
function revision(value: unknown) { if (!Number.isSafeInteger(value) || Number(value)<0) throw new RequestError(400,"INVALID_EXPECTED_REVISION"); return Number(value); }

export async function handleSdfQualificationIntake(request: Request, dependencies: SdfQualificationDependencies): Promise<Response> {
  const origin=request.headers.get("origin");
  if (request.method==="OPTIONS") return new Response(null,{status:204,headers:corsHeaders(origin)});
  const blocked=rejectIfOriginNotAllowed(request); if (blocked) return blocked;
  if (request.method!=="POST" || new URL(request.url).search) return json(405,{ok:false,code:"METHOD_NOT_ALLOWED"},origin);
  try {
    const rawToken=bearer(request); const capabilityDigest=await dependencies.hashCapability(rawToken); const input=await body(request);
    const action=input.action;
    if (!Object.keys(input).every(key=>["action","expected_revision","answers","idempotency_key","confirmation_accepted","confirmation_version"].includes(key))) throw new RequestError(400,"INVALID_REQUEST_SHAPE");
    if (!['inspect','save_draft','submit'].includes(String(action))) throw new RequestError(400,"INVALID_ACTION");
    const operation=action==='submit'?'submit':'inspect_save';
    const limited=await dependencies.rpc("consume_sdf_qualification_rate_limit_v1",{p_pseudonymous_key:capabilityDigest,p_operation:operation});
    if (limited.error) throw new RequestError(503,"RATE_LIMIT_UNAVAILABLE");
    if (limited.data!==true) throw new RequestError(429,"RATE_LIMITED");
    let result: RpcResult;
    if (action==='inspect') result=await dependencies.rpc("inspect_sdf_qualification_intake_v1",{p_customer_capability_digest:capabilityDigest});
    else if (action==='save_draft') {
      if (!input.answers || typeof input.answers!=="object" || Array.isArray(input.answers)) throw new RequestError(400,"INVALID_ANSWERS");
      result=await dependencies.rpc("save_sdf_qualification_intake_draft_v1",{p_customer_capability_digest:capabilityDigest,p_expected_revision:revision(input.expected_revision),p_answers:input.answers});
    } else {
      if (typeof input.idempotency_key!=="string" || !UUID.test(input.idempotency_key)) throw new RequestError(400,"INVALID_IDEMPOTENCY_KEY");
      if (input.confirmation_accepted!==true || input.confirmation_version!==SDF_CONFIRMATION_VERSION) throw new RequestError(400,"INVALID_CONFIRMATION");
      result=await dependencies.rpc("submit_sdf_qualification_intake_v1",{p_customer_capability_digest:capabilityDigest,p_expected_revision:revision(input.expected_revision),p_confirmation_accepted:true,p_confirmation_version:SDF_CONFIRMATION_VERSION,p_confirmation_sha256:await sha256(SDF_CONFIRMATION_TEXT),p_idempotency_key:input.idempotency_key});
    }
    if (result.error) {
      const code=result.error.message||"SDF_INTAKE_REQUEST_FAILED";
      const status=code.includes("ACCESS_DENIED")?401:code.includes("REVISION_CONFLICT")?409:code.includes("TRANSITION_NOT_ALLOWED")?409:code.includes("INVALID_")?400:500;
      return json(status,{ok:false,code},origin);
    }
    return json(200,{ok:true,result:result.data,...(action==='inspect'?{confirmation:{version:SDF_CONFIRMATION_VERSION,text:SDF_CONFIRMATION_TEXT,sha256:await sha256(SDF_CONFIRMATION_TEXT)}}:{})},origin);
  } catch (error) {
    const problem=error instanceof RequestError?error:new RequestError(500,"SDF_INTAKE_REQUEST_FAILED");
    return json(problem.status,{ok:false,code:problem.code},origin);
  }
}