import { isAbsolute, join } from "node:path";

export function installSquidLanguage(
  existing: string,
  options: { readonly repository: string; readonly definition: string },
): string {
  if (!isAbsolute(options.repository)) {
    throw new Error("Helix requires an absolute repository path.");
  }
  const openingMarkers = [
    ...existing.matchAll(/^# >>> squid \(managed by (.+)\) >>>\r?$/gm),
  ];
  if (openingMarkers.length > 1) {
    throw new Error("languages.toml contains multiple managed Squid blocks.");
  }

  const opening = openingMarkers[0];
  let start = existing.length;
  let end = existing.length;
  if (opening !== undefined) {
    start = opening.index;
    const closing = `# <<< squid (managed by ${opening[1]}) <<<`;
    const closingStart = existing.indexOf(closing, start + opening[0].length);
    if (closingStart < 0) {
      throw new Error(
        "languages.toml has a managed Squid block with no closing marker.",
      );
    }
    end = closingStart + closing.length;
  }

  const outside = existing.slice(0, start) + existing.slice(end);
  if (/^\s*name\s*=\s*["']squid["']\s*(?:#.*)?$/m.test(outside)) {
    throw new Error(
      "languages.toml has an unmanaged Squid entry; move it into the managed block before installing.",
    );
  }
  if (/^\s*\[language-server\.squid\]\s*(?:#.*)?$/m.test(outside)) {
    throw new Error("languages.toml has an unmanaged Squid language server.");
  }
  if (/^# <<< squid \(managed by .+\) <<<\r?$/m.test(outside)) {
    throw new Error(
      "languages.toml has a Squid closing marker without its opening marker.",
    );
  }

  const newline = existing.includes("\r\n") ? "\r\n" : "\n";
  const block = [
    `# >>> squid (managed by ${options.repository}) >>>`,
    "[language-server.squid]",
    'command = "deno"',
    `args = ${
      JSON.stringify([
        "run",
        "--allow-read",
        "--allow-run",
        join(options.repository, "host", "lsp.ts"),
        "--compiler",
        join(options.repository, "compiler-goose", "build", "squidc-goose"),
        "--prelude",
        join(options.repository, "std", "prelude.sq"),
        "--std-root",
        join(options.repository, "std"),
      ])
    }`,
    "",
    options.definition.trimEnd(),
    "",
    "[[grammar]]",
    'name = "squid"',
    `source = { path = ${
      JSON.stringify(join(options.repository, "editor", "tree-sitter-squid"))
    } }`,
    `# <<< squid (managed by ${options.repository}) <<<`,
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
