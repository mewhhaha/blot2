import { createHash } from "node:crypto";
import { isAbsolute, relative, resolve } from "node:path";

export function fileDigest(path: string): Promise<string> {
  return bufferedDigest(path, new Uint8Array(1024 * 1024));
}

async function bufferedDigest(
  path: string,
  buffer: Uint8Array,
): Promise<string> {
  const hash = createHash("sha256");
  const file = await Deno.open(path);
  try {
    let length: number | null;
    while ((length = await file.read(buffer)) !== null) {
      hash.update(buffer.subarray(0, length));
    }
  } finally {
    file.close();
  }
  return hash.digest("hex");
}

export async function inputDigest(paths: string[]): Promise<string> {
  const hash = createHash("sha256");
  // Reuse a bounded buffer across source files. Large executable digests use a
  // larger buffer above to avoid thousands of small stream reads and promises.
  const buffer = new Uint8Array(64 * 1024);
  for (const path of [...new Set(paths)].sort()) {
    hash.update(JSON.stringify(path));
    try {
      hash.update(await bufferedDigest(path, buffer));
    } catch (error) {
      if (!(error instanceof Deno.errors.NotFound)) throw error;
      hash.update("missing");
    }
  }
  return hash.digest("hex");
}

function xmlText(value: string): string {
  return value.replaceAll("&quot;", '"').replaceAll("&apos;", "'")
    .replaceAll("&lt;", "<").replaceAll("&gt;", ">")
    .replaceAll("&amp;", "&");
}

export function failedGuestFiles(xml: string, root: string): string[] {
  const files: string[] = [];
  for (const suite of xml.matchAll(/<testsuite\s+([^>]+)>/g)) {
    const attributes = Object.fromEntries(
      [...suite[1].matchAll(/(\w+)="([^"]*)"/g)].map((
        match,
      ) => [match[1], xmlText(match[2])]),
    );
    if (!(Number(attributes.failures) > 0 || Number(attributes.errors) > 0)) {
      continue;
    }
    const path = relative(root, resolve(root, attributes.name ?? ""));
    if (
      !path.endsWith(".test.ts") || path.startsWith("..") || isAbsolute(path)
    ) continue;
    files.push(path);
  }
  return [...new Set(files)].sort();
}

export async function recentFailures(path: string): Promise<string[]> {
  try {
    const files = JSON.parse(await Deno.readTextFile(path));
    if (!Array.isArray(files)) return [];
    return files.filter((file) =>
      typeof file === "string" && file.endsWith(".test.ts")
    );
  } catch (error) {
    if (error instanceof Deno.errors.NotFound || error instanceof SyntaxError) {
      return [];
    }
    throw error;
  }
}
