import { SupabaseClient } from "npm:@supabase/supabase-js@2";

export interface RateLimitResult {
  limited: boolean;
  error: boolean;
  errorCode?: string;
  errorMessage?: string;
}

export async function isRateLimited(
  supabase: SupabaseClient,
  clientIpHash: string,
): Promise<RateLimitResult> {
  const windowSeconds = Number(Deno.env.get("RATE_LIMIT_WINDOW_SECONDS") || "900");
  const maxRequests = Number(Deno.env.get("RATE_LIMIT_MAX_REQUESTS") || "3");

  const since = new Date(Date.now() - windowSeconds * 1000).toISOString();

  try {
    const { count, error } = await supabase
      .from("quote_requests")
      .select("id", { count: "exact", head: true })
      .eq("client_ip_hash", clientIpHash)
      .gte("created_at", since);

    if (error) {
      const postgrestLike = error as {
        name?: string;
        message?: string;
        code?: string;
        details?: string;
        hint?: string;
        status?: number;
        statusText?: string;
      };

      console.error("rate_limit_query_error", {
        category: "rate_limit",
        step: "quote_requests_count",
        error: {
          name: postgrestLike.name ?? "PostgrestError",
          message: postgrestLike.message ?? "Rate limit query failed",
          code: postgrestLike.code ?? null,
          details: postgrestLike.details ?? null,
          hint: postgrestLike.hint ?? null,
          status: postgrestLike.status ?? null,
          statusText: postgrestLike.statusText ?? null,
        },
      });

      return {
        limited: false,
        error: true,
        errorCode: error.code ?? "UNKNOWN_DB_ERROR",
        errorMessage: error.message ?? "Rate limit query failed",
      };
    }

    return {
      limited: (count ?? 0) >= maxRequests,
      error: false,
    };
  } catch (error) {
    const err = error as Error;
    const maybeHttpError = error as {
      code?: string;
      details?: string;
      hint?: string;
      status?: number;
      statusText?: string;
    };

    console.error("rate_limit_runtime_error", {
      category: "rate_limit",
      step: "quote_requests_count",
      error: {
        name: err.name || "Error",
        message: err.message || "Unexpected rate limit error",
        code: maybeHttpError.code ?? null,
        details: maybeHttpError.details ?? null,
        hint: maybeHttpError.hint ?? null,
        status: maybeHttpError.status ?? null,
        statusText: maybeHttpError.statusText ?? null,
      },
    });

    return {
      limited: false,
      error: true,
      errorCode: "RATE_LIMIT_RUNTIME_ERROR",
      errorMessage: err.message || "Unexpected rate limit error",
    };
  }
}
