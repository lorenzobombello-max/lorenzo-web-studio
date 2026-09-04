export const SUPABASE_KEY_BINDING_ERROR = "SUPABASE_KEY_BINDING_INVALID";

export type SupabaseServerSecretKey = string & {
  readonly __supabaseServerSecretKey: unique symbol;
};

export type SupabasePublishableKey = string & {
  readonly __supabasePublishableKey: unique symbol;
};

export type SupabaseKeyBindingEnvironment = Readonly<{
  get(name: string): string | undefined;
}>;

export class SupabaseKeyBindingError extends Error {
  readonly code = SUPABASE_KEY_BINDING_ERROR;

  constructor() {
    super(SUPABASE_KEY_BINDING_ERROR);
    this.name = "SupabaseKeyBindingError";
  }
}

function readKey(
  environmentName: "SUPABASE_SECRET_KEYS" | "SUPABASE_PUBLISHABLE_KEYS",
  entry: string,
  expectedPrefix: "sb_secret_" | "sb_publishable_",
  environment: SupabaseKeyBindingEnvironment,
): string {
  const encoded = environment.get(environmentName);
  if (!encoded) throw new SupabaseKeyBindingError();

  let parsed: unknown;
  try {
    parsed = JSON.parse(encoded);
  } catch {
    throw new SupabaseKeyBindingError();
  }

  if (
    !entry ||
    typeof parsed !== "object" ||
    parsed === null ||
    Array.isArray(parsed) ||
    Object.getPrototypeOf(parsed) !== Object.prototype
  ) {
    throw new SupabaseKeyBindingError();
  }

  const entries = parsed as Record<string, unknown>;
  if (
    !Object.hasOwn(entries, entry) ||
    Object.values(entries).some((value) => typeof value !== "string" || !value)
  ) {
    throw new SupabaseKeyBindingError();
  }

  const key = entries[entry] as string;
  const suffix = key.slice(expectedPrefix.length);
  if (
    !key.startsWith(expectedPrefix) || !suffix ||
    !/^[A-Za-z0-9_-]+$/.test(suffix)
  ) {
    throw new SupabaseKeyBindingError();
  }
  return key;
}

export function getSupabaseServerSecretKey(
  entry = "default",
  environment: SupabaseKeyBindingEnvironment = Deno.env,
): SupabaseServerSecretKey {
  return readKey(
    "SUPABASE_SECRET_KEYS",
    entry,
    "sb_secret_",
    environment,
  ) as SupabaseServerSecretKey;
}

export function getSupabasePublishableKey(
  entry = "default",
  environment: SupabaseKeyBindingEnvironment = Deno.env,
): SupabasePublishableKey {
  return readKey(
    "SUPABASE_PUBLISHABLE_KEYS",
    entry,
    "sb_publishable_",
    environment,
  ) as SupabasePublishableKey;
}
