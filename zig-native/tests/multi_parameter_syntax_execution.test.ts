import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { observeGuestAllocations } from "../../scripts/bench/guest_heap_observer.ts";
import { compileAndRun, compileExpectedFailure } from "./compile_helpers.ts";

Deno.test("curried parameter lists retain partial application, generic callbacks, and named record calls", async () => {
  await compileAndRun(
    `
const combine = fn (first: U32) (second: U32) (third: U32) => @u32.add (@u32.add first second) third
const partial = combine 40
const apply = fn callback value => callback value
const dimensions = fn (fields: { width: U32, height: U32, x: U32, y: U32 }) =>
  @u32.add (@u32.mul fields.width fields.height) (@u32.add fields.x fields.y)
entry const positional = fn (input: U32) => partial input 1
entry const generic = fn (input: U32) => apply (fn number => @u32.add number 1) input
entry const named = fn (input: U32) => dimensions { y: 4, height: 3, x: input, width: 5 }
`,
    (guest) => {
      assert.equal(guest.call("positional", 1), 42);
      assert.equal(guest.call("generic", 41), 42);
      assert.equal(guest.call("named", 2), 21);
    },
  );
});

Deno.test("record fields and curried stages evaluate arguments once in written order", async () => {
  await compileAndRun(
    `
const combine = fn first second => @u32.add first second
const dimensions = fn (fields: { width: U32, height: U32 }) => @u32.mul fields.width fields.height
const staged = fn (tick: U32 -> U32 ! {Foreign}) => do:
  use base <- tick 3
  return fn (value: U32) => @u32.add base value
entry const positional = fn (tick: U32 -> U32 ! {Foreign}) => combine (tick 1) (tick 2)
entry const named = fn (tick: U32 -> U32 ! {Foreign}) => dimensions { height: tick 2, width: tick 1 }
entry const later = fn (tick: U32 -> U32 ! {Foreign}) => (staged tick) 4
`,
    (guest) => {
      const calls: number[] = [];
      const tick = guest.capability({
        parameter: "U32",
        result: "U32",
        call: (value: number) => {
          calls.push(value);
          return value;
        },
      });
      assert.equal(guest.call("positional", tick), 3);
      assert.deepEqual(calls.splice(0), [1, 2]);
      assert.equal(guest.call("named", tick), 2);
      assert.deepEqual(calls.splice(0), [2, 1]);
      assert.equal(guest.call("later", tick), 7);
      assert.deepEqual(calls.splice(0), [3]);
    },
  );
});

Deno.test("record-style named calls reject duplicate and unknown argument names at their source", async () => {
  const prefix =
    `const area = fn (fields: { width: U32, height: U32 }) => @u32.mul fields.width fields.height\nentry const answer = fn () => area `;
  const duplicate = `${prefix}{ width: 1, width: 2, height: 3 }\n`;
  await compileExpectedFailure(duplicate, "duplicate_record_field", undefined, {
    span: [duplicate.indexOf("width: 2"), duplicate.indexOf("width: 2")],
  });
  const unknown = `${prefix}{ width: 1, height: 2, depth: 3 }\n`;
  await compileExpectedFailure(unknown, "unknown_field", undefined, {
    span: [
      unknown.indexOf("depth: 3"),
      unknown.indexOf("depth: 3") + "depth: 3".length,
    ],
  });
});

Deno.test("parameter-list sugar and explicit currying have the same generated size and guest allocation traffic in both tiers", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-curried-parity-" });
  const entry = `${directory}/main.blot`;
  const executable = Deno.args[0] ??
    new URL("../zig-out/bin/blotc", import.meta.url);
  try {
    for (const codegenTier of ["development", "optimized"] as const) {
      const outputs: Array<
        {
          bytes: Uint8Array<ArrayBuffer>;
          allocations: ReturnType<typeof observeGuestAllocations>;
        }
      > = [];
      for (
        const declaration of [
          "fn (first: U32) (second: U32) => @u32.add first second",
          "fn (first: U32) => fn (second: U32) => @u32.add first second",
        ]
      ) {
        const source =
          `const sum = ${declaration}\nentry const answer = fn (input: U32) => sum input 1\n`;
        const compiler = await createZigProjectCompiler({
          executable,
          entry,
          prelude: null,
          cacheDirectory: false,
          codegenTier,
        });
        try {
          const result = await compiler.build({ sources: { [entry]: source } });
          assert(result.success, JSON.stringify(result));
          outputs.push({
            bytes: result.bytes,
            allocations: observeGuestAllocations(result.bytes, [[
              "answer",
              41,
              42,
            ]]),
          });
        } finally {
          await compiler.dispose();
        }
      }
      assert.equal(
        outputs[0].bytes.length,
        outputs[1].bytes.length,
        codegenTier,
      );
      assert.deepEqual(
        outputs[0].allocations,
        outputs[1].allocations,
        codegenTier,
      );
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("named record calls and positional calls expose allocation traffic in both tiers", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-named-call-" });
  const entry = `${directory}/main.blot`;
  const executable = Deno.args[0] ??
    new URL("../zig-out/bin/blotc", import.meta.url);
  const declarations = [
    `const calculate = fn (a: U32) (b: U32) (c: U32) (d: U32) => @u32.add (@u32.mul a b) (@u32.mul c d)
entry const answer = fn (input: U32) => calculate input 2 3 4
`,
    `const calculate = fn (args: { a: U32, b: U32, c: U32, d: U32 }) => @u32.add (@u32.mul args.a args.b) (@u32.mul args.c args.d)
entry const answer = fn (input: U32) => calculate { d: 4, c: 3, b: 2, a: input }
`,
  ];
  try {
    for (const codegenTier of ["development", "optimized"] as const) {
      const traffic = [];
      for (const source of declarations) {
        const compiler = await createZigProjectCompiler({
          executable,
          entry,
          prelude: null,
          cacheDirectory: false,
          codegenTier,
        });
        try {
          const result = await compiler.build({ sources: { [entry]: source } });
          assert(result.success, JSON.stringify(result));
          traffic.push(
            observeGuestAllocations(result.bytes, [["answer", 5, 22]]),
          );
        } finally {
          await compiler.dispose();
        }
      }
      assert.equal(traffic[0].rounded_allocation_bytes, 0, codegenTier);
      if (codegenTier === "optimized") {
        assert.equal(traffic[1].rounded_allocation_bytes, 0, codegenTier);
      }
      console.log(
        JSON.stringify({
          codegenTier,
          positional: traffic[0].rounded_allocation_bytes,
          named_record: traffic[1].rounded_allocation_bytes,
          calls: traffic[1].calls,
        }),
      );
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
