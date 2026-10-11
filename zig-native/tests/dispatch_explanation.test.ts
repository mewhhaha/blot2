import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
import { readDispatchExplanation } from "../../compiler/type_diagnostics.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const prelude = new URL("../../std/prelude.blot", import.meta.url).pathname;

async function cli(args: string[]): Promise<Record<string, unknown>[]> {
  const output = await new Deno.Command(executable, {
    args,
    stdout: "piped",
    stderr: "piped",
  }).output();
  return new TextDecoder().decode(output.stdout).trim().split("\n").map((
    line,
  ) => JSON.parse(line));
}
function explained(records: Record<string, unknown>[]) {
  const diagnostic = records.find((record) => record.kind === "diagnostic");
  ok(diagnostic, JSON.stringify(records));
  const details = diagnostic.details as Record<string, unknown>;
  return {
    code: diagnostic.code,
    explanation: readDispatchExplanation(details.explanation),
  };
}

Deno.test("operator failures explain prelude dispatch through the CLI", async () => {
  const directory = await Deno.makeTempDir();
  try {
    const cases: [string, unknown][] = [
      ["entry const answer = fn () => 1 + 2.5\n", [
        { side: "left", operand: "U32", outcome: "incompatible" },
        { side: "right", operand: "F32", outcome: "incompatible" },
      ]],
      ["entry const answer = fn () => #True + #False\n", [
        { side: "left", operand: "Bool", outcome: "no_member" },
      ]],
    ];
    for (const [source, candidates] of cases) {
      const input = `${directory}/main.blot`;
      await Deno.writeTextFile(input, source);
      const result = explained(
        await cli([
          "build",
          input,
          `${directory}/main.wasm`,
          "--prelude",
          prelude,
        ]),
      );
      equal(result.code, "missing_associated");
      equal(result.explanation, {
        operation: "+",
        member: "add",
        candidates,
        truncated: false,
      });
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

const library = "type Meters is data=#Meters F32\n" +
  "const meters = fn (value: F32) => #Meters value\n";
const method = "const Meters.add = fn left => fn right => do:\n" +
  "  let #Meters a = left\n  let #Meters b = right\n" +
  "  return #Meters (@f32.add a b)\n";
const main = (annotation: string) =>
  'import { meters } from "./library"\n' +
  "entry const answer = fn () => do:\n" +
  `  let total${annotation} = meters 1.0 + meters 2.0\n  return 7\n`;

Deno.test("project diagnostics carry dispatch explanations and recover after correction", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const compiler = await createZigProjectCompiler({
    executable,
    entry,
    prelude,
  });
  try {
    const libraryPath = `${directory}/library.blot`;
    const fixed = { [entry]: main(""), [libraryPath]: library + method };
    const first = await compiler.build({ sources: fixed });
    ok(first.success, JSON.stringify(first));
    const missing = await compiler.build({
      sources: { ...fixed, [libraryPath]: library },
    });
    ok(!missing.success);
    equal(missing.revision, first.revision);
    equal(missing.diagnostics[0].code, "missing_associated");
    const absent = missing.diagnostics[0].explanation;
    ok(absent, JSON.stringify(missing.diagnostics[0]));
    equal(absent.operation, "+");
    equal(absent.member, "add");
    equal(absent.candidates.length, 1);
    equal(absent.candidates[0].side, "left");
    equal(absent.candidates[0].outcome, "no_member");
    ok(absent.candidates[0].operand?.endsWith("Meters"));
    // Operands select the left method; a conflicting annotation does not
    // send dispatch to any other candidate.
    const conflict = await compiler.build({
      sources: { ...fixed, [entry]: main(": F32") },
    });
    ok(!conflict.success);
    equal(conflict.diagnostics[0].code, "type_mismatch");
    equal(conflict.diagnostics[0].explanation, {
      operation: "+",
      member: "add",
      candidates: [{
        side: "left",
        operand: "Meters",
        outcome: "result_mismatch",
      }],
      truncated: false,
    });
    const recovered = await compiler.build({ sources: fixed });
    ok(recovered.success, JSON.stringify(recovered));
    equal(recovered.bytes, first.bytes);
    const guest = await instantiateGuest(recovered.bytes);
    try {
      equal(guest.call("answer", null), 7);
    } finally {
      guest.dispose();
    }
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("dispatch over a compiled dependency's type is explained", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const bundle = `${directory}/dependencies.blotdep`;
  try {
    await Deno.writeTextFile(`${directory}/library.blot`, library);
    await Deno.writeTextFile(
      entry,
      'import { meters } from "./library"\nentry const answer = fn () => 7\n',
    );
    const packed = await new Deno.Command(executable, {
      args: ["dependencies", entry, bundle, "--prelude", prelude],
      stdout: "piped",
      stderr: "piped",
    }).output();
    ok(packed.success, new TextDecoder().decode(packed.stdout));
    await Deno.writeTextFile(entry, main(""));
    const compiler = await createZigProjectCompiler({
      executable,
      entry,
      prelude,
      dependencies: bundle,
    });
    try {
      const built = await compiler.build();
      ok(!built.success);
      equal(built.diagnostics[0].code, "missing_associated");
      equal(built.diagnostics[0].filename, entry);
      ok(built.diagnostics[0].related?.filename.endsWith("prelude.blot"));
      const explanation = built.diagnostics[0].explanation;
      ok(explanation, JSON.stringify(built.diagnostics[0]));
      equal(explanation.candidates.map((item) => item.outcome), [
        "no_member",
      ]);
      ok(explanation.candidates[0].operand?.endsWith("Meters"));
    } finally {
      await compiler.dispose();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
