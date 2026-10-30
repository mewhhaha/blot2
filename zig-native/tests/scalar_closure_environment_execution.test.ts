import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const source = `
entry const snapshots = func (seed: U32) => return do:
  let value = seed
  let callback = func (index: U32) => return do:
    let total = value
    for i in 0..index:
      total := @u32.add self i
    break total
  value := @u32.add self 1
  let other = func (index: U32) => return @u32.add value index
  let saved = #[callback, other]
  let nested = func () => return (saved[0]) 3
  for i in 0..64:
    let pressure = @array.fill 8192 i
    if @u32.eq (@array.get pressure 8191) i:
      let checked = i
    else:
      @panic "pressure"
  break #[nested (), (saved[1]) 3, value]
const bounce = func action => return @computation action
const completed = func computation => return do:
  for request in @requests computation:
    case request of
      complete value =>
        break value
entry const factory = func (seed: U32) => return completed (bounce (func () => return @u32.add seed 1))
entry const borrowed = func (seed: U32) => return do:
  let values = #[seed, 8192]
  let callback = func index => return @array.get values index
  break callback 0
entry const floating = func (seed: F32) => return do:
  let callback = func value => return @f32.add seed value
  let saved = #[callback]
  break (saved[0]) 1.0
entry const task = func (seed: U32) => return @task.scope (func group => return @task.join (@task.spawn group (func () => return seed)))
`;
Deno.test("scalar closure words preserve pointer-looking snapshots nested captures factories and task moves", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-scalar-environment-",
  });
  const entry = `${directory}/main.blot`;
  try {
    for (const codegenTier of ["optimized", "development"] as const) {
      const compiler = await createZigProjectCompiler({
        executable: Deno.args[0],
        entry,
        prelude: null,
        cacheDirectory: false,
        codegenTier,
      });
      try {
        const result = await compiler.build({ sources: { [entry]: source } });
        assert(result.success, JSON.stringify(result));
        const checkpoint = await compiler.exportCheckpoint();
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(result.bytes, { asynchronous });
          const invoke = async (name: string, value: unknown) => {
            if (asynchronous) return await guest.callAsync(name, value);
            return guest.call(name, value);
          };
          try {
            for (const seed of [0, 41, 8192, 65536, 131072, 0xfffffffc]) {
              assert.deepEqual(
                await invoke("snapshots", seed),
                Uint32Array.of(seed + 3, seed + 4, seed + 1),
              );
              assert.equal(await invoke("borrowed", seed), seed);
              assert.equal(await invoke("task", seed), seed);
            }
            assert.equal(await invoke("floating", 41.5), 42.5);
            assert.equal(await invoke("factory", 41), 42);
            const warm = guest.memoryBytes();
            for (let repeat = 0; repeat < 8; repeat++) {
              assert.deepEqual(
                await invoke("snapshots", 8192),
                Uint32Array.of(8195, 8196, 8193),
              );
            }
            assert.equal(guest.memoryBytes(), warm);
          } finally {
            guest.dispose();
          }
        }
        const retained = await compiler.build({ sources: { [entry]: source } });
        assert(retained.success);
        assert.deepEqual(retained.bytes, result.bytes);
        const restored = await createZigProjectCompiler({
          executable: Deno.args[0],
          entry,
          prelude: null,
          cacheDirectory: false,
          codegenTier,
          checkpoint,
        });
        try {
          const restarted = await restored.build({
            sources: { [entry]: source },
          });
          assert(restarted.success);
          assert.deepEqual(restarted.bytes, result.bytes);
        } finally {
          await restored.close();
        }
      } finally {
        await compiler.close();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
