import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../compiler/guest.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { compileAndRun, equal } from "./compile_helpers.ts";

function destroyedAfterCalls(
  bytes: Uint8Array<ArrayBuffer>,
  value: number,
  expected: number,
): void {
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
    equal(invoke(value), expected);
    leave(0);
    equal(counter("roots"), 0);
    equal(counter("leases"), 0);
  }
  if (counter("destroyed") <= destroyed) {
    throw new Error("Carrier payloads were not destroyed");
  }
}

Deno.test("sequence carrier witness revisions preserve both-tier retained failure and revert equality", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const source = `type Item = exists [a] => (Array a, Array a -> U32)
const make: U32 -> Item = func count => return pack [U32] (@array.generate count (func index => return index), func (values: Array U32) => return @array.length values) as Item
entry const answer = func (count: U32) => return unpack (make count) as [a] body in (@product.get body 1) (@product.get body 0)
`;
  const edited = source.replaceAll("U32]", "Bool]")
    .replace("func index => return index", "func index => return true")
    .replace("values: Array U32", "values: Array Bool");
  const revisions = [
    source,
    edited,
    source.replace("pack [U32]", "pack [Bool]"),
    source,
  ];
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
        for (const [index, revision] of revisions.entries()) {
          const sources = { [entry]: revision };
          const actual = await retained.build({ sources });
          const fresh = await createZigProjectCompiler(options);
          try {
            const expected = await fresh.build({ sources });
            assert.equal(actual.success, expected.success);
            if (!actual.success && !expected.success) {
              assert.equal(index, 2, JSON.stringify(actual));
              assert.deepEqual(actual.diagnostics, expected.diagnostics);
              assert.equal(
                actual.diagnostics[0].code,
                "type_mismatch",
              );
              continue;
            }
            assert(actual.success && expected.success, JSON.stringify(actual));
            assert.notEqual(index, 2);
            assert.deepEqual(actual.bytes, expected.bytes);
            const guest = await instantiateGuest(actual.bytes);
            try {
              equal(guest.call("answer", 0), 0);
              equal(guest.call("answer", 513), 513);
              destroyedAfterCalls(actual.bytes, 513, 513);
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

for (const collection of ["Array", "List"] as const) {
  Deno.test(`package adapters convert ${collection} elements and packed rows in both directions`, async () => {
    const prefix = collection.toLowerCase();
    let rows = "rows";
    if (collection === "List") rows = "(@array.from_list rows)";
    await compileAndRun(
      `type Item = exists [a] => (${collection} (a, U32), ${collection} (a, U32) -> U32)
const make: U32 -> Item = func count => return pack [U32] (@${prefix}.generate count (func index => return (index, @u32.add index 10)), func (rows: ${collection} (U32, U32)) => return @u32.add (@product.get (@array.get ${rows} 0) 0) (@product.get (@array.get ${rows} (@u32.sub count 1)) 1)) as Item
const read: Item -> U32 = func item => return unpack item as [a] body in (@product.get body 1) (@product.get body 0)
entry const answer = func (count: U32) => return read (make count)
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
        equal(guest.call("answer", 1), 10);
        assert.throws(() => guest.call("answer", 0));
        equal(guest.call("answer", 17), 26);
        equal(guest.call("answer", 513), 522);
        destroyedAfterCalls(bytes, 513, 522);
      },
      { prelude: "none" },
    );
  });
}
Deno.test("package collection adapters preserve hidden reference leaves and operation results", async () => {
  await compileAndRun(
    `type Item = exists [a] => (Array a, Array a -> a, a -> U32)
const make: U32 -> Item = func value => return pack [Array U32] (#[#[value], #[@u32.add value 1]], func (values: Array (Array U32)) => return @array.get values 1, func (values: Array U32) => return @array.get values 0) as Item
const read: Item -> U32 = func item => return unpack item as [a] body in (@product.get body 2) ((@product.get body 1) (@product.get body 0))
entry const answer = func (value: U32) => return read (make value)
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
      equal(guest.call("answer", 41), 42);
      equal(guest.call("answer", 16), 17);
      destroyedAfterCalls(bytes, 41, 42);
    },
    { prelude: "none" },
  );
});

Deno.test("package adapters convert tagged and recursive nominal payloads through owned helper edges", async () => {
  await compileAndRun(
    `type Chain a is data = $End | $Link (a, Chain a)
type Item = exists [a] => (Chain a, Chain a -> U32)
const make: U32 -> Item = func value => return pack [U32] ($Link (value, $Link (13, $End)), func (chain: Chain U32) => return case chain of
  $End => 0
  $Link (head, tail) => head
) as Item
const read: Item -> U32 = func item => return unpack item as [a] body in (@product.get body 1) (@product.get body 0)
entry const answer = func (value: U32) => return read (make value)
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
      equal(guest.call("answer", 42), 42);
      equal(guest.call("answer", 17), 17);
      destroyedAfterCalls(bytes, 42, 42);
    },
    { prelude: "none" },
  );
});
Deno.test("package adapters preserve opaque nominal erasure across scalar and abstract payload layouts", async () => {
  await compileAndRun(
    `opaque type Box a = a
type Item = exists [a] => (Box a, Box a -> U32)
const make: U32 -> Item = func value => return pack [U32] ($Box value, func (box: Box U32) => return case box of
  $Box inner => inner
) as Item
const read: Item -> U32 = func item => return unpack item as [a] body in (@product.get body 1) (@product.get body 0)
entry const answer = func (value: U32) => return read (make value)
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
      equal(guest.call("answer", 42), 42);
      equal(guest.call("answer", 17), 17);
      destroyedAfterCalls(bytes, 42, 42);
    },
    { prelude: "none" },
  );
});

for (const codegenTier of ["optimized", "development"] as const) {
  Deno.test(`sequence carriers preserve Unit empty nested references and canceled owners (${codegenTier})`, async () => {
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
      const result = await compiler.build({
        sources: {
          [entry]: `
type Units = exists [a] => (Array a, List a, Array a -> U32, List a -> U32)
const units: U32 -> Units = func count => return pack [Unit] (@array.fill count (), @list.fill count (), func values => return @array.length values, func values => return @list.length values) as Units
entry const count = func (count: U32) => return unpack (units count) as [a] body in @u32.add ((@product.get body 2) (@product.get body 0)) ((@product.get body 3) (@product.get body 1))
type Nested = exists [a] => (Array (List a), Array (List a) -> U32)
const nested: U32 -> Nested = func value => return pack [Array U32] (@array.fill 2 (@list.fill 3 #[value]), func rows => return @array.get (@array.get (@array.from_list (@array.get rows 1)) 2) 0) as Nested
const read: Nested -> U32 = func item => return unpack item as [a] body in (@product.get body 1) (@product.get body 0)
entry const answer = func (value: U32) => return read (nested value)
entry const snapshot = func (value: U32) => return #[read (nested value)]
type Chain a is data = $End | $Link (a, Chain a)
type Nominal = exists [a] => (Chain a, Chain a -> U32)
const nominal: U32 -> Nominal = func value => return pack [Array U32] (if @u32.eq value 0 then $End else $Link (#[value], $Link (#[13], $End)), func chain => return case chain of
  $End => 0
  $Link (head, tail) => @array.get head 0
) as Nominal
entry const tagged = func (value: U32) => return unpack (nominal value) as [a] body in (@product.get body 1) (@product.get body 0)
opaque type Box a = a
type Opaque = exists [a] => (Box a, Box a -> U32)
const opaque: U32 -> Opaque = func value => return pack [Array U32] ($Box (@array.fill 3 value), func box => return case box of
  $Box inner => @array.get inner 2
) as Opaque
entry const boxed = func (value: U32) => return unpack (opaque value) as [a] body in (@product.get body 1) (@product.get body 0)
type UnitBox = exists [a] => (Box a, Box a -> U32)
const unit_box: Unit -> UnitBox = func () => return pack [Unit] ($Box (), func box => return case box of
  $Box inner => 42
) as UnitBox
entry const unit_boxed = func () => return unpack (unit_box ()) as [a] body in (@product.get body 1) (@product.get body 0)
type Stop is effect = { check: U32 -> U32 }
const stop = func computation => return do:
  for request in @requests computation:
    case request of
      effect Stop.check value =>
        break value
      complete value =>
        break value
entry const canceled = func (value: U32) => return stop (@computation (func () => return do:
  let item = nested value
  use Stop.check (read item)
  break @panic "carrier computation continued after cancellation"
))
type Empty = exists [a] => (Array a, Array a -> U32)
const empty: U32 -> Empty = func ignored => return pack [Unit] (@array.fill 0 (), func values => return do:
  let first = @array.get values 0
  break 42
) as Empty
entry const trapped = func (value: U32) => return unpack (empty value) as [a] body in (@product.get body 1) (@product.get body 0)
`,
        },
      });
      assert(result.success, JSON.stringify(result));
      const module = new WebAssembly.Module(result.bytes);
      assert.deepEqual([
        ...new Uint8Array(
          WebAssembly.Module.customSections(module, "blot:ownership")[0],
        ),
      ], [2, 2, 0]);
      const guest = await instantiateGuest(module);
      try {
        for (const count of [0, 1, 17, 513]) {
          equal(guest.call("count", count), count * 2);
        }
        equal(guest.call("unit_boxed", null), 42);
        for (const value of [0, 42, 7, 42]) {
          equal(guest.call("tagged", value), value);
          equal(guest.call("boxed", value), value);
          equal(guest.call("answer", value), value);
          equal(guest.call("canceled", value), value);
          assert.throws(() => guest.call("trapped", value));
          equal(guest.call("answer", value), value);
        }
        assert.deepEqual(guest.call("snapshot", 42), Uint32Array.of(42));
        assert(guest.memoryBytes() > 0);
        let warmBytes = 0;
        for (let index = 0; index < 32; index++) {
          equal(guest.call("answer", 42), 42);
          equal(guest.call("canceled", 42), 42);
          if (index === 7) warmBytes = guest.memoryBytes();
          if (index > 7) equal(guest.memoryBytes(), warmBytes);
        }
      } finally {
        guest.dispose();
      }
      const raw = new WebAssembly.Instance(module).exports;
      for (let index = 0; index < 16; index++) {
        equal((raw.canceled as CallableFunction)(index), index);
        equal(Number((raw["blot:rc_roots"] as WebAssembly.Global).value), 0);
        equal(Number((raw["blot:rc_leases"] as WebAssembly.Global).value), 0);
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
