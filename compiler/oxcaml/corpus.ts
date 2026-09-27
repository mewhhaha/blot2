/** Differential corpus derived from complete, unescaped source literals in the
 * existing tests. This supplements, rather than replaces, those tests: dynamic
 * templates and fixtures requiring surrounding setup are not reconstructed. */
import { deepStrictEqual as equal } from "node:assert/strict";
import { createNativeCompiler } from "../native.ts";
import { createSourceCompiler } from "../source.ts";
import { SourceError } from "../syntax.ts";

const executable = Deno.args[0] ?? new URL("./_build/blotc", import.meta.url);
const threads = Number(Deno.args[1] ?? "4");
const fixtures = new Map<string, { source: string; file: string; line: number }>();
const root = new URL("../", import.meta.url);
const names = [];
for await (const file of Deno.readDir(root)) {
  if (file.isFile && file.name.endsWith(".test.ts")) names.push(file.name);
}
for (const file of names.sort()) {
  const text = await Deno.readTextFile(new URL(file, root));
  for (const match of text.matchAll(/`([^`]*?)`/gs)) {
    const source = match[1];
    if (source.includes("${") || source.includes("\\")) continue;
    if (!/^\s*(?:entry\s+)?(?:const|data|effect|use|import)\s+/m.test(source)) continue;
    if (!fixtures.has(source)) fixtures.set(source, {
      source, file: `compiler/${file}`,
      line: text.slice(0, match.index).split("\n").length,
    });
  }
}
let compiled = 0, diagnostics = 0;
const results = [];
function diagnostic(error: unknown) {
  if (!(error instanceof SourceError)) throw error;
  return { code: error.code, message: error.message, start: error.start,
    end: error.end, origin: error.origin };
}
for (const prelude of ["none", "default"] as const) {
  const reference = await createSourceCompiler({ prelude });
  const native = await createNativeCompiler({ executable, prelude, threads });
  try {
    for (const fixture of fixtures.values()) {
      const label = `${fixture.file}:${fixture.line}/${prelude}`;
      let expected, expectedError;
      try { expected = reference.compile(fixture.source); }
      catch (error) { expectedError = diagnostic(error); }
      if (expectedError) {
        let actualError;
        try { await native.compile(fixture.source); }
        catch (error) { actualError = diagnostic(error); }
        equal(actualError, expectedError, label);
        diagnostics++;
      } else {
        equal(await native.compile(fixture.source), expected, label);
        compiled++;
      }
      results.push({ file: fixture.file, line: fixture.line, prelude,
        outcome: expectedError ? "matching-diagnostic" : "matching-artifact" });
    }
  } finally { reference.dispose(); await native.dispose(); }
  console.log(`${prelude}: ${compiled} artifact comparisons, ${diagnostics} diagnostic comparisons passed so far`);
}
const report = { fixtures: fixtures.size, threads, compiled, diagnostics, results };
if (Deno.args[2]) await Deno.writeTextFile(Deno.args[2], JSON.stringify(report, null, 2) + "\n");
console.log(`${fixtures.size} unique source literals: ${compiled} matching artifacts, ${diagnostics} matching diagnostics`);
