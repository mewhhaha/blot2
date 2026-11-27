import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../../compiler-goose/build/squidc-goose", import.meta.url);
const repo = new URL("../../", import.meta.url).pathname;
const prelude = `${repo}std/prelude.sq`;
const stdRoot = `${repo}std`;

// Comment and spacing edits, real edits, errors and recovery in a retained
// project session match fresh builds, including diagnostic positions in the
// edited text.
Deno.test("retained trivia and real edits match fresh builds", async () => {
  for (const name of ["ecs", "syntax", "prelude"]) {
    const entry = `${repo}examples/${name}.sq`;
    const original = await Deno.readTextFile(entry);
    const firstLine = original.indexOf("\n");
    const lines = original.split("\n");
    const code = lines.findIndex((line) =>
      line.startsWith("const ") || line.startsWith("io const ") ||
      line.startsWith("func ") || line.startsWith("io ")
    );
    assert(code >= 0, name);
    const withComment = [
      ...lines.slice(0, code),
      `${lines[code]} // trailing note`,
      ...lines.slice(code + 1),
    ].join("\n");
    const longerComment = `// ${"x".repeat(40)}\n${
      original.slice(firstLine + 1)
    }`;
    const spaced = withComment.replace(" = ", " =   ");
    const added = `${original}\nconst trivia_probe_value: U32 = 1\n`;
    const broken = `${withComment}\nconst broken_trivia_probe: U32 = $Wrong\n`;
    const revisions = [
      original,
      withComment,
      longerComment,
      spaced,
      added,
      broken,
      withComment,
      original,
    ];
    const options = { executable, entry, prelude, stdRoot };
    const retained = await createZigProjectCompiler(options);
    try {
      for (const text of revisions) {
        const sources = { [entry]: text };
        const result = await retained.build({ sources });
        const fresh = await createZigProjectCompiler(options);
        try {
          const expected = await fresh.build({ sources });
          assert.equal(result.success, expected.success, name);
          if (!result.success && !expected.success) {
            assert.deepEqual(result.diagnostics, expected.diagnostics, name);
            continue;
          }
          assert(result.success && expected.success, name);
          assert.deepEqual(result.bytes, expected.bytes, name);
        } finally {
          await fresh.dispose();
        }
      }
    } finally {
      await retained.dispose();
    }
  }
});
