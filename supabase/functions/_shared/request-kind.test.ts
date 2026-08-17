import { assertEquals } from "jsr:@std/assert@1";
import { allowsWebsiteLifecycle, isRequestKind, requestKindLabel } from "./request-kind.ts";

Deno.test("request kind values and labels are closed", () => {
  assertEquals(isRequestKind("website"), true);
  assertEquals(isRequestKind("slimme_documentenflow"), true);
  assertEquals(isRequestKind("privacy"), false);
  assertEquals(isRequestKind("unknown"), false);
  assertEquals(requestKindLabel("website"), "Website");
  assertEquals(requestKindLabel("slimme_documentenflow"), "Slimme Documentenflow");
});

Deno.test("only website requests enter the website lifecycle", () => {
  assertEquals(allowsWebsiteLifecycle("website"), true);
  assertEquals(allowsWebsiteLifecycle("slimme_documentenflow"), false);
});