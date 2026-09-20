import { equal, ok, throws } from "node:assert/strict";
import { installBlotLanguage } from "./helix_languages.ts";

const definition = await Deno.readTextFile(
  new URL("../editor/helix/languages.toml", import.meta.url),
);
const options = { repository: "/projects/blot2", definition };
const legacy = `# >>> blot (managed by /projects/blot) >>>
[language-server.blot]
command = "legacy-lsp"

[[language]]
name = "blot"
language-servers = ["blot"]
auto-format = true

[[grammar]]
name = "blot"
source = { path = "/projects/blot/tree-sitter-blot" }
# <<< blot (managed by /projects/blot) <<<
`;

Deno.test("registers the public blot language with no legacy language server", () => {
  const installed = installBlotLanguage("", options);
  ok(installed.includes('language-id = "blot"'));
  ok(installed.includes('file-types = ["blot"]'));
  ok(installed.includes('grammar = "blot"'));
  ok(installed.includes("language-servers = []"));
  ok(installed.includes("auto-format = false"));
  ok(installed.includes('path = "/projects/blot2/editor/tree-sitter-blot2"'));
});

Deno.test("replaces the legacy block and preserves neighboring settings exactly", () => {
  const before = '# custom settings\n[[language]]\nname = "rust"\n\n';
  const after = '\n[[language]]\nname = "bend2"\n';
  const installed = installBlotLanguage(before + legacy + after, options);
  equal(installed, before + installBlotLanguage("", options) + after);
  ok(!installed.includes("legacy-lsp"));
  ok(!installed.includes("auto-format = true"));
});

Deno.test("reinstalling does not duplicate or move the managed block", () => {
  const installed = installBlotLanguage(legacy, options);
  equal(installBlotLanguage(installed, options), installed);
});

Deno.test("preserves CRLF line endings on replacement", () => {
  const installed = installBlotLanguage(
    legacy.replaceAll("\n", "\r\n"),
    options,
  );
  ok(!/(?<!\r)\n/.test(installed));
  equal(installBlotLanguage(installed, options), installed);
});

Deno.test("refuses an incomplete block instead of overwriting unrelated settings", () => {
  throws(
    () =>
      installBlotLanguage(legacy.slice(0, legacy.indexOf("# <<<")), options),
    /no closing marker/,
  );
  throws(
    () =>
      installBlotLanguage(
        "# <<< blot (managed by /projects/blot) <<<\n",
        options,
      ),
    /without its opening marker/,
  );
});

Deno.test("refuses ambiguous or unmanaged Blot registrations", () => {
  throws(
    () => installBlotLanguage(legacy + legacy, options),
    /multiple managed/,
  );
  throws(
    () => installBlotLanguage('[[language]]\nname = "blot"\n', options),
    /unmanaged Blot entry/,
  );
});
