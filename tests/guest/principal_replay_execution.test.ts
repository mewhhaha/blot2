import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";

// Constants are computed at instantiation, so a constant that divides by zero
// compiles and its module traps when instantiated.
async function trapsAtInstantiation(bytes: Uint8Array<ArrayBuffer>) {
  await assert.rejects(WebAssembly.instantiate(bytes), WebAssembly.RuntimeError);
}

Deno.test("completed captured callbacks preserve edits and rejection recovery", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-completed-capture-",
  });
  const entry = `${directory}/main.blot`;
  const source = (seed: number | null, schema: number) =>
    `const add = func extra => return ${
      seed === null ? "@f32.add extra 1.0" : `@u32.add extra ${seed}`
    }
const factory = func invoke => return func extra => return invoke extra
const callback = factory add
#entry const schema: U32 = ${schema}
#entry const answer = func (extra: U32) : U32 => return callback extra
`;
  try {
    await Deno.writeTextFile(entry, source(42, 7));
    {
      const options = {
        executable: Deno.args[0] ??
          new URL("../../compiler-goose/build/blotc-goose", import.meta.url).pathname,
        entry,
        prelude: null,
      };
      const retained = await createZigProjectCompiler(options);
      try {
        for (
          const [seed, schema] of [[42, 7], [42, 9], [43, 9], [null, 9], [
            42,
            7,
          ]] as const
        ) {
          const sources = { [entry]: source(seed, schema) };
          const actual = await retained.build({ sources });
          const fresh = await createZigProjectCompiler(options);
          try {
            const expected = await fresh.build({ sources });
            assert.equal(actual.success, expected.success);
            if (seed === null) {
              assert(!actual.success && !expected.success);
              assert.deepEqual(actual.diagnostics, expected.diagnostics);
              continue;
            }
            assert(actual.success && expected.success, JSON.stringify(actual));
            assert.deepEqual(actual.bytes, expected.bytes);
            const { instance } = await WebAssembly.instantiate(actual.bytes);
            const answer = instance.exports.answer;
            assert.equal(typeof answer, "function");
            assert.equal((answer as CallableFunction)(5), seed + 5);
          } finally {
            await fresh.dispose();
          }
        }
      } finally {
        await retained.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("retained nested source owners preserve unrelated edits consumed closures callbacks and error recovery", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-source-owner-" });
  const entry = `${directory}/main.blot`;
  const library = `${directory}/library.blot`;
  const source = (divisor: number, unused: number) =>
    `const force = func value => return value ()
const make = func (seed: U32) => return do:
  let captured = func (value: U32) => return @u32.div (@u32.add seed (force (func () => return value))) ${divisor}
  break captured
const unrelated = func (value: U32) => return @u32.add value ${unused}
`;
  try {
    await Deno.writeTextFile(
      entry,
      'import { make } from "./library"\n#entry const answer: U32 = (make 6) 2\n',
    );
    await Deno.writeTextFile(library, source(2, 1));
    {
      const options = {
        executable: Deno.args[0] ??
          new URL("../../compiler-goose/build/blotc-goose", import.meta.url).pathname,
        entry,
        prelude: null,
      };
      const retained = await createZigProjectCompiler(options);
      try {
        for (
          const [divisor, unused] of [[2, 1], [2, 7], [4, 7], [0, 7], [2, 1]]
        ) {
          const sources = { [library]: source(divisor, unused) };
          const result = await retained.build({ sources });
          const fresh = await createZigProjectCompiler(options);
          try {
            const expected = await fresh.build({ sources });
            assert.equal(result.success, expected.success);
            assert(result.success && expected.success, JSON.stringify(result));
            assert.deepEqual(result.bytes, expected.bytes);
            if (divisor === 0) {
              await trapsAtInstantiation(result.bytes);
              continue;
            }
            const { instance } = await WebAssembly.instantiate(result.bytes);
            const answer = instance.exports.answer;
            assert.equal(
              typeof answer === "function"
                ? answer()
                : (answer as WebAssembly.Global).value,
              8 / divisor,
            );
          } finally {
            await fresh.dispose();
          }
        }
      } finally {
        await retained.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("retained deep layered values preserve edits traps recovery and execution", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-principal-depth-" });
  const entry = `${directory}/main.blot`;
  // Cross the retained proof importer's 128-level depth bound, while staying
  // within ordinary inference's 256-level bound. These are linear-size values.
  const layers = Array.from(
    { length: 130 },
    (_, i) => `  let layer_${i + 1} = wrap layer_${i}`,
  ).join("\n");
  const source = (value: number) =>
    `const wrap = func value => return (value, 0)
const ignore = func value => return 1
#entry const answer: U32 = do:
  let seed = ${value}
  let layer_0 = wrap seed
${layers}
  break @u32.div 8 (@u32.mul seed (ignore layer_130))
`;
  try {
    await Deno.writeTextFile(entry, source(2));
    {
      const options = {
        executable: Deno.args[0] ??
          new URL("../../compiler-goose/build/blotc-goose", import.meta.url).pathname,
        entry,
        prelude: null,
      };
      const retained = await createZigProjectCompiler(options);
      try {
        for (const value of [2, 4, 0, 2, 1]) {
          const sources = { [entry]: source(value) };
          const built = await retained.build({ sources });
          const fresh = await createZigProjectCompiler(options);
          try {
            const expected = await fresh.build({ sources });
            assert(built.success, JSON.stringify(built));
            assert(expected.success, JSON.stringify(expected));
            assert.deepEqual(built.bytes, expected.bytes);
            if (value === 0) {
              await trapsAtInstantiation(built.bytes);
              continue;
            }
            const { instance } = await WebAssembly.instantiate(built.bytes);
            const answer = instance.exports.answer;
            assert.equal(
              typeof answer === "function"
                ? answer()
                : (answer as WebAssembly.Global).value,
              Math.floor(8 / value),
            );
          } finally {
            await fresh.dispose();
          }
        }
      } finally {
        await retained.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("recursive summaries preserve body edits traps and recovery", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-principal-summary-",
  });
  const entry = `${directory}/main.blot`;
  const source = (seed: number, operation = "add", unrelated = "sub") =>
    `const local = func value => return @u32.${operation} value 1
const subtract = func value => return @u32.sub value 2
const unused = func value => return @u32.${unrelated} value 2
const even: U32 -> U32 = func value => return if @u32.eq value 0 then 41 else odd (@u32.sub value 1)
const odd: U32 -> U32 = func value => return if @u32.eq value 0 then 41 else even (@u32.sub value 1)
#entry const first: U32 = do:
  let identity = func value => return value
  break identity (@u32.div 8 ${seed})
#entry const second: U32 = local (even ${seed})
#entry const third: U32 = local (odd ${seed})
`;
  try {
    await Deno.writeTextFile(entry, source(2));
    {
      const options = {
        executable: Deno.args[0] ??
          new URL("../../compiler-goose/build/blotc-goose", import.meta.url).pathname,
        entry,
        prelude: null,
      };
      const retained = await createZigProjectCompiler(options);
      try {
        for (
          const [seed, operation, unrelated] of [
            [2, "add", "sub"],
            [4, "add", "sub"],
            [4, "add", "add"],
            [4, "sub", "add"],
            [0, "add", "sub"],
            [2, "add", "sub"],
          ]
        ) {
          const value = Number(seed);
          const sources = {
            [entry]: source(value, String(operation), String(unrelated)),
          };
          const built = await retained.build({ sources });
          const fresh = await createZigProjectCompiler({
            ...options,
          });
          try {
            const expected = await fresh.build({ sources });
            assert(built.success, JSON.stringify(built));
            assert(expected.success, JSON.stringify(expected));
            assert.deepEqual(built.bytes, expected.bytes);
            if (value === 0) {
              await trapsAtInstantiation(built.bytes);
              continue;
            }
            const { instance } = await WebAssembly.instantiate(built.bytes);
            for (
              const [name, result] of Object.entries({
                first: Math.floor(8 / value),
                second: operation === "add" ? 42 : 40,
                third: operation === "add" ? 42 : 40,
              })
            ) {
              const exported = instance.exports[name];
              assert.equal(
                typeof exported === "function"
                  ? exported()
                  : (exported as WebAssembly.Global).value,
                result,
              );
            }
          } finally {
            await fresh.dispose();
          }
        }
      } finally {
        await retained.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("checked interfaces execute changed bodies and preserve traps and recovery", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-checked-interface-",
  });
  const entry = `${directory}/main.blot`;
  const source = (operation: string, operand: number) =>
    `const add = func (x: U32) : U32 => return @u32.add x 1
const sub = func (x: U32) : U32 => return @u32.sub x 1
const div = func (x: U32) : U32 => return @u32.div x 1
const local = func (x: U32) : U32 => return @u32.${operation} x ${operand}
#entry const answer: U32 = local 41
`;
  try {
    await Deno.writeTextFile(entry, source("add", 1));
    {
      const options = {
        executable: Deno.args[0] ??
          new URL("../../compiler-goose/build/blotc-goose", import.meta.url).pathname,
        entry,
        prelude: null,
      };
      const retained = await createZigProjectCompiler(options);
      try {
        for (
          const [operation, operand, answer] of ([
            ["add", 1, 42],
            ["sub", 1, 40],
            ["div", 0, null],
            ["sub", 2, 39],
            ["add", 1, 42],
          ] as const)
        ) {
          const sources = { [entry]: source(operation, operand) };
          const result = await retained.build({ sources });
          const fresh = await createZigProjectCompiler(options);
          try {
            const expected = await fresh.build({ sources });
            assert.equal(result.success, expected.success);
            assert(result.success && expected.success, JSON.stringify(result));
            assert.deepEqual(result.bytes, expected.bytes);
            if (answer === null) {
              await trapsAtInstantiation(result.bytes);
              continue;
            }
            const { instance } = await WebAssembly.instantiate(result.bytes);
            const actual = instance.exports.answer;
            assert.equal(
              typeof actual === "function"
                ? actual()
                : (actual as WebAssembly.Global).value,
              answer,
            );
          } finally {
            await fresh.dispose();
          }
        }
      } finally {
        await retained.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("completed inferred interfaces preserve current conversions body edits traps and recovery", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-completed-interface-",
  });
  const entry = `${directory}/main.blot`;
  const source = (rounding: string, member = "from") =>
    `type Token is data = $Token U32
const Token.from = func value => return $Token (@f32.to_u32 value)
const Token.fail = func value => return $Token (@u32.div (@f32.to_u32 value) 0)
const from = func value => return @type.result "${member}" value
const floor_impl = func value => return @f32.floor value
const ceil_impl = func value => return @f32.ceil value
const floor = floor_impl
const ceil = ceil_impl
const local = func value => return from (${rounding} value)
#entry const answer: U32 = case local 41.25 of
  $Token value => value
`;
  try {
    await Deno.writeTextFile(entry, source("floor"));
    {
      const options = {
        executable: Deno.args[0] ??
          new URL("../../compiler-goose/build/blotc-goose", import.meta.url).pathname,
        entry,
        prelude: null,
      };
      const retained = await createZigProjectCompiler(options);
      try {
        for (
          const [rounding, member, answer] of ([
            ["floor", "from", 41],
            ["ceil", "from", 42],
            ["ceil", "fail", null],
            ["ceil", "from", 42],
            ["floor", "from", 41],
          ] as const)
        ) {
          const sources = { [entry]: source(rounding, member) };
          const result = await retained.build({ sources });
          const fresh = await createZigProjectCompiler(options);
          try {
            const expected = await fresh.build({ sources });
            assert.equal(result.success, expected.success);
            assert(result.success && expected.success, JSON.stringify(result));
            assert.deepEqual(result.bytes, expected.bytes);
            if (answer === null) {
              await trapsAtInstantiation(result.bytes);
              continue;
            }
            const { instance } = await WebAssembly.instantiate(result.bytes);
            const actual = instance.exports.answer;
            assert.equal(
              typeof actual === "function"
                ? actual()
                : (actual as WebAssembly.Global).value,
              answer,
            );
          } finally {
            await fresh.dispose();
          }
        }
      } finally {
        await retained.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
