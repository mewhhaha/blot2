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

Deno.test("callable subtraction reports source operands and recovers after correction", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const invalid = `entry const good = fn (value: F32) -> F32 => value - 1.0
entry const broken = fn (value: F32) -> F32 => do:
  let transform: F32 -> F32 = fn (x: F32) => x + 1.0
  return transform - value
`;
  const corrected = invalid.replace(
    "transform - value",
    "transform value - value",
  );
  try {
    for (const codegenTier of ["development", "optimized"] as const) {
      const compiler = await createZigProjectCompiler({
        executable,
        entry,
        prelude,
        codegenTier,
      });
      try {
        const bad = await compiler.build({ sources: { [entry]: invalid } });
        ok(!bad.success);
        equal(bad.diagnostics[0].code, "missing_associated");
        equal(bad.diagnostics[0].filename, entry);
        const start = invalid.indexOf("transform - value");
        equal([bad.diagnostics[0].start, bad.diagnostics[0].end], [
          start,
          start + "transform - value".length,
        ]);
        equal(bad.diagnostics[0].explanation, {
          operation: "-",
          member: "sub",
          candidates: [
            { side: "left", operand: "(F32 -> F32)", outcome: "no_member" },
            { side: "right", operand: "F32", outcome: "incompatible" },
          ],
          truncated: false,
        });
        ok(bad.diagnostics[0].related?.filename.endsWith("prelude.blot"));
        const fixed = await compiler.build({ sources: { [entry]: corrected } });
        ok(fixed.success, JSON.stringify(fixed));
        const guest = await instantiateGuest(fixed.bytes);
        try {
          equal(guest.call("good", 2.5), 1.5);
          equal(guest.call("broken", 2.5), 1);
        } finally {
          guest.dispose();
        }
        const again = await compiler.build({ sources: { [entry]: invalid } });
        ok(!again.success);
        equal(again.diagnostics[0].code, "missing_associated");
        const recovered = await compiler.build({
          sources: { [entry]: corrected },
        });
        ok(recovered.success, JSON.stringify(recovered));
        equal(recovered.bytes, fixed.bytes);
      } finally {
        await compiler.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("imported generic subtraction points to the mismatched call", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const helper = `${directory}/helper.blot`;
  const generic = "const difference = fn left => fn right => left - right\n";
  const invalid = `import { difference } from "./helper"
entry const broken = fn (value: F32) -> F32 => do:
  let transform: F32 -> F32 = fn (x: F32) => x + 1.0
  return difference transform value
`;
  const corrected = invalid.replace(
    "difference transform value",
    "difference (transform value) value",
  );
  try {
    for (const codegenTier of ["development", "optimized"] as const) {
      const compiler = await createZigProjectCompiler({
        executable,
        entry,
        prelude,
        codegenTier,
      });
      try {
        const bad = await compiler.build({
          sources: { [entry]: invalid, [helper]: generic },
        });
        ok(!bad.success);
        equal(bad.diagnostics[0].code, "missing_associated");
        equal(bad.diagnostics[0].filename, entry);
        const start = invalid.indexOf("difference transform value");
        equal([bad.diagnostics[0].start, bad.diagnostics[0].end], [
          start,
          start + "difference transform value".length,
        ]);
        equal(
          bad.diagnostics[0].explanation?.candidates.map((candidate) =>
            candidate.operand
          ),
          ["(F32 -> F32)", "F32"],
        );
        const fixed = await compiler.build({
          sources: { [entry]: corrected, [helper]: generic },
        });
        ok(fixed.success, JSON.stringify(fixed));
        const guest = await instantiateGuest(fixed.bytes);
        try {
          equal(guest.call("broken", 2.5), 1);
        } finally {
          guest.dispose();
        }
      } finally {
        await compiler.dispose();
      }
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
