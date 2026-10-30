import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../compiler/guest.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

function completeOwnership(bytes: Uint8Array<ArrayBuffer>): void {
  const sections = WebAssembly.Module.customSections(
    new WebAssembly.Module(bytes),
    "blot:ownership",
  );
  equal(sections.length, 1);
  const state = new Uint8Array(sections[0]);
  equal(state[0], 2);
  equal(state[1], 2);
  equal(state[2], 0);
}

Deno.test("runtime existential scalar carriers select both witnesses and reseal lexical openings", async () => {
  await compileAndRun(
    `type Item = exists [a] => a
const make: Bool -> Item = func flag => return if flag then pack [U32] 42 as Item else pack [Bool] true as Item
const reseal: Item -> Item = func item => return unpack item as [a] value in pack [a] value as Item
entry const answer = func (flag: Bool) => return unpack (reseal (make flag)) as [a] value in 42
`,
    (guest, bytes) => {
      completeOwnership(bytes);
      equal(guest.call("answer", true), 42);
      equal(guest.call("answer", false), 42);
    },
    { prelude: "none" },
  );
});

Deno.test("runtime existential operation adapters preserve heterogeneous payloads", async () => {
  await compileAndRun(
    `type Item = exists [a] => (a, a -> U32)
const make: Bool -> Item = func flag => return if flag then pack [U32] (42, func value => return value) as Item else pack [Bool] (true, func value => return if value then 7 else 9) as Item
const read: Item -> U32 = func item => return unpack item as [a] body in (@product.get body 1) (@product.get body 0)
entry const answer = func (flag: Bool) => return read (make flag)
`,
    (guest, bytes) => {
      completeOwnership(bytes);
      equal(guest.call("answer", true), 42);
      equal(guest.call("answer", false), 7);
    },
    { prelude: "none" },
  );
});

Deno.test("runtime package adapters carry references floats records and independent openings", async () => {
  await compileAndRun(
    `type Item = exists [a] => { value: a, run: a -> U32 }
const floats: F32 -> Item = func value => return pack [F32] { value: value, run: func number => return @f32.to_u32 number } as Item
const arrays: U32 -> Item = func value => return pack [Array U32] { value: #[value, 7], run: func values => return @array.get values 0 } as Item
const read: Item -> U32 = func item => return unpack item as [a] body in body.run body.value
entry const answer = func (value: U32) => return do:
  let items = #[arrays value, floats (@u32.to_f32 value)]
  break @u32.add (read (@array.get items 0)) (read (@array.get items 1))
entry const nested = func (value: U32) => return unpack (arrays value) as [a] left in unpack (floats 3.0) as [b] right in @u32.add (left.run left.value) (right.run right.value)
`,
    (guest, bytes) => {
      completeOwnership(bytes);
      equal(guest.call("answer", 21), 42);
      equal(guest.call("answer", 5), 10);
      equal(guest.call("nested", 39), 42);
      const exports =
        new WebAssembly.Instance(new WebAssembly.Module(bytes)).exports;
      const counter = (name: string) =>
        Number((exports[`blot:rc_${name}`] as WebAssembly.Global).value);
      const enter = exports["blot:ownership_enter"] as CallableFunction;
      const leave = exports["blot:ownership_leave"] as CallableFunction;
      const invoke = exports.answer as CallableFunction;
      const destroyed = counter("destroyed");
      for (let repetition = 0; repetition < 3; repetition++) {
        enter();
        equal(invoke(21), 42);
        leave(0);
        equal(counter("roots"), 0);
        equal(counter("leases"), 0);
      }
      assert(counter("destroyed") > destroyed);
    },
    { prelude: "none" },
  );
});
Deno.test("runtime package adapters preserve multiple binders and boxed callback results", async () => {
  await compileAndRun(
    `type Item = exists [a, b] => (a, a -> b, b -> U32)
const make: U32 -> Item = func value => return pack [U32, F32] (value, func number => return @u32.to_f32 number, func number => return @f32.to_u32 number) as Item
const read: Item -> U32 = func item => return unpack item as [a, b] body in (@product.get body 2) ((@product.get body 1) (@product.get body 0))
entry const answer = func (value: U32) => return read (make value)
`,
    (guest, bytes) => {
      completeOwnership(bytes);
      equal(guest.call("answer", 42), 42);
      equal(guest.call("answer", 9), 9);
    },
    { prelude: "none" },
  );
});
Deno.test("runtime package calls preserve traps and independent subsequent invocations", async () => {
  await compileAndRun(
    `type Item = exists [a] => (a, a -> U32)
const make: Bool -> Item = func value => return pack [Bool] (value, func flag => return if flag then 42 else @panic "sealed operation trap") as Item
const read: Item -> U32 = func item => return unpack item as [a] body in (@product.get body 1) (@product.get body 0)
entry const answer = func (value: Bool) => return read (make value)
`,
    (guest, bytes) => {
      completeOwnership(bytes);
      equal(guest.call("answer", true), 42);
      let trapped = false;
      try {
        guest.call("answer", false);
      } catch {
        trapped = true;
      }
      equal(trapped, true);
      equal(guest.call("answer", true), 42);
    },
    { prelude: "none" },
  );
});
Deno.test("package abstraction rejects direct reflection and hidden value escape", async () => {
  await compileExpectedFailure(
    `type Item = exists [a] => a
const wrong: Item -> Bool = func item => return unpack item as [a] value in @type.same value 0
entry const answer = 42
`,
    "abstract_representation_access",
    undefined,
    { prelude: "none" },
  );
  await compileExpectedFailure(
    `type Item = exists [a] => a
const wrong: Item -> U32 = func item => return unpack item as [a] value in value
entry const answer = 42
`,
    "package_escape",
    undefined,
    { prelude: "none" },
  );
});

Deno.test("package carrier revisions preserve fresh bytes after witness edits failure and revert in both tiers", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const original = `type Item = exists [a] => (a, a -> U32)
const make: U32 -> Item = func value => return pack [Array U32] (#[value, 7], func values => return @array.get values 0) as Item
const read: Item -> U32 = func item => return unpack item as [a] body in (@product.get body 1) (@product.get body 0)
entry const answer = func (value: U32) => return read (make value)
`;
  const changed = original.replace("#[value, 7]", "#[@u32.add value 1, 7]");
  const failed = original.replace("pack [Array U32]", "pack [Bool]");
  try {
    for (const codegenTier of ["optimized", "development"] as const) {
      const options = {
        executable: Deno.args[0] ??
          new URL("../zig-out-dev/bin/blotc", import.meta.url),
        entry,
        prelude: null,
        codegenTier,
        cacheDirectory: false as const,
      };
      const retained = await createZigProjectCompiler(options);
      try {
        for (
          const [index, source] of [original, changed, failed, original]
            .entries()
        ) {
          const result = await retained.build({ sources: { [entry]: source } });
          const fresh = await createZigProjectCompiler(options);
          try {
            const expected = await fresh.build({
              sources: { [entry]: source },
            });
            equal(result.success, expected.success);
            if (!result.success && !expected.success) {
              equal(index, 2);
              assert.deepEqual(result.diagnostics, expected.diagnostics);
              continue;
            }
            assert(result.success && expected.success);
            assert.deepEqual(result.bytes, expected.bytes);
            completeOwnership(result.bytes);
            const guest = await instantiateGuest(result.bytes);
            try {
              let value = 42;
              if (index === 1) value = 43;
              equal(guest.call("answer", 42), value);
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
