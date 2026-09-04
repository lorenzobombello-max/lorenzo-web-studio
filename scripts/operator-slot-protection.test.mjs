import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const read = (path)=>readFile(new URL(path, root), "utf8");

test("occupied operator slots are immutable and future slots start at OP-04", async ()=>{
  const migration = await read("supabase/migrations/20260904140000_protect_reserved_operator_slots_v1.sql");
  assert.match(migration, /v_profile_code in \('OP-01', 'OP-02', 'OP-03'\)/);
  assert.match(migration, /RESERVED_OPERATOR_PROFILE_IMMUTABLE/);
  assert.match(migration, /substring\(v_profile_code from 4\)::integer < 4/);
  assert.match(migration, /tg_op in \('UPDATE', 'DELETE'\)[\s\S]*OPERATOR_PROFILE_SLOT_IMMUTABLE/);
});

test("reserved operator identities cannot be assigned to workforce employees", async ()=>{
  const migration = await read("supabase/migrations/20260904140000_protect_reserved_operator_slots_v1.sql");
  assert.match(migration, /before insert or update of commercial_operator_id on public\.workforce_employees/);
  assert.match(migration, /RESERVED_OPERATOR_PROFILE_LINK_FORBIDDEN/);
  assert.match(migration, /profile\.profile_code in \('OP-01', 'OP-02', 'OP-03'\)/);
});

test("open applications never assign an operator profile", async ()=>{
  const [ownerModule, migration] = await Promise.all([
    read("assets/js/operator-recruitment-applications.mjs"),
    read("supabase/migrations/20260904130000_add_recruitment_open_applications_v1.sql"),
  ]);
  for (const source of [ownerModule, migration]) {
    assert.doesNotMatch(source, /commercial_operator_id|operator_profile_definitions|profile_code|OP-0[1-9]/);
  }
});