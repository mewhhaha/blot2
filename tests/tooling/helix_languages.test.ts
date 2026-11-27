import { equal, ok, throws } from "node:assert/strict";
import { installSquidLanguage } from "../../editor/helix/languages.ts";

const definition = await Deno.readTextFile(
  new URL("../../editor/helix/languages.toml", import.meta.url),
);
const options = { repository: "/projects/squid-lang", definition };
const legacy = `# >>> squid (managed by /projects/squid) >>>
[language-server.squid]
command = "legacy-lsp"

[[language]]
name = "squid"
language-servers = ["squid"]
auto-format = true

[[grammar]]
name = "squid"
source = { path = "/projects/squid/tree-sitter-squid" }
# <<< squid (managed by /projects/squid) <<<
`;

Deno.test("registers the public squid language and completion server with absolute paths", () => {
  const installed = installSquidLanguage("", options);
  ok(installed.includes('language-id = "squid"'));
  ok(installed.includes('file-types = ["sq"]'));
  ok(installed.includes('grammar = "squid"'));
  ok(installed.includes('language-servers = ["squid"]'));
  ok(installed.includes("[language-server.squid]"));
  ok(installed.includes('"/projects/squid-lang/host/lsp.ts"'));
  ok(
    installed.includes(
      '"/projects/squid-lang/compiler-goose/build/squidc-goose"',
    ),
  );
  ok(installed.includes("auto-format = false"));
  ok(
    installed.includes(
      'path = "/projects/squid-lang/editor/tree-sitter-squid"',
    ),
  );
});

Deno.test("replaces the legacy block and preserves neighboring settings exactly", () => {
  const before = '# custom settings\n[[language]]\nname = "rust"\n\n';
  const after = '\n[[language]]\nname = "bend2"\n';
  const installed = installSquidLanguage(before + legacy + after, options);
  equal(installed, before + installSquidLanguage("", options) + after);
  ok(!installed.includes("legacy-lsp"));
  ok(!installed.includes("auto-format = true"));
});

Deno.test("reinstalling does not duplicate or move the managed block", () => {
  const installed = installSquidLanguage(legacy, options);
  equal(installSquidLanguage(installed, options), installed);
});

Deno.test("preserves CRLF line endings on replacement", () => {
  const installed = installSquidLanguage(
    legacy.replaceAll("\n", "\r\n"),
    options,
  );
  ok(!/(?<!\r)\n/.test(installed));
  equal(installSquidLanguage(installed, options), installed);
});

Deno.test("refuses an incomplete block instead of overwriting unrelated settings", () => {
  throws(
    () =>
      installSquidLanguage(legacy.slice(0, legacy.indexOf("# <<<")), options),
    /no closing marker/,
  );
  throws(
    () =>
      installSquidLanguage(
        "# <<< squid (managed by /projects/squid) <<<\n",
        options,
      ),
    /without its opening marker/,
  );
});

Deno.test("refuses ambiguous or unmanaged Squid registrations", () => {
  throws(
    () => installSquidLanguage(legacy + legacy, options),
    /multiple managed/,
  );
  throws(
    () => installSquidLanguage('[[language]]\nname = "squid"\n', options),
    /unmanaged Squid entry/,
  );
  throws(
    () =>
      installSquidLanguage(
        '[language-server.squid]\ncommand="other"\n',
        options,
      ),
    /unmanaged Squid language server/,
  );
});
