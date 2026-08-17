import type { RequestKind } from "./types.ts";

export const REQUEST_KINDS = new Set<RequestKind>(["website", "slimme_documentenflow"]);

export function isRequestKind(value: string): value is RequestKind {
  return REQUEST_KINDS.has(value as RequestKind);
}

export function requestKindLabel(value: RequestKind): string {
  return value === "slimme_documentenflow" ? "Slimme Documentenflow" : "Website";
}

export function allowsWebsiteLifecycle(value: RequestKind): boolean {
  return value === "website";
}