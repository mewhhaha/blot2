import { join } from "node:path";

export function installBlotLanguage(
  existing: string,
  options: { readonly repository: string; readonly definition: string },
): string {
  const openingMarkers = [
    ...existing.matchAll(/^# >>> blot \(managed by (.+)\) >>>\r?$/gm),
  ];
  if (openingMarkers.length > 1) {
    throw new Error("languages.toml contains multiple managed Blot blocks.");
  }

  const opening = openingMarkers[0];
  let start = existing.length;
  let end = existing.length;
  if (opening !== undefined) {
    start = opening.index;
    const closing = `# <<< blot (managed by ${opening[1]}) <<<`;
    const closingStart = existing.indexOf(closing, start + opening[0].length);
    if (closingStart < 0) {
      throw new Error(
        "languages.toml has a managed Blot block with no closing marker.",
      );
    }
    end = closingStart + closing.length;
  }

  const outside = existing.slice(0, start) + existing.slice(end);
  if (/^\s*name\s*=\s*["']blot["']\s*(?:#.*)?$/m.test(outside)) {
    throw new Error(
      "languages.toml has an unmanaged Blot entry; move it into the managed block before installing.",
    );
  }
  if (/^# <<< blot \(managed by .+\) <<<\r?$/m.test(outside)) {
    throw new Error(
      "languages.toml has a Blot closing marker without its opening marker.",
    );
  }

  const newline = existing.includes("\r\n") ? "\r\n" : "\n";
  const block = [
    `# >>> blot (managed by ${options.repository}) >>>`,
    options.definition.trimEnd(),
    "",
    "[[grammar]]",
    'name = "blot"',
    `source = { path = ${
      JSON.stringify(join(options.repository, "editor", "tree-sitter-blot2"))
    } }`,
    `# <<< blot (managed by ${options.repository}) <<<`,
  ].join("\n").replace(/\r?\n/g, newline);

  if (opening !== undefined) {
    return existing.slice(0, start) + block + existing.slice(end);
  }
  const separator = existing.length === 0
    ? ""
    : existing.endsWith("\n")
    ? newline
    : newline + newline;
  return existing + separator + block + newline;
}
