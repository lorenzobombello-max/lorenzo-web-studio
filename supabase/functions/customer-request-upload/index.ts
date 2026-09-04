import { createClient } from "npm:@supabase/supabase-js@2";
import {
  handleCustomerRequestUpload,
  type CustomerRequestUploadRpcClient,
} from "../_shared/customer-request-upload-handler.ts";
import {
  getSupabaseServerSecretKey,
  type SupabaseKeyBindingEnvironment,
} from "../_shared/supabase-key-bindings.ts";

type RuntimeClient = CustomerRequestUploadRpcClient & Readonly<{
  storage: Readonly<{
    from(bucket: string): Readonly<{
      createSignedUploadUrl(path: string, options: { upsert: false }): PromiseLike<{ data: { signedUrl?: string } | null; error: unknown }>;
      download(path: string): PromiseLike<{ data: Blob | null; error: unknown }>;
      remove(paths: string[]): PromiseLike<{ error: unknown }>;
    }>;
  }>;
}>;

type RuntimeClientFactory = (
  url: string,
  key: string,
  options: { auth: { persistSession: false; autoRefreshToken: false } },
) => RuntimeClient;

function unavailable(): Response {
  return new Response(JSON.stringify({ ok: false, state: "UPLOAD_NOT_AVAILABLE" }), { status: 500, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" } });
}

export function createCustomerRequestUploadRuntime(
  environment: SupabaseKeyBindingEnvironment = Deno.env,
  clientFactory: RuntimeClientFactory = (url, key, options) => createClient(url, key, options),
): (request: Request) => Promise<Response> {
  const url = environment.get("SUPABASE_URL");
  let key: string;
  try {
    key = getSupabaseServerSecretKey("default", environment);
  } catch {
    return async () => unavailable();
  }
  if (!url) return async () => unavailable();

  const client = clientFactory(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  return (request) => handleCustomerRequestUpload(request, client, {
    createSignedUploadUrl: (bucket, path) => client.storage.from(bucket).createSignedUploadUrl(path, { upsert: false }),
    download: (bucket, path) => client.storage.from(bucket).download(path),
    remove: (bucket, paths) => client.storage.from(bucket).remove(paths),
  });
}

if (import.meta.main) Deno.serve(createCustomerRequestUploadRuntime());