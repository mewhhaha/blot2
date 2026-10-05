import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";
import { loopCases } from "./loop_cases.ts";

// These source cases and outputs are also run against the unchanged compiler
// in build/zig-native-core-eval/loop_oracle.ts. No hand-constructed IR bypasses
// the native parser, checker, retained bodies, evaluator or Wasm emitter.
for (const item of loopCases) {
  if (!("expected" in item)) continue;
  Deno.test(`native loops preserve ${item.name}`, async () => {
    await compileAndRun(item.source, (guest) => {
      for (const [name, expected] of Object.entries(item.expected)) {
        const argument = "arguments" in item
          ? (item.arguments as Record<string, number>)[name]
          : undefined;
        equal(
          guest.abi.constants.some((value) => value.name === name)
            ? guest.read(name)
            : guest.call(name, argument ?? null),
          expected,
        );
      }
    });
  });
}

Deno.test("native loops reject invalid bounds, refutable iterators and escaped control scopes", async () => {
  for (const item of loopCases) {
    if (!("error" in item)) continue;
    const nativeCode = item.error;
    await compileExpectedFailure(item.source, nativeCode);
  }
});

Deno.test("native range iteration uses constant stack on large runtime bounds", async () => {
  await compileAndRun(
    `
entry const run = fn (limit: U32) -> U32 => do:
  let total = 0
  for index in 0..limit:
    total := @u32.add self index
  return total
`,
    (guest) => {
      equal(guest.call("run", 0), 0);
      equal(guest.call("run", 100000), 704982704);
      equal(guest.call("run", 100001), 705082704);
    },
  );
});
