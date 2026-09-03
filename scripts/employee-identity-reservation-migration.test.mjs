import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const migrationPath = new URL(
  "../supabase/migrations/20260903130000_add_employee_identity_reservation_v1.sql",
  import.meta.url
);
const migration = await readFile(migrationPath, "utf8");

test("C3A reserves the exact first three pre-employment identities", ()=>{
  for(const [number, name] of [
    ["LWS-00001", "Lorenzo Bombello"],
    ["LWS-00002", "Herlinde Verlodt"],
    ["LWS-00003", "Daisy Defraine"]
  ]){
    assert.match(migration, new RegExp(`'${number}'::text, '${name}'::text`));
  }
  assert.match(migration, /default 'PRE_EMPLOYMENT'/);
});

test("C3A uses a concurrency-safe non-recycling allocator starting at four", ()=>{
  assert.match(migration, /create sequence public\.employee_identity_number_seq/);
  assert.match(migration, /minvalue 4\s+start with 4\s+no cycle;/);
  assert.match(migration, /nextval\('public\.employee_identity_number_seq'::regclass\)/);
  assert.doesNotMatch(migration, /max\s*\(/i);
});

test("C3A keeps allocation and activation evidence append-only", ()=>{
  assert.match(migration, /EMPLOYEE_NUMBER_ALLOCATION_IMMUTABLE/);
  assert.match(migration, /EMPLOYEE_IDENTITY_ACTIVATION_EVENT_IMMUTABLE/);
  assert.match(migration, /before update or delete on public\.employee_number_allocation_ledger/);
  assert.match(migration, /before update or delete on public\.employee_identity_activation_events/);
  assert.doesNotMatch(migration, /employee UUID pending|ledger row from pending/i);
});

test("C3A activation is a one-time UUID binding with no operator guess", ()=>{
  assert.match(migration, /EMPLOYEE_IDENTITY_ALREADY_ACTIVATED/);
  assert.match(migration, /EMPLOYEE_IDENTITY_BINDING_IMMUTABLE/);
  assert.match(migration, /commercial_operator_id\s*\n\s*\) values \(/);
  assert.match(migration, /p_end_date,\s*\n\s*null\s*\n\s*\)/);
  assert.doesNotMatch(migration, /auth_user_id|operator_profile|OP-0[1-9]|OP-1[0-5]/);
});

test("C3A preserves the Workforce start-date and Calendar UUID contracts", ()=>{
  assert.doesNotMatch(migration, /alter\s+(?:table\s+)?public\.workforce_employees[\s\S]*drop\s+not\s+null/i);
  assert.doesNotMatch(migration, /create\s+or\s+replace\s+function\s+public\.(?:get_operator_calendar_v1|list_workforce_calendar_v1|list_operator_workforce_v1)/i);
  assert.match(migration, /references public\.workforce_employees\(id\) on delete restrict/);
});

test("C3A exposes no unaudited runtime write route", ()=>{
  assert.match(migration, /revoke all on function public\.reserve_employee_identity_v1\(text, text\) from public, anon, authenticated, service_role/);
  assert.match(migration, /revoke all on function public\.activate_workforce_employee_identity_v1\(uuid, date, text, text, text, date\) from public, anon, authenticated, service_role/);
  assert.doesNotMatch(migration, /grant\s+execute/i);
});

test("C3A contains only approved low-sensitivity identity data", ()=>{
  assert.doesNotMatch(
    migration,
    /rijksregister|kaartnummer|\bMRZ\b|geboortedatum|birth_date|phone|telefoon|address|adres|bank|IBAN|salary|loon/i
  );
});