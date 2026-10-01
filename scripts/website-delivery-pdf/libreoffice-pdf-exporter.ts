// W2.4.1-PDF part A: LibreOffice exporter for convertWebsiteDeliveryDocxToPdf (dependencies.exportWithWord).
// The pinned local image (scripts/website-delivery-pdf/libreoffice/Dockerfile) converts one copied DOCX
// without network, with a read-only root and input, no capabilities and no environment besides HOME.
import { join } from "jsr:@std/path@1";

// Local image lws-opl-w-01-pdf-converter:a1 built from the pinned Dockerfile (LibreOffice 25.2.3.2, Carlito 20230309-2).
export const LWS_OPL_W_01_PDF_CONVERTER_IMAGE =
  "sha256:ec39c3eadebfd3f31656548725e8eb4a7c4cf91d3ab91f015289e4e25f848314";

type RunResult = Readonly<{ success: boolean; stdout: string; stderr: string }>;
type ExportDependencies = Readonly<{
  run?: (command: string, args: string[]) => Promise<RunResult>;
  image?: string;
}>;

async function runCommand(command: string, args: string[]): Promise<RunResult> {
  const result = await new Deno.Command(command, { args, stdin: "null", stdout: "piped", stderr: "piped" }).output();
  return {
    success: result.success,
    stdout: new TextDecoder().decode(result.stdout),
    stderr: new TextDecoder().decode(result.stderr),
  };
}

export async function exportWithLibreOffice(
  inputPath: string,
  outputPath: string,
  dependencies: ExportDependencies = {},
): Promise<number> {
  const work = await Deno.makeTempDir({ prefix: "lws-opl-w-01-lo-" });
  try {
    const inDir = join(work, "in");
    const outDir = join(work, "out");
    await Deno.mkdir(inDir);
    await Deno.mkdir(outDir);
    await Deno.copyFile(inputPath, join(inDir, "input.docx"));
    const result = await (dependencies.run || runCommand)("docker", [
      "run", "--rm",
      "--network", "none",
      "--read-only",
      "--tmpfs", "/tmp:rw,size=256m,uid=10001,gid=10001",
      "--tmpfs", "/home/converter:rw,size=64m,uid=10001,gid=10001",
      "--cap-drop", "ALL",
      "--security-opt", "no-new-privileges",
      "--pids-limit", "256",
      "--memory", "1g",
      "--user", "10001:10001",
      "-e", "HOME=/home/converter",
      "-v", `${inDir}:/in:ro`,
      "-v", `${outDir}:/out:rw`,
      dependencies.image || LWS_OPL_W_01_PDF_CONVERTER_IMAGE,
      "sh", "-c",
      "soffice --headless --norestore --nolockcheck --convert-to pdf --outdir /out /in/input.docx >/dev/null "
        + "&& printf 'PAGE_COUNT=%s\\n' \"$(pdfinfo /out/input.pdf | sed -n 's/^Pages: *//p')\"",
    ]);
    if (!result.success) throw new Error("WEBSITE_DELIVERY_PDF_EXPORT_FAILED");
    const pageCount = Number(/^PAGE_COUNT=(\d+)$/m.exec(result.stdout)?.[1]);
    const produced = join(outDir, "input.pdf");
    if (!Number.isInteger(pageCount) || !(await Deno.stat(produced).then((info) => info.isFile, () => false))) {
      throw new Error("WEBSITE_DELIVERY_PDF_EXPORT_RESULT_INVALID");
    }
    await Deno.copyFile(produced, outputPath);
    return pageCount;
  } finally {
    await Deno.remove(work, { recursive: true });
  }
}
