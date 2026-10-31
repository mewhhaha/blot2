import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
import { compileAndRun, equal } from "./compile_helpers.ts";

Deno.test("static package phantom dictionaries keep exact methods and sealed closures", async () => {
  await compileAndRun(
    `type Tag a is contract = { const read: Unit -> U32 }
impl Number : Tag U32 = { const read = func unit => return 42 }
type Item = exists [a] where { Tag a } => Unit
type Sealed = exists [b] => Unit -> U32
const item: Item = pack [U32] () as Item
const read = func (value: Item) => return unpack value as [a] payload in Tag.read ()
const keep = func (value: Item) => return unpack value as [a] payload in pack [a] Tag.read as Sealed
const invoke = func (value: Sealed) => return unpack value as [b] callback in callback ()
entry const answer = func () => return @u32.add (read item) (invoke (keep item))
`,
    (guest) => equal(guest.call("answer", null), 84),
    { prelude: "none" },
  );
});
Deno.test("static package concrete scalars bridge stored method arguments", async () => {
  await compileAndRun(
    `type Render a is contract = { const show: a -> U32 }
impl Number : Render U32 = { const show = func value => return value }
type Item = exists [a] where { Render a } => a
const item: Item = pack [U32] 42 as Item
const read = func (value: Item) => return unpack value as [a] payload in Render.show payload
entry const answer = func () => return read item
`,
    (guest) => equal(guest.call("answer", null), 42),
    { prelude: "none" },
  );
});
Deno.test("static package products adapt callbacks and retain ordinary captures", async () => {
  await compileAndRun(
    `type Item = exists [a] => (a, a -> U32)
const offset: U32 = 7
const item: Item = pack [U32] (35, func value => return @u32.add value offset) as Item
const read = func (value: Item) => return unpack value as [a] payload in (@product.get payload 1) (@product.get payload 0)
entry const answer = func () => return read item
`,
    (guest) => equal(guest.call("answer", null), 42),
    { prelude: "none" },
  );
});

Deno.test("static package arrays and Lists retain each abstract element", async () => {
  await compileAndRun(
    `type Item = exists [a] => (Array a, List a, a -> U32)
const item: Item = pack [U32] (#[20, 22], [20, 22], func value => return value) as Item
const read = func (value: Item) => return unpack value as [a] payload in @u32.add ((@product.get payload 2) (@array.get (@product.get payload 0) 0)) ((@product.get payload 2) (@array.get (@array.from_list (@product.get payload 1)) 1))
entry const answer = func () => return read item
`,
    (guest) => equal(guest.call("answer", null), 42),
    { prelude: "none" },
  );
});
Deno.test("static package Float witnesses keep bits across callable adapters", async () => {
  await compileAndRun(
    `type Item = exists [a] => (a, a -> F32)
const item: Item = pack [F32] (41.5, func value => return @f32.add value 0.5) as Item
const read = func (value: Item) => return unpack value as [a] payload in (@product.get payload 1) (@product.get payload 0)
entry const answer = func () => return read item
`,
    (guest) => equal(guest.call("answer", null), 42),
    { prelude: "none" },
  );
});

Deno.test("static package source archives checkpoints and same-layout literal edits preserve owners", async () => {
  const executable = Deno.args[0] ??
    new URL("../zig-out/bin/blotc", import.meta.url);
  const directory = await Deno.makeTempDir({ prefix: "blot-static-package-" });
  const entry = `${directory}/main.blot`,
    library = `${directory}/library.blot`,
    dependencies = `${directory}/library.blotdep`;
  const producer = `type Render a is contract = { const show: a -> U32 }
impl Number : Render U32 = { const show = func value => return value }
type Item = exists [a] where { Render a } => (Array a, a)
const item: Item = pack [U32] (#[20, 22], 42) as Item
const read = func (value: Item) => return unpack value as [a] payload in Render.show (@product.get payload 1)
const answer = func () => return read item
`;
  const consumer = `import {answer} from "./library"
entry const run = func () => return answer ()
entry const snapshot = func (value: U32) => return #[value]
`;
  async function execute(bytes: Uint8Array<ArrayBuffer>, expected: number) {
    for (const asynchronous of [false, true]) {
      const guest = await instantiateGuest(bytes, { asynchronous });
      try {
        for (let i = 0; i < 64; i++) {
          let result;
          if (asynchronous) result = await guest.callAsync("run", null);
          else result = guest.call("run", null);
          assert.equal(result, expected);
        }
        const warmed = guest.memoryBytes();
        for (let i = 0; i < 64; i++) {
          if (asynchronous) {
            assert.equal(await guest.callAsync("run", null), expected);
          } else assert.equal(guest.call("run", null), expected);
        }
        assert.equal(guest.memoryBytes(), warmed);
      } finally {
        guest.dispose();
      }
    }
    const raw = new WebAssembly.Instance(new WebAssembly.Module(bytes)).exports;
    const enter = raw["blot:ownership_enter"] as CallableFunction,
      leave = raw["blot:ownership_leave"] as CallableFunction;
    for (let i = 0; i < 32; i++) {
      enter();
      assert.equal((raw.run as CallableFunction)(), expected);
      leave(0);
      for (const name of ["roots", "leases"]) {
        assert.equal(
          Number((raw[`blot:rc_${name}`] as WebAssembly.Global).value),
          0,
        );
      }
    }
  }
  try {
    await Deno.writeTextFile(entry, consumer);
    await Deno.writeTextFile(library, producer);
    const packed = await new Deno.Command(executable, {
      args: ["dependencies", entry, dependencies, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert(
      packed.success,
      new TextDecoder().decode(packed.stdout) +
        new TextDecoder().decode(packed.stderr),
    );
    for (const codegenTier of ["development", "optimized"] as const) {
      const options = {
        executable,
        entry,
        prelude: null,
        cacheDirectory: false as const,
        codegenTier,
      };
      const source = await createZigProjectCompiler(options),
        archive = await createZigProjectCompiler({ ...options, dependencies });
      let checkpoint: Uint8Array<ArrayBuffer>,
        expected: Uint8Array<ArrayBuffer>;
      try {
        const live = await source.build(), frozen = await archive.build();
        assert(live.success, JSON.stringify(live));
        assert(frozen.success, JSON.stringify(frozen));
        assert.deepEqual(frozen.bytes, live.bytes);
        await execute(frozen.bytes, 42);
        expected = frozen.bytes;
        checkpoint = await archive.exportCheckpoint();
        const changed = producer.replace("], 42)", "], 43)");
        const edited = await source.build({ sources: { [library]: changed } });
        assert(edited.success, JSON.stringify(edited));
        await execute(edited.bytes, 43);
        const reverted = await source.build({
          sources: { [library]: producer },
        });
        assert(reverted.success, JSON.stringify(reverted));
        assert.deepEqual(reverted.bytes, expected);
      } finally {
        await source.dispose();
        await archive.dispose();
      }
      const restored = await createZigProjectCompiler({
        ...options,
        dependencies,
        checkpoint: checkpoint!,
      });
      try {
        const replayed = await restored.build();
        assert(replayed.success, JSON.stringify(replayed));
        assert.deepEqual(replayed.bytes, expected!);
        await execute(replayed.bytes, 42);
      } finally {
        await restored.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("static package nominal payloads retain constructor witnesses", async () => {
  await compileAndRun(
    `type Box a is data = $Box a
const unwrap = func ($Box value) => return value
type Item = exists [a] => (Box a, a -> U32)
const item: Item = pack [U32] ($Box 42, func value => return value) as Item
const read = func (value: Item) => return unpack value as [a] payload in (@product.get payload 1) (unwrap (@product.get payload 0))
entry const answer = func () => return read item
`,
    (guest) => equal(guest.call("answer", null), 42),
    { prelude: "none" },
  );
});
