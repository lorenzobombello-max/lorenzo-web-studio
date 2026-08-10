export function buildAuthoritativeSubmitData(
  storedData: Record<string, unknown>,
  submittedData: Record<string, unknown>,
): Record<string, unknown> {
  return { ...storedData, ...submittedData };
}
