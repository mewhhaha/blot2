import { strict as assert } from "node:assert";
import { compileAndRun, compileExpectedFailure } from "./compile_helpers.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";

const definitions = `
type Box f is data = #Box f
const box = fn value => #Box value
const get = fn (#Box mapper) => mapper
`;

for (const codegenTier of ["optimized", "development"] as const) {
  Deno.test(`closed local initializers preserve loop and branch versions (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir();
    const entry = `${directory}/main.blot`;
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0] ??
        new URL("../zig-out/bin/blotc", import.meta.url),
      entry,
      prelude: null,
      codegenTier,
      cacheDirectory: false,
    });
    try {
      const source = `
type Maybe value is data = #Nothing | #Just value
entry const loop = fn (limit: U32) => do:
  let pending = (#Nothing, #[1])
  let index = 0
  for ever:
    let (state, request) = pending
    if @u32.eq index limit:
      break case state of
        #Nothing => request[0]
        #Just value => @u32.add value request[0]
    pending := (#Just index, #[@u32.add index 2])
    index := @u32.add self 1
entry const branch = fn (value: U32) => do:
  let pending = (#Nothing, #[1])
  if @u32.lt 0 value:
    pending := (#Just value, #[2])
  let (state, request) = pending
  break case state of
    #Nothing => request[0]
    #Just item => @u32.add item request[0]
`;
      const result = await compiler.build({ sources: { [entry]: source } });
      if (!result.success) throw new Error(JSON.stringify(result.diagnostics));
      const module = new WebAssembly.Module(result.bytes);
      assert.deepEqual([
        ...new Uint8Array(
          WebAssembly.Module.customSections(module, "blot:ownership")[0],
        ),
      ], [2, 2, 0]);
      const guest = await instantiateGuest(module);
      try {
        assert.equal(guest.call("loop", 0), 1);
        assert.equal(guest.call("branch", 0), 1);
        assert.equal(guest.call("loop", 4096), 8192);
        const warm = guest.memoryBytes();
        for (let repeat = 0; repeat < 32; repeat++) {
          assert.equal(guest.call("branch", 8192), 8194);
          assert.equal(guest.call("loop", 4096), 8192);
        }
        assert.equal(guest.memoryBytes(), warm);
      } finally {
        guest.dispose();
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}

Deno.test("single-use local creators preserve selected scalar and reference fields", async () => {
  for (
    const [type, read] of [
      ["U32", "@u32.add (mapper seed).item 1"],
      ["F32", "@f32.add (mapper seed).item 1.0"],
      ["Array U32", "@array.length (mapper seed).item"],
    ]
  ) {
    await compileAndRun(
      definitions + `
entry const run = fn (seed: ${type}) => do:
  let stored = box (fn value => {item: value})
  let #Box mapper = stored
  break ${read}
`,
      (guest, bytes) => {
        const module = new WebAssembly.Module(bytes);
        assert.deepEqual([
          ...new Uint8Array(
            WebAssembly.Module.customSections(module, "blot:ownership")[0],
          ),
        ], [2, 2, 0]);
        let argument: number | Uint32Array = 8192;
        let expected = 8193;
        if (type === "F32") {
          argument = 41.5;
          expected = 42.5;
        }
        if (type === "Array U32") {
          argument = Uint32Array.of(41, 8192);
          expected = 2;
        }
        assert.equal(guest.call("run", argument), expected);
      },
    );
  }
});

Deno.test("multiple generic local instances retain independent checked views", async () => {
  await compileAndRun(
    definitions + `
entry const run = fn (seed: U32) => do:
  let stored = box (fn value => {item: value})
  let scalar = (get stored seed).item
  let reference = (get stored #[seed, 8192]).item
  break @u32.add scalar reference[0]
`,
    (guest, bytes) => {
      const module = new WebAssembly.Module(bytes);
      const mode = new Uint8Array(
        WebAssembly.Module.customSections(module, "blot:ownership")[0],
      );
      assert.deepEqual([...mode], [2, 2, 0]);
      assert.equal(guest.call("run", 65536), 131072);
    },
  );
});

Deno.test("captured closed generic local storage retains its static value and checked view", async () => {
  await compileAndRun(
    definitions + `
entry const run = fn (seed: U32) => do:
  let stored = box (fn value => {item: value})
  let read = fn (value: U32) => (get stored value).item
  break read seed
`,
    (guest, bytes) => {
      const module = new WebAssembly.Module(bytes);
      const mode = new Uint8Array(
        WebAssembly.Module.customSections(module, "blot:ownership")[0],
      );
      assert.deepEqual([...mode], [2, 2, 0]);
      assert.equal(guest.call("run", 8192), 8192);
    },
  );
});

Deno.test("local storage promotion preserves runtime captures traps and eager host order", async () => {
  await compileExpectedFailure(
    definitions + `
type Phantom value is data = #Phantom
entry const run = fn () => do:
  let stored: Box (Phantom (unique U32)) = box #Phantom
  break ()
`,
    "multiplicity_unknown",
    undefined,
    { prelude: "none" },
  );

  await compileAndRun(
    definitions + `
entry const run = fn (seed: U32) => do:
  let stored = box (fn value => {item: @u32.add value seed})
  let #Box mapper = stored
  break (mapper 3).item
`,
    (guest) => {
      assert.equal(guest.call("run", 10), 13);
      assert.equal(guest.call("run", 20), 23);
    },
    { prelude: "none" },
  );

  await compileAndRun(
    definitions + `
entry const run = fn (seed: U32) => do:
  let stored = box (fn value => {item: @u32.div value 0})
  let #Box mapper = stored
  break (mapper seed).item
`,
    (guest) => {
      assert.throws(() => guest.call("run", 7), WebAssembly.RuntimeError);
    },
    { prelude: "none" },
  );

  await compileAndRun(
    definitions + `
entry const run = fn (seed: U32) => do:
  let stored = box ((fn value => {item: value}), @u32.div seed 0)
  let #Box (mapper, _) = stored
  break (mapper 7).item
`,
    (guest) => {
      assert.throws(() => guest.call("run", 7), WebAssembly.RuntimeError);
    },
    { prelude: "none" },
  );

  await compileAndRun(
    definitions + `
entry const run = fn (host: Unit -> U32 ! {Foreign}) => do:
  use before <- host ()
  use stored <- box ((fn value => {item: value}), host ())
  let #Box (mapper, during) = stored
  use after <- host ()
  break @u32.add (@u32.mul before 100) (@u32.add (@u32.mul during 10) (@u32.add after (mapper 7).item))
`,
    async (_guest, bytes) => {
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(bytes, { asynchronous });
        try {
          let calls = 0;
          let callback = guest.capability({
            parameter: "Unit",
            result: "U32",
            call: () => ++calls,
          });
          if (asynchronous) {
            callback = guest.capabilityAsync({
              parameter: "Unit",
              result: "U32",
              call: async () => {
                await Promise.resolve();
                return ++calls;
              },
            });
          }
          let answer: unknown;
          if (asynchronous) answer = await guest.callAsync("run", callback);
          else answer = guest.call("run", callback);
          assert.equal(answer, 130);
          assert.equal(calls, 3);
        } finally {
          guest.dispose();
        }
      }
    },
    { prelude: "none" },
  );
});

Deno.test("closed local wrapper body edits retain fresh failure recovery and restart parity", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-local-wrapper-" });
  const entry = `${directory}/main.blot`;
  const dependency = `${directory}/wrapper.blot`;
  const options = {
    executable: Deno.args[0] ??
      new URL("../zig-out/bin/blotc", import.meta.url),
    entry,
    prelude: null,
  };
  const cached = { ...options, cacheDirectory: `${directory}/cache` };
  const library = `type Box f is data = #Box (f, U32)
const box = fn value => #Box (value, 1)
const get = fn (#Box (mapper, _)) => mapper
const stamp = fn (#Box (_, value)) => value
`;
  const source = `import {Box, box, get, stamp} from "./wrapper"
entry const run = fn (seed: U32) => do:
  let stored = box (fn value => {item: value})
  let read = fn (value: U32) => @u32.add (get stored value).item (stamp stored)
  let reference = (get stored #[seed, 8192]).item
  break @u32.add (read seed) reference[0]
`;
  const observe = async (bytes: Uint8Array<ArrayBuffer>, expected: number) => {
    const module = new WebAssembly.Module(bytes);
    assert.deepEqual([
      ...new Uint8Array(
        WebAssembly.Module.customSections(module, "blot:ownership")[0],
      ),
    ], [2, 2, 0]);
    for (const asynchronous of [false, true]) {
      const guest = await instantiateGuest(bytes, { asynchronous });
      try {
        if (asynchronous) {
          assert.equal(await guest.callAsync("run", 8192), expected);
        } else assert.equal(guest.call("run", 8192), expected);
      } finally {
        guest.dispose();
      }
    }
  };
  const compiler = await createZigProjectCompiler(cached);
  try {
    for (const mark of [1, 2]) {
      const sources = {
        [entry]: source,
        [dependency]: library.replace("value, 1", `value, ${mark}`),
      };
      const fresh = await createZigProjectCompiler({
        ...options,
        cacheDirectory: false,
      });
      try {
        const expected = await fresh.build({ sources });
        assert(expected.success, JSON.stringify(expected));
        const result = await compiler.build({ sources });
        assert(result.success, JSON.stringify(result));
        assert.deepEqual(result.bytes, expected.bytes);
        await observe(result.bytes, 16384 + mark);
        const unchanged = await compiler.build({ sources });
        assert(unchanged.success, JSON.stringify(unchanged));
        assert.deepEqual(unchanged.bytes, result.bytes);
        assert.equal(unchanged.stats.attemptStats.reused_output, true);
        assert.equal(unchanged.stats.nativeWorkSteps, 0);
        const failed = await compiler.build({
          sources: {
            ...sources,
            [dependency]: sources[dependency].replace(
              `value, ${mark}`,
              "value, missing",
            ),
          },
        });
        assert(!failed.success, JSON.stringify(failed));
        await observe(result.bytes, 16384 + mark);
        const recovered = await compiler.build({ sources });
        assert(recovered.success, JSON.stringify(recovered));
        assert.deepEqual(recovered.bytes, expected.bytes);
        const restarted = await createZigProjectCompiler(cached);
        try {
          const resumed = await restarted.build({ sources });
          assert(resumed.success, JSON.stringify(resumed));
          assert.deepEqual(resumed.bytes, expected.bytes);
          await observe(resumed.bytes, 16384 + mark);
        } finally {
          await restarted.dispose();
        }
      } finally {
        await fresh.dispose();
      }
    }
  } finally {
    await compiler.dispose();
    // dispose aborts the server; its detached cache writer may still own the
    // directory. Opening the same key waits for that writer before teardown.
    const settled = await createZigProjectCompiler(cached);
    await settled.close();
    await Deno.remove(directory, { recursive: true });
  }
});
