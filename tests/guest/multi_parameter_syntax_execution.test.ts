import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { compileAndRun, compileExpectedFailure } from "./compile_helpers.ts";

Deno.test("curried parameter lists retain partial application, generic callbacks, and named record calls", async () => {
  await compileAndRun(
    `
const combine = func (first: U32) -> (second: U32) -> (third: U32) => return @u32.add (@u32.add first second) third
const partial = combine 40
const apply = func callback -> value => return callback value
const dimensions = func (fields: { width: U32, height: U32, x: U32, y: U32 }) => return
  @u32.add (@u32.mul fields.width fields.height) (@u32.add fields.x fields.y)
#entry const positional = func (input: U32) => return partial input 1
#entry const generic = func (input: U32) => return apply (func number => return @u32.add number 1) input
#entry const named = func (input: U32) => return dimensions { y: 4, height: 3, x: input, width: 5 }
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
const combine = func first -> second => return @u32.add first second
const dimensions = func (fields: { width: U32, height: U32 }) => return @u32.mul fields.width fields.height
const staged = func (tick: U32 -> U32 ! {Foreign}) => return do:
  use base <- tick 3
  return func (value: U32) => return @u32.add base value
#entry const positional = func (tick: U32 -> U32 ! {Foreign}) => return combine (tick 1) (tick 2)
#entry const named = func (tick: U32 -> U32 ! {Foreign}) => return dimensions { height: tick 2, width: tick 1 }
#entry const later = func (tick: U32 -> U32 ! {Foreign}) => return (staged tick) 4
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
    `const area = func (fields: { width: U32, height: U32 }) => return @u32.mul fields.width fields.height\n#entry const answer = func () => return area `;
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

Deno.test("parameter-list sugar and explicit currying have the same generated size and results", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-curried-parity-" });
  const entry = `${directory}/main.blot`;
  const executable = Deno.args[0] ??
    new URL("../../compiler-goose/build/blotc-goose", import.meta.url);
  try {
    {
      const outputs: Uint8Array<ArrayBuffer>[] = [];
      for (
        const declaration of [
          "func (first: U32) -> (second: U32) => return @u32.add first second",
          "func (first: U32) => return func (second: U32) => return @u32.add first second",
        ]
      ) {
        const source =
          `const sum = ${declaration}\n#entry const answer = func (input: U32) => return sum input 1\n`;
        const compiler = await createZigProjectCompiler({
          executable,
          entry,
          prelude: null,
        });
        try {
          const result = await compiler.build({ sources: { [entry]: source } });
          assert(result.success, JSON.stringify(result));
          outputs.push(result.bytes);
          const exports =
            new WebAssembly.Instance(new WebAssembly.Module(result.bytes))
              .exports;
          assert.equal((exports.answer as CallableFunction)(41), 42);
        } finally {
          await compiler.dispose();
        }
      }
      assert.equal(outputs[0].length, outputs[1].length);
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("named record calls and positional calls agree in both tiers", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-named-call-" });
  const entry = `${directory}/main.blot`;
  const executable = Deno.args[0] ??
    new URL("../../compiler-goose/build/blotc-goose", import.meta.url);
  const declarations = [
    `const calculate = func (a: U32) -> (b: U32) -> (c: U32) -> (d: U32) => return @u32.add (@u32.mul a b) (@u32.mul c d)
#entry const answer = func (input: U32) => return calculate input 2 3 4
`,
    `const calculate = func (args: { a: U32, b: U32, c: U32, d: U32 }) => return @u32.add (@u32.mul args.a args.b) (@u32.mul args.c args.d)
#entry const answer = func (input: U32) => return calculate { d: 4, c: 3, b: 2, a: input }
`,
  ];
  try {
    for (const source of declarations) {
      const compiler = await createZigProjectCompiler({
        executable,
        entry,
        prelude: null,
      });
      try {
        const result = await compiler.build({ sources: { [entry]: source } });
        assert(result.success, JSON.stringify(result));
        const exports =
          new WebAssembly.Instance(new WebAssembly.Module(result.bytes))
            .exports;
        assert.equal((exports.answer as CallableFunction)(5), 22);
      } finally {
        await compiler.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
