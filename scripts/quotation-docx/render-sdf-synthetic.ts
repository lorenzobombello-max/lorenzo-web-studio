import { renderSdfQuotationDocxBytes } from "../../supabase/functions/commercial-operator-command/sdf-quotation-renderer-edge.ts";
import {
  createSdfSyntheticRendererPackage,
  SDF_SYNTHETIC_PACKAGE_AMOUNTS,
  type SdfSyntheticPackageKey,
} from "./sdf-synthetic-fixture.ts";

const templatePath = new URL(
  "../../assets/docs/quotation/LWS_SDF_QUOTATION_NL_BE_OFFICIAL_v1.docx",
  import.meta.url,
);
const outputDirectory = new URL("../../test-results/sdf-quotation-renderer/", import.meta.url);
await Deno.mkdir(outputDirectory, { recursive: true });
const templateBytes = await Deno.readFile(templatePath);

for (const packageKey of Object.keys(SDF_SYNTHETIC_PACKAGE_AMOUNTS) as SdfSyntheticPackageKey[]) {
  const result = await renderSdfQuotationDocxBytes({
    templateBytes,
    rendererPackage: createSdfSyntheticRendererPackage(packageKey),
  });
  const output = new URL(`TEST-SDF-2026-0001-${packageKey.toUpperCase()}.docx`, outputDirectory);
  await Deno.writeFile(output, result.buffer);
  console.log(`${packageKey.toUpperCase()} ${result.sha256} ${result.buffer.byteLength}`);
}