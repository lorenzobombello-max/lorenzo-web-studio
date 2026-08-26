import { createClient } from "npm:@supabase/supabase-js@2";
import { handleCustomerRequestUpload } from "../_shared/customer-request-upload-handler.ts";

Deno.serve((request) => {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) return new Response(JSON.stringify({ ok: false, state: "UPLOAD_NOT_AVAILABLE" }), { status: 500, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" } });
  const client = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  return handleCustomerRequestUpload(request, client, {
    createSignedUploadUrl: (bucket, path) => client.storage.from(bucket).createSignedUploadUrl(path, { upsert: false }),
    download: (bucket, path) => client.storage.from(bucket).download(path),
    remove: (bucket, paths) => client.storage.from(bucket).remove(paths),
  });
});