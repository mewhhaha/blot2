import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const repo = new URL("../../", import.meta.url).pathname;
const prelude = `${repo}std/prelude.blot`;
const stdRoot = `${repo}std`;

// Comment and spacing edits that keep tokens and adjacency publish the last
// output without rebuilding. Real edits, errors and recovery afterwards match
// fresh builds, including diagnostic positions in the edited text.
Deno.test("trivia-only edits reuse output and later edits match fresh builds", async () => {
  for (const name of ["ecs", "syntax", "monads"]) {
    const entry = `${repo}examples/${name}.blot`;
    const original = await Deno.readTextFile(entry);
    const firstLine = original.indexOf("\n");
    const lines = original.split("\n");
    const code = lines.findIndex((line) =>
      line.startsWith("const ") || line.startsWith("entry const ")
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
    // [text, expected trivia reuse relative to the last compiled revision]
    const revisions: [string, boolean][] = [
      [original, false],
      [withComment, true],
      [longerComment, true],
      [spaced, true],
      [added, false],
      [broken, false],
      [withComment, false],
      [original, true],
    ];
    const options = { executable, entry, prelude, stdRoot };
    const retained = await createZigProjectCompiler(options);
    try {
      for (const [index, [text, trivia]] of revisions.entries()) {
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
          const attempt = result.stats.attemptStats as Record<string, unknown>;
          assert.equal(
            attempt.trivia_only,
            trivia,
            `${name} revision ${index}: ${JSON.stringify(attempt).slice(0, 120)}`,
          );
          if (trivia) assert.equal(attempt.reused_output, true);
        } finally {
          await fresh.dispose();
        }
      }
    } finally {
      await retained.dispose();
    }
  }
});
