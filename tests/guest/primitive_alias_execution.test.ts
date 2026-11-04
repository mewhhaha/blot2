import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const fixture = new URL("../../compiler/fixtures/primitive-aliases.blot", import.meta.url);
const importedSource = `import * as primitives from "./primitives"
const apply = func operation -> left -> right => return operation left right
entry const imported = func (value: U32): Array U32 => return do:
  let owner: GrowArray U32 = #[value]
  let alias = primitives.add
  let partial = primitives.subtract owner[0]
  return #[alias owner[0] 7, apply primitives.multiply value 7, partial 7]
entry const imported_float = func (value: F32): F32 => return primitives.negate value
`;
const librarySource = `const add = @u32.add
const subtract = @u32.sub
const multiply = @u32.mul
const negate = @f32.neg
`;
const operatorSource = `type Number is data = $Number U32
const Number.add = func (left: Number) -> (right: Number): Number => return do:
  let $Number a = left
  let $Number b = right
  return $Number (a + b + 100)
entry const operators = func (value: U32): Array U32 => return do:
  let owner: GrowArray U32 = #[value]
  let partial = U32.add owner[0]
  let $Number nominal = $Number value + $Number 2
  return #[value + 2, value - 2, value * 3, partial 2, nominal,
    if value != 7 then 1 else 0, if value <= 7 then 1 else 0,
    if value > 7 then 1 else 0, if value >= 7 then 1 else 0,
    if true == false then 1 else 0, if true != false then 1 else 0]
const apply_bound = func operation -> (value: U32): U32 => return operation value
entry const receiver_callbacks = func (value: U32): Array U32 => return
  #[apply_bound (2.add) value, apply_bound (9.add) value, apply_bound (2.mul) value, apply_bound (9.mul) value]
entry const float_operators = func (value: F32): F32 => return do:
  let partial = F32.mul value
  return partial (2.0 * 2.0) + F32.square value
`;

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`primitive scalar aliases preserve eager calls partial snapshots identities and numeric laws (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-primitive-alias-",
    });
    const entry = `${directory}/main.blot`;
    const library = `${directory}/primitives.blot`;
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0],
      entry,
      prelude: null,
      cacheDirectory: false,
      codegenTier,
    });
    try {
      const source = await Deno.readTextFile(fixture);
      const built = await compiler.build({ sources: { [entry]: source } });
      assert(built.success, JSON.stringify(built));
      const counters = built.stats.workCounters as Record<string, number>;
      assert(
        counters.scoped_function_plan_definitions > 0,
        JSON.stringify(counters),
      );
      assert(counters.scoped_function_plan_hits > 0, JSON.stringify(counters));
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(built.bytes, { asynchronous });
        const call = async (name: string, input: unknown) => {
          if (asynchronous) return await guest.callAsync(name, input);
          return guest.call(name, input);
        };
        try {
          assert.equal(guest.abi.version, 8);
          for (const value of [0, 1, 6, 7, 8, 8192, 0xfffffffe, 0xffffffff]) {
            assert.deepEqual(
              await call("integers", value),
              Uint32Array.of(
                value + 2,
                value - 2,
                Math.imul(value, 3),
                Math.floor(value / 3),
                value % 3,
                value & 15,
                value | 16,
                value ^ 15,
                value << 1,
                value >>> 1,
                Number(value === 7),
                Number(value < 7),
                0,
              ),
            );
            assert.deepEqual(
              await call("higher_order", value),
              Uint32Array.of(
                value + 7,
                value - 7,
                Math.imul(value, 7),
                value + 7,
                value - 7,
                value + 8,
                value + 28,
                value,
                value + 2,
                value + 3,
              ),
            );
            assert.deepEqual(
              await call("snapshots", value),
              Uint32Array.of(
                value + 2,
                value + 12,
                value + 3,
                value + 10,
              ),
            );
            assert.deepEqual(
              await call("references", value),
              Uint32Array.of(
                value + 2,
                value + 12,
                value + 10,
              ),
            );
            assert.deepEqual(
              await call("scalar_reference", value),
              Uint32Array.of(
                value + 2,
                Math.imul(value, 3) + 2,
                Math.imul(value, 3),
              ),
            );
            assert.equal(await call("from_integer", value), Math.fround(value));
          }
          for (const value of [0, -0, 1.5, -2.75, Infinity, -Infinity, NaN]) {
            const absolute = Math.abs(value);
            assert.deepEqual(
              await call("float_reference", value),
              Float32Array.of(value * 2, -value * 2, -value),
            );
            assert.deepEqual(
              await call("floating", value),
              Float32Array.of(
                value + 0.5,
                value - 0.5,
                value * 2,
                value / 2,
                -value,
                absolute,
                Math.sqrt(absolute),
                Math.floor(value),
                Math.ceil(value),
                Math.trunc(value),
                value * 2,
                value * 2,
                value * 3,
              ),
            );
            assert.deepEqual(
              await call("comparisons", value),
              Uint32Array.of(
                Number(value === 0),
                Number(value !== 0),
                Number(value < 0),
                Number(value <= 0),
                Number(value > 0),
                Number(value >= 0),
              ),
            );
          }
          for (
            const value of [
              0,
              -0,
              -1,
              1.75,
              4294967040,
              4294967296,
              Infinity,
              -Infinity,
              NaN,
            ]
          ) {
            let expected = 0;
            if (value > 0) expected = Math.min(0xffffffff, Math.trunc(value));
            assert.equal(await call("from_float", value), expected);
          }
          assert(Object.is(await call("signed_zero", 0), -0));
          assert(Object.is(await call("signed_zero", -0), 0));
          assert.equal(await call("literal_product", null), 4);
          assert(Number.isNaN(await call("constant_nan", null)));
          assert.deepEqual(
            await call("partial_constants", 7),
            Uint32Array.of(9, 16, 9, 16, 11, 18),
          );
          for (const name of ["trap_divide", "trap_remainder"]) {
            await assert.rejects(() => call(name, 0), WebAssembly.RuntimeError);
            let expected = 1;
            if (name === "trap_divide") expected = 3;
            assert.equal(await call(name, 2), expected);
          }
          const trace: number[] = [];
          const observe = (value: number) => {
            trace.push(value);
            return value + 10;
          };
          let host;
          if (asynchronous) {
            host = guest.capabilityAsync({
              parameter: "U32",
              result: "U32",
              call: async (value) => {
                await Promise.resolve();
                return observe(value);
              },
            });
          } else {
            host = guest.capability({
              parameter: "U32",
              result: "U32",
              call: observe,
            });
          }
          assert.equal(await call("eager", host), 23);
          assert.deepEqual(trace, [1, 2]);
          trace.length = 0;
          const reject = (value: number): never => {
            trace.push(value);
            throw new Error("first primitive argument failed");
          };
          let fail;
          if (asynchronous) {
            fail = guest.capabilityAsync({
              parameter: "U32",
              result: "U32",
              call: async (value) => {
                await Promise.resolve();
                return reject(value);
              },
            });
          } else {
            fail = guest.capability({
              parameter: "U32",
              result: "U32",
              call: reject,
            });
          }
          await assert.rejects(
            () => call("eager", fail),
            /Host callback (threw|rejected) during eager/,
          );
          assert.deepEqual(trace, [1]);
          assert.equal(await call("literal_product", null), 4);
        } finally {
          guest.dispose();
        }
      }
      const retained = await compiler.build({ sources: { [entry]: source } });
      assert(retained.success, JSON.stringify(retained));
      assert.deepEqual(retained.bytes, built.bytes);
      const imported = await compiler.build({
        sources: {
          [entry]: importedSource,
          [library]: librarySource,
        },
      });
      assert(imported.success, JSON.stringify(imported));
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(imported.bytes, { asynchronous });
        try {
          assert.equal(guest.abi.version, 8);
          let result;
          let zero;
          if (asynchronous) {
            result = await guest.callAsync("imported", 40);
            zero = await guest.callAsync("imported_float", 0);
          } else {
            result = guest.call("imported", 40);
            zero = guest.call("imported_float", 0);
          }
          assert.deepEqual(result, Uint32Array.of(47, 280, 33));
          assert(Object.is(zero, -0));
        } finally {
          guest.dispose();
        }
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });

  Deno.test(`prelude primitive aliases retain operators associated dispatch and nominal behavior (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-primitive-prelude-",
    });
    const entry = `${directory}/main.blot`;
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0],
      entry,
      prelude: new URL("../../std/prelude.blot", import.meta.url).pathname,
      cacheDirectory: false,
      codegenTier,
    });
    try {
      const built = await compiler.build({
        sources: { [entry]: operatorSource },
      });
      assert(built.success, JSON.stringify(built));
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(built.bytes, { asynchronous });
        const call = async (name: string, input: number) => {
          if (asynchronous) return await guest.callAsync(name, input);
          return guest.call(name, input);
        };
        try {
          assert.equal(guest.abi.version, 8);
          for (const value of [0, 7, 8, 0xffffffff]) {
            assert.deepEqual(
              await call("operators", value),
              Uint32Array.of(
                value + 2,
                value - 2,
                Math.imul(value, 3),
                value + 2,
                value + 102,
                Number(value !== 7),
                Number(value <= 7),
                Number(value > 7),
                Number(value >= 7),
                0,
                1,
              ),
            );
          }
          assert.equal(await call("float_operators", 1.5), 8.25);
          assert.deepEqual(
            await call("receiver_callbacks", 7),
            Uint32Array.of(9, 16, 14, 63),
          );
        } finally {
          guest.dispose();
        }
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
