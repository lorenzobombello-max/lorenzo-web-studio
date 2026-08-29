import { assertEquals } from "jsr:@std/assert@1";
import { isActiveOwnerIdentity, isStorageDuplicateError } from "./index.ts";

Deno.test("only ACTIVE owner identity is authorized", () => {
  assertEquals(
    isActiveOwnerIdentity({ role: "owner", status: "ACTIVE" }),
    true,
  );
  assertEquals(
    isActiveOwnerIdentity({ role: "admin", status: "ACTIVE" }),
    false,
  );
  assertEquals(
    isActiveOwnerIdentity({ role: "owner", status: "DISABLED" }),
    false,
  );
  assertEquals(
    isActiveOwnerIdentity({ role: "owner", status: "REVOKED" }),
    false,
  );
  assertEquals(isActiveOwnerIdentity(null), false);
});

Deno.test("Storage conflicts normalize to duplicate without broad error suppression", () => {
  assertEquals(
    isStorageDuplicateError({ statusCode: 409, message: "Conflict" }),
    true,
  );
  assertEquals(isStorageDuplicateError({ status: "409" }), true);
  assertEquals(
    isStorageDuplicateError({ message: "The resource already exists" }),
    true,
  );
  assertEquals(
    isStorageDuplicateError({
      statusCode: 500,
      message: "Storage unavailable",
    }),
    false,
  );
  assertEquals(isStorageDuplicateError(null), false);
});
