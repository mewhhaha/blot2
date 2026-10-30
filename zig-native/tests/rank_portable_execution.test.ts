import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../compiler/guest.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const producer = `const id: forall [a] => a -> a = func value => return value
const two: (forall [a] => a -> a) -> U32 -> (U32, F32) = func identity => return func value => return (identity value, identity (@u32.to_f32 value))
const array: (forall [a] => a -> a) -> Array U32 -> Array U32 = func identity => return func values => return identity values
const floating: (forall [a] => a -> a) -> Array F32 -> Array F32 = func identity => return func values => return identity values
const list: (forall [a] => a -> a) -> List U32 -> List U32 = func identity => return func values => return identity values
const floating_list: (forall [a] => a -> a) -> List F32 -> List F32 = func identity => return func values => return identity values
`;
const consumer =
  `import {id, two, array, floating, list, floating_list} from "./identity"
entry const whole = func (value: U32) => return @product.get (two id value) 0
entry const fraction = func (value: U32) => return @product.get (two (func item => return item) value) 1
entry const exact_array = func (values: Array F32) => return floating id values
entry const exact_list = func (values: Array F32) => return @array.from_list (floating_list id (@list.from_array values))
entry const kept = func (value: U32) => return do:
  let result = array id (@array.fill 256 value)
  let pressure = @array.fill 8192 99
  break if @u32.eq pressure[0] 99 then result else @panic "pressure"
entry const floating_kept = func (value: U32) => return do:
  let identity: forall [a] => a -> a = id
  let result = floating identity (@array.fill 256 (@f32.add (@u32.to_f32 value) 0.25))
  let pressure = @array.fill 8192 99
  break if @u32.eq pressure[0] 99 then result else @panic "pressure"
entry const listed_kept = func (value: U32) => return do:
  let result = list id (@list.from_array (@array.fill 256 value))
  let pressure = @array.fill 8192 99
  break if @u32.eq pressure[0] 99 then @array.from_list result else @panic "pressure"
entry const floating_list_kept = func (value: U32) => return do:
  let result = floating_list (func item => return item) (@list.from_array (@array.fill 256 (@f32.add (@u32.to_f32 value) 0.25)))
  let pressure = @array.fill 8192 99
  break if @u32.eq pressure[0] 99 then @array.from_list result else @panic "pressure"
entry const anonymous = func (value: U32) => return array (func item => return item) #[value, 42]
`;

async function run(bytes: Uint8Array<ArrayBuffer>) {
  const module = new WebAssembly.Module(bytes);
  assert.deepEqual([
    ...new Uint8Array(
      WebAssembly.Module.customSections(module, "blot:ownership")[0],
    ),
  ], [2, 2, 0]);
  assert.deepEqual(WebAssembly.Module.imports(module), []);
  const guest = await instantiateGuest(module);
  const paths = [
    {
      name: "kept",
      expected: (value: number) => new Uint32Array(256).fill(value),
      view: Uint32Array,
    },
    {
      name: "floating_kept",
      expected: (value: number) => new Float32Array(256).fill(value + 0.25),
      view: Float32Array,
    },
    {
      name: "listed_kept",
      expected: (value: number) => new Uint32Array(256).fill(value),
      view: Uint32Array,
    },
    {
      name: "floating_list_kept",
      expected: (value: number) => new Float32Array(256).fill(value + 0.25),
      view: Float32Array,
    },
  ];
  const returned = [];
  try {
    const bits = Float32Array.of(0, -0, -2.5, Infinity, -Infinity, NaN);
    assert.deepEqual(guest.call("exact_array", bits), bits);
    assert.deepEqual(guest.call("exact_list", bits), bits);
    for (const value of [0, 13, 42, 1024]) {
      assert.equal(guest.call("whole", value), value);
      assert.equal(guest.call("fraction", value), value);
      assert.deepEqual(
        guest.call("anonymous", value),
        Uint32Array.of(value, 42),
      );
    }
    for (const path of paths) {
      const value = guest.call(path.name, 73);
      assert.deepEqual(value, path.expected(73));
      returned.push(value);
    }
    const warmed = guest.memoryBytes();
    for (let value = 0; value < 64; value++) {
      for (const path of paths) {
        assert.deepEqual(guest.call(path.name, value), path.expected(value));
      }
    }
    assert.equal(guest.memoryBytes(), warmed);
  } finally {
    guest.dispose();
  }
  for (const [index, path] of paths.entries()) {
    assert.deepEqual(returned[index], path.expected(73));
  }
  const raw = new WebAssembly.Instance(module).exports;
  const memory = raw["blot:memory"] as WebAssembly.Memory;
  const enter = raw["blot:ownership_enter"] as CallableFunction;
  const leave = raw["blot:ownership_leave"] as CallableFunction;
  const count = (name: string) =>
    Number((raw[`blot:rc_${name}`] as WebAssembly.Global).value);
  let warmed = 0;
  for (let value = 0; value < 64; value++) {
    for (const path of paths) {
      enter();
      const pointer = (raw[path.name] as CallableFunction)(value);
      assert.deepEqual(
        new path.view(memory.buffer as ArrayBuffer, pointer + 4, 256),
        path.expected(value),
      );
      if (warmed !== 0) assert.equal(memory.buffer.byteLength, warmed);
      warmed = memory.buffer.byteLength;
      leave(0);
      assert.equal(count("roots"), 0);
      assert.equal(count("leases"), 0);
      const hostRefs = raw["blot:rc_host_refs"] as
        | WebAssembly.Global
        | undefined;
      assert.equal(hostRefs?.value ?? 0, 0);
    }
  }
  leave(2);
}

Deno.test("portable rank identities execute source archive checkpoint restart and failed edit recovery", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-rank-portable-" });
  const entry = `${directory}/main.blot`;
  const identity = `${directory}/identity.blot`;
  const dependencies = `${directory}/identity.blotdep`;
  try {
    await Deno.writeTextFile(entry, consumer);
    await Deno.writeTextFile(identity, producer);
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
      const source = await createZigProjectCompiler(options);
      const archive = await createZigProjectCompiler({
        ...options,
        dependencies,
      });
      let checkpoint: Uint8Array<ArrayBuffer>;
      let expected: Uint8Array<ArrayBuffer>;
      try {
        const actual = await source.build();
        const frozen = await archive.build();
        assert(actual.success, JSON.stringify(actual));
        assert(frozen.success, JSON.stringify(frozen));
        assert(frozen.stats.cachedModules > 0);
        assert.deepEqual(frozen.bytes, actual.bytes);
        await run(actual.bytes);
        await run(frozen.bytes);
        expected = actual.bytes;
        checkpoint = await archive.exportCheckpoint();
        for (
          const failed of [
            consumer.replace("func item => return item", "func item => return 42"),
            consumer.replace(
              "two id value",
              "two (func (item: U32) => return item) value",
            ),
          ]
        ) {
          const live = await source.build({ sources: { [entry]: failed } });
          const frozenFailure = await archive.build({
            sources: { [entry]: failed },
          });
          assert(!live.success && !frozenFailure.success);
          assert.deepEqual(frozenFailure.diagnostics, live.diagnostics);
          assert.deepEqual(await archive.exportCheckpoint(), checkpoint);
        }
        const recovered = await archive.build({
          sources: { [entry]: consumer },
        });
        assert(recovered.success, JSON.stringify(recovered));
        assert.deepEqual(recovered.bytes, expected);
      } finally {
        await source.dispose();
        await archive.dispose();
      }
      await run(expected!);
      const restored = await createZigProjectCompiler({
        ...options,
        dependencies,
        checkpoint: checkpoint!,
      });
      try {
        const replayed = await restored.build();
        assert(replayed.success, JSON.stringify(replayed));
        assert.deepEqual(replayed.bytes, expected!);
        assert(
          (replayed.stats.runtimeOptimization as Record<string, number>)
            .reused >
            0,
          JSON.stringify(replayed.stats.runtimeOptimization),
        );
        await run(replayed.bytes);
      } finally {
        await restored.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
