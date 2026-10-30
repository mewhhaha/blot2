import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../compiler/guest.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";
Deno.test("rank two callbacks execute one parametric carrier across U32 and F32 instances", async () => {
  await compileAndRun(
    `const two: (forall [a] => a -> a) -> U32 -> (U32, F32) = func identity => return func value => return (identity value, identity (@u32.to_f32 value))
const id: forall [a] => a -> a = func value => return value
entry const whole = func (value: U32) => return @product.get (two id value) 0
entry const fraction = func (value: U32) => return @product.get (two id value) 1
`,
    (guest, bytes) => {
      const ownership = new Uint8Array(
        WebAssembly.Module.customSections(
          new WebAssembly.Module(bytes),
          "blot:ownership",
        )[0],
      );
      equal(ownership[0], 2);
      equal(ownership[1], 2);
      equal(ownership[2], 0);
      equal(guest.call("whole", 42), 42);
      equal(guest.call("fraction", 13), 13);
    },
    { prelude: "none" },
  );
});

Deno.test("rank callbacks preserve fresh retained failed edit and revert results in both tiers", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const producer = "const id: forall [a] => a -> a = func value => return value\n";
  const consumer =
    `const two: (forall [a] => a -> a) -> U32 -> (U32, F32) = func identity => return func value => return (identity value, identity (@u32.to_f32 value))
entry const whole = func (value: U32) => return @product.get (two id value) 0
entry const fraction = func (value: U32) => return @product.get (two id value) 1
`;
  try {
    for (const codegenTier of ["development", "optimized"] as const) {
      const options = {
        executable: Deno.args[0] ??
          new URL("../zig-out/bin/blotc", import.meta.url),
        entry,
        prelude: null,
        codegenTier,
        cacheDirectory: false as const,
      };
      const retained = await createZigProjectCompiler(options);
      try {
        const revisions = [
          { main: consumer, producer },
          { main: consumer.replace("two id value", "two id 43"), producer },
          { main: consumer, producer: producer.replace("=> return value", "=> return 42") },
          { main: consumer, producer },
        ];
        for (const [index, revision] of revisions.entries()) {
          const sources = { [entry]: revision.producer + revision.main };
          const actual = await retained.build({ sources });
          const fresh = await createZigProjectCompiler(options);
          try {
            const expected = await fresh.build({ sources });
            assert.equal(actual.success, expected.success);
            if (!actual.success && !expected.success) {
              assert.equal(index, 2, JSON.stringify(actual));
              assert.deepEqual(actual.diagnostics, expected.diagnostics);
              assert.equal(actual.diagnostics[0].code, "rank_mismatch");
              continue;
            }
            assert(actual.success && expected.success, JSON.stringify(actual));
            assert.notEqual(index, 2);
            assert.deepEqual(actual.bytes, expected.bytes);
            const guest = await instantiateGuest(actual.bytes);
            try {
              let whole = 42;
              if (index === 1) whole = 43;
              assert.equal(guest.call("whole", 42), whole);
              assert.equal(guest.call("fraction", 17), 17);
            } finally {
              guest.dispose();
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

Deno.test("rank callbacks reject concrete-only implementations", async () => {
  await compileExpectedFailure(
    `const two: (forall [a] => a -> a) -> U32 = func identity => return identity 42
entry const run = func () => return two (func (value: U32) => return @u32.add value 1)
`,
    "type_mismatch",
    undefined,
    { prelude: "none" },
  );
});

Deno.test("rank two explicit lambda introductions retain runtime captured environment", async () => {
  await compileAndRun(
    `const two: (forall [a] => a -> a) -> U32 -> (U32, F32) = func identity => return func value => return (identity value, identity (@u32.to_f32 value))
const make: U32 -> (forall [a] => a -> a) = func captured => return func item => return do:
  let ignored = @u32.add captured 1
  break item
entry const whole = func (value: U32) => return @product.get (two (make value) value) 0
entry const fraction = func (value: U32) => return @product.get (two (func item => return item) value) 1
`,
    (guest, bytes) => {
      const state = new Uint8Array(
        WebAssembly.Module.customSections(
          new WebAssembly.Module(bytes),
          "blot:ownership",
        )[0],
      );
      equal(state[0], 2);
      equal(state[1], 2);
      equal(state[2], 0);
      equal(guest.call("whole", 42), 42);
      equal(guest.call("fraction", 17), 17);
    },
    { prelude: "none" },
  );
});
Deno.test("rank two annotated results preserve universal closure across runtime boundary", async () => {
  await compileAndRun(
    `const two: (forall [a] => a -> a) -> U32 -> (U32, F32) = func identity => return func value => return (identity value, identity (@u32.to_f32 value))
const make: Bool -> (forall [a] => a -> a) = func flag => return if flag then (func value => return value) else (func value => return value)
entry const whole = func (flag: Bool) => return @product.get (two (make flag) 42) 0
entry const fraction = func (flag: Bool) => return @product.get (two (make flag) 17) 1
`,
    (guest, bytes) => {
      const state = new Uint8Array(
        WebAssembly.Module.customSections(
          new WebAssembly.Module(bytes),
          "blot:ownership",
        )[0],
      );
      equal(state[0], 2);
      equal(state[1], 2);
      equal(state[2], 0);
      equal(guest.call("whole", true), 42);
      equal(guest.call("fraction", false), 17);
    },
    { prelude: "none" },
  );
});

Deno.test("rank two annotated record fields retain their universal storage interface", async () => {
  await compileAndRun(
    `const two: { identity: forall [a] => a -> a } -> U32 -> (U32, F32) = func holder => return func value => return (holder.identity value, holder.identity (@u32.to_f32 value))
const id: forall [a] => a -> a = func value => return value
entry const whole = func (value: U32) => return @product.get (two { identity: id } value) 0
entry const fraction = func (value: U32) => return @product.get (two { identity: id } value) 1
`,
    (guest, bytes) => {
      const state = new Uint8Array(
        WebAssembly.Module.customSections(
          new WebAssembly.Module(bytes),
          "blot:ownership",
        )[0],
      );
      equal(state[0], 2);
      equal(state[1], 2);
      equal(state[2], 0);
      equal(guest.call("whole", 42), 42);
      equal(guest.call("fraction", 17), 17);
    },
    { prelude: "none" },
  );
});
Deno.test("universal results eliminate directly at independent runtime instances", async () => {
  await compileAndRun(
    `const make: Bool -> (forall [a] => a -> a) = func flag => return if flag then (func value => return value) else (func value => return value)
entry const whole = func (flag: Bool) => return (make flag) 42
entry const fraction = func (flag: Bool) => return (make flag) 3.5
`,
    (guest, bytes) => {
      const state = new Uint8Array(
        WebAssembly.Module.customSections(
          new WebAssembly.Module(bytes),
          "blot:ownership",
        )[0],
      );
      equal(state[0], 2);
      equal(state[1], 2);
      equal(state[2], 0);
      equal(guest.call("whole", true), 42);
      equal(guest.call("fraction", false), 3.5);
    },
    { prelude: "none" },
  );
});
