import { createClient } from "npm:@supabase/supabase-js@2";
import { handleRecruitmentApplicationSubmit } from "./handler.ts";

export function finalizationSucceeded(data: unknown, error: unknown): boolean {
  if (error || !data || typeof data !== "object" || Array.isArray(data)) {
    return false;
  }
  const value = data as Record<string, unknown>;
  return value.status === "SUBMITTED" && typeof value.id === "string";
}

if (import.meta.main) {
  Deno.serve((request) => {
    const url = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !serviceRoleKey) {
      return new Response(
        JSON.stringify({ ok: false, code: "SERVER_CONFIGURATION_ERROR" }),
        {
          status: 500,
          headers: {
            "Content-Type": "application/json",
            "Cache-Control": "no-store",
          },
        },
      );
    }
    const serviceClient = createClient(url, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    return handleRecruitmentApplicationSubmit(request, {
      createApplicationId: () => crypto.randomUUID(),
      putObject: async (input) => {
        const { error } = await serviceClient.storage.from(input.bucket).upload(
          input.objectPath,
          input.bytes,
          {
            contentType: input.mimeType,
            upsert: input.upsert,
            metadata: { sha256: input.sha256 },
          },
        );
        if (error) throw error;
      },
      finalizeApplication: async (input) => {
        const { data, error } = await serviceClient.rpc(
          "finalize_recruitment_application_v1",
          {
            p_application_id: input.applicationId,
            p_vacancy_id: input.vacancyId,
            p_first_name: input.firstName,
            p_last_name: input.lastName,
            p_email: input.email,
            p_phone: input.phone,
            p_motivation: input.motivation,
            p_cv_storage_path: input.cvStoragePath,
            p_cv_mime_type: input.cvMimeType,
            p_cv_byte_count: input.cvByteCount,
            p_cv_sha256: input.cvSha256,
          },
        );
        if (!finalizationSucceeded(data, error)) {
          throw error || new Error("APPLICATION_FINALIZATION_FAILED");
        }
      },
      removeObject: async (bucket, objectPath) => {
        const { error } = await serviceClient.storage.from(bucket).remove([
          objectPath,
        ]);
        if (error) throw error;
      },
    });
  });
}
