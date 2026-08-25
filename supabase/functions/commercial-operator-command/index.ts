import { createClient } from "npm:@supabase/supabase-js@2";
import {
  executeAssignmentOperatorRosterTransport,
  executeDossierAssignmentMutationTransport,
  executeDossierAssignmentReadTransport,
  executeDossierLifecycleTransport,
  handleCommercialOperator,
  withCommercialOperatorCors
} from "./handler.ts";
import {
  createApprovalTokenForIdempotencyKey,
  createInternalE2EIntakeTokenForIdempotencyKey,
  deriveAdminIntakeCapability,
  hashAdminIntakeToken,
  hashApprovalToken,
  hashIntakeToken,
} from "../_shared/security.ts";
import {
  signOperatorCursor,
  verifyOperatorCursor,
  type OperatorCursorPosition,
  type OperatorCursorRequest,
} from "../_shared/operator-cursor.ts";

type OperatorApplicationCursorInput = Readonly<{
  zone: OperatorCursorRequest["zone"];
  operational_status: string | null;
  year?: number | null;
  quarter?: OperatorCursorRequest["quarter"];
  request_kind: OperatorCursorRequest["requestKind"];
  search: string | null;
}>;

type OperatorApplicationListV2Input = OperatorApplicationCursorInput & Readonly<{
  year: number | null;
  quarter: OperatorCursorRequest["quarter"];
  cursor: string | null;
  limit: number;
}>;

type OperatorApplicationFacetsV2Input = Omit<OperatorApplicationCursorInput, "year" | "quarter">;
type DossierAssignmentActionInput = Readonly<{
  action: "get_dossier_assignment";
  dossier_reference: string;
}> | Readonly<{
  action: "assign_dossier";
  dossier_reference: string;
  assignee_operator_id: string;
  expected_revision: number;
  idempotency_key: string;
  reason: string | null;
}>;
type DossierAssignmentClient = Parameters<typeof executeDossierAssignmentReadTransport>[0];
type ValidatedApplicationActionInput = Record<string, unknown> & Readonly<{
  action: string;
  intake_id: string;
  event_type: string;
  expected_revision: number;
  idempotency_key: string;
  reason: string | null;
  quote_request_id: string | null;
  project_id: string;
  operation: string;
  canonical_domain: string;
  evidence: string;
  run_id: string;
  terminal_status: string;
  run_label: string;
  ttl_minutes: number;
  limit: number;
  offset: number;
  support_reference: string | null;
  application_reference: string | null;
  dossier_reference: string;
  assignee_operator_id: string;
}>;
type ValidatedDossierLifecycleActionInput = ValidatedApplicationActionInput & Readonly<{
  action: "archive_dossier" | "reactivate_dossier" | "trash_dossier" | "restore_dossier";
  quote_request_id: string;
  reason: string;
}>;
type ValidatedCommercialCommandInput = Readonly<{
  project_id: string;
  command_type: string;
  expected_state: string;
  expected_revision: number;
  idempotency_key: string;
  payload: Record<string, unknown>;
}>;

type OperatorCursorDatabasePosition = Readonly<{
  dossier_date: string;
  quote_request_id: string;
}>;

async function sha256(value: string): Promise<string> {
  const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(bytes)].map((byte)=>byte.toString(16).padStart(2, "0")).join("");
}

function isDossierLifecycleAction(input: ValidatedApplicationActionInput): input is ValidatedDossierLifecycleActionInput {
  return input.action === "archive_dossier"
    || input.action === "reactivate_dossier"
    || input.action === "trash_dossier"
    || input.action === "restore_dossier";
}

export async function executeCallerJwtDossierAssignmentAction(
  jwt: string,
  input: DossierAssignmentActionInput,
  clientFor: (jwt: string)=>DossierAssignmentClient
): Promise<unknown> {
  const client = clientFor(jwt);
  return input.action === "get_dossier_assignment"
    ? await executeDossierAssignmentReadTransport(client, input)
    : await executeDossierAssignmentMutationTransport(client, input);
}

export async function executeCallerJwtAssignmentRosterAction(
  jwt: string,
  clientFor: (jwt: string)=>DossierAssignmentClient
): Promise<unknown> {
  return await executeAssignmentOperatorRosterTransport(clientFor(jwt));
}

if (import.meta.main) Deno.serve((request)=>withCommercialOperatorCors(request, ()=>{
  const url = Deno.env.get("SUPABASE_URL"), anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !anonKey) return new Response(JSON.stringify({
    ok: false,
    code: "SERVER_CONFIGURATION_ERROR"
  }), {
    status: 500,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store"
    }
  });
  const clientFor = (jwt: string)=>createClient(url, anonKey, {
      global: {
        headers: {
          Authorization: `Bearer ${jwt}`
        }
      },
      auth: {
        persistSession: false,
        autoRefreshToken: false
      }
    });
  const serviceClient = ()=>{
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!serviceRoleKey) throw new Error("SERVER_CONFIGURATION_ERROR");
    return createClient(url, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false }
    });
  };
  const cursorRequest = (input: OperatorApplicationCursorInput): OperatorCursorRequest=>({
    zone: input.zone,
    operationalStatus: input.operational_status,
    year: input.year ?? null,
    quarter: input.quarter ?? null,
    requestKind: input.request_kind,
    search: input.search,
  });
  return handleCommercialOperator(request, {
    now: ()=>Date.now(),
    verifyUser: async (jwt: string)=>{
      const { data, error } = await clientFor(jwt).auth.getUser(jwt);
      return error || !data.user ? null : {
        id: data.user.id
      };
    },
    authorizeApplicationReader: async (jwt: string)=>{
      const { error } = await clientFor(jwt).rpc("authorize_operator_application_reader_v2");
      if (error) throw new Error(error.message);
    },
    verifyOperatorCursor: async (cursor: string, input: OperatorApplicationListV2Input)=>
      await verifyOperatorCursor(cursor, cursorRequest(input)),
    signOperatorCursor: async (position: OperatorCursorDatabasePosition, input: OperatorApplicationListV2Input)=>await signOperatorCursor({
      dossierDate: position.dossier_date,
      quoteRequestId: position.quote_request_id,
    }, cursorRequest(input)),
    executeApplicationListV2: async (actorAuthUserId: string, input: OperatorApplicationListV2Input, position: OperatorCursorPosition | null)=>{
      const { data, error } = await serviceClient().rpc("list_operator_applications_v2", {
        p_actor_auth_user_id: actorAuthUserId,
        p_zone: input.zone,
        p_operational_status: input.operational_status,
        p_year: input.year,
        p_quarter: input.quarter,
        p_request_kind: input.request_kind,
        p_search: input.search,
        p_cursor_date: position?.dossierDate ?? null,
        p_cursor_id: position?.quoteRequestId ?? null,
        p_limit: input.limit,
      });
      if (error) throw new Error(error.message);
      return data;
    },
    executeApplicationFacetsV2: async (actorAuthUserId: string, input: OperatorApplicationFacetsV2Input)=>{
      const { data, error } = await serviceClient().rpc("get_operator_dossier_facets_v2", {
        p_actor_auth_user_id: actorAuthUserId,
        p_zone: input.zone,
        p_operational_status: input.operational_status,
        p_request_kind: input.request_kind,
        p_search: input.search,
      });
      if (error) throw new Error(error.message);
      return data;
    },
    consumeRateLimit: async (jwt: string, projectId: string)=>{
      const { data, error } = await clientFor(jwt).rpc("consume_commercial_operator_rate_limit_v1", {
        p_project_id: projectId,
        p_max_requests: 60,
        p_window_seconds: 60
      });
      if (error) throw new Error(error.message);
      return data;
    },
    executeApplicationAction: async (jwt: string, input: ValidatedApplicationActionInput, actorAuthUserId: string)=>{
      if (input.action === "get_assignment_operator_roster") {
        return await executeCallerJwtAssignmentRosterAction(jwt, clientFor);
      }
      if (input.action === "get_dossier_assignment" || input.action === "assign_dossier") {
        return await executeCallerJwtDossierAssignmentAction(jwt, input as DossierAssignmentActionInput, clientFor);
      }
      const client = clientFor(jwt);
      if (["interrupt_intake", "resume_intake", "cancel_intake", "reactivate_intake"].includes(input.action)) {
        const { data, error } = await client.rpc("execute_operator_intake_lifecycle_command_v1", {
          p_intake_id: input.intake_id,
          p_event_type: input.event_type,
          p_expected_revision: input.expected_revision,
          p_idempotency_key: input.idempotency_key,
          p_reason: input.reason,
        });
        if (error) throw new Error(error.message);
        return data;
      }
      if (isDossierLifecycleAction(input)) {
        return await executeDossierLifecycleTransport(
          (args)=>serviceClient().rpc("issue_operator_dossier_lifecycle_edge_capability_v1", args),
          (args)=>client.rpc("execute_operator_dossier_lifecycle_command_v1", args),
          actorAuthUserId,
          input
        );
      }
      if (["bind_project_site", "rotate_project_site"].includes(input.action)) {
        const { data, error } = await client.rpc("execute_operator_project_site_command_v1", {
          p_project_id: input.project_id,
          p_operation: input.operation,
          p_expected_revision: input.expected_revision,
          p_idempotency_key: input.idempotency_key,
          p_canonical_domain: input.canonical_domain,
          p_evidence: input.evidence,
        });
        if (error) throw new Error(error.message);
        return data;
      }
      if (input.action === "create_internal_e2e_run") {
        const approvalToken = await createApprovalTokenForIdempotencyKey(input.idempotency_key);
        const intakeToken = await createInternalE2EIntakeTokenForIdempotencyKey(input.idempotency_key);
        const intakeTokenHash = await hashIntakeToken(intakeToken);
        const adminToken = await deriveAdminIntakeCapability(intakeTokenHash);
        const requestFingerprint = await sha256(JSON.stringify({
          contract_version: 1,
          run_label: input.run_label,
          ttl_minutes: input.ttl_minutes,
        }));
        const { data, error } = await client.rpc("create_internal_e2e_run_v1", {
          p_idempotency_key: input.idempotency_key,
          p_request_fingerprint: requestFingerprint,
          p_run_label: input.run_label,
          p_ttl_minutes: input.ttl_minutes,
          p_approval_token_hash: await hashApprovalToken(approvalToken),
          p_intake_access_token_hash: intakeTokenHash,
          p_admin_access_token_hash: await hashAdminIntakeToken(adminToken),
        });
        if (error) throw new Error(error.message);
        return { ...data, intake_token: intakeToken, admin_intake_token: adminToken };
      }
      if (input.action === "finalize_internal_e2e_run") {
        const { data, error } = await client.rpc("finalize_internal_e2e_run_v1", {
          p_run_id: input.run_id,
          p_terminal_status: input.terminal_status,
          p_expected_revision: input.expected_revision,
          p_idempotency_key: input.idempotency_key,
        });
        if (error) throw new Error(error.message);
        return data;
      }
      const request = input.action === "list_applications"
        ? client.rpc("list_operator_applications_v1", {
          p_limit: input.limit,
          p_offset: input.offset
        })
        : input.action === "get_project_dossier"
        ? client.rpc("get_commercial_project_view_v2", {
          p_project_id: input.project_id
        })
        : input.action === "get_application_detail"
        ? input.support_reference
          ? client.rpc("get_operator_application_by_support_reference_v1", {
            p_support_reference: input.support_reference
          })
          : client.rpc("get_operator_application_v1", {
            p_quote_request_id: input.quote_request_id,
            p_application_reference: input.application_reference
          })
        : client.rpc("promote_operator_application_v1", {
          p_idempotency_key: input.idempotency_key,
          p_quote_request_id: input.quote_request_id,
          p_application_reference: input.application_reference
        });
      const { data, error } = await request;
      if (error) throw new Error(error.message);
      return data;
    },
    executeCommand: async (jwt: string, input: ValidatedCommercialCommandInput)=>{
      const { data, error } = await clientFor(jwt).rpc("execute_commercial_command_v2", {
        p_project_id: input.project_id,
        p_command_type: input.command_type,
        p_expected_state: input.expected_state,
        p_expected_revision: input.expected_revision,
        p_idempotency_key: input.idempotency_key,
        p_payload: input.payload
      });
      if (error) throw new Error(error.message);
      return data;
    }
  });
}));