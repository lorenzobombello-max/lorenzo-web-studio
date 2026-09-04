import { assertEquals } from "jsr:@std/assert@1";
import {
  finalizationSucceeded,
  resolveRecruitmentApplicationSubmitConfiguration,
} from "./index.ts";

function environment(values: Record<string, string | undefined>) {
  return { get: (name: string) => values[name] };
}

Deno.test("service finalization accepts only the minimal submitted result", () => {
  assertEquals(
    finalizationSucceeded({
      id: "fa100000-0000-4000-8000-000000000001",
      status: "SUBMITTED",
    }, null),
    true,
  );
  assertEquals(
    finalizationSucceeded({
      id: "fa100000-0000-4000-8000-000000000001",
      status: "ACCEPTED",
    }, null),
    false,
  );
  assertEquals(finalizationSucceeded(null, { message: "failed" }), false);
  assertEquals(finalizationSucceeded([], null), false);
  assertEquals(finalizationSucceeded({ status: "SUBMITTED" }, null), false);
});

Deno.test("runtime adapter uses only the modern server binding and fails closed", async () => {
  const serverKey = ["sb", "secret", "recruitmentApplication", "test"].join(
    "_",
  );
  assertEquals(
    resolveRecruitmentApplicationSubmitConfiguration(environment({
      SUPABASE_URL: "https://project.supabase.co",
      SUPABASE_SECRET_KEYS: JSON.stringify({ default: serverKey }),
    })),
    { url: "https://project.supabase.co", serviceRoleKey: serverKey },
  );

  for (
    const serverBinding of [
      undefined,
      "not-json",
      JSON.stringify({ default: "legacy-service-role-key" }),
    ]
  ) {
    assertEquals(
      resolveRecruitmentApplicationSubmitConfiguration(environment({
        SUPABASE_URL: "https://project.supabase.co",
        SUPABASE_SERVICE_ROLE_KEY: "must-not-be-read",
        SUPABASE_SECRET_KEYS: serverBinding,
      })),
      null,
    );
  }
  assertEquals(
    resolveRecruitmentApplicationSubmitConfiguration(environment({
      SUPABASE_SECRET_KEYS: JSON.stringify({ default: serverKey }),
    })),
    null,
  );

  const source = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );
  assertEquals(source.includes('getSupabaseServerSecretKey("default"'), true);
  assertEquals(source.includes("SUPABASE_SERVICE_ROLE_KEY"), false);
  assertEquals(source.includes("SERVER_CONFIGURATION_ERROR"), true);
  assertEquals(source.includes("finalize_recruitment_application_v1"), true);
  assertEquals(
    source.includes("finalize_recruitment_open_application_v1"),
    true,
  );
  assertEquals(source.includes("RECRUITMENT_CV_BUCKET"), false);
  assertEquals(source.includes("storage.from(input.bucket).upload"), true);
  assertEquals(source.includes("storage.from(bucket).remove"), true);
  assertEquals(source.includes("upsert: input.upsert"), true);
  assertEquals(source.includes("auth.getUser"), false);
  assertEquals(source.includes("auth.admin"), false);
  assertEquals(source.includes("fetch("), false);
});
