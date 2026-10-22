import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../compiler/guest.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;

for (const codegenTier of ["optimized", "development"] as const) {
  Deno.test(`unobserved generic identities preserve concrete aliases (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir();
    const entry = `${directory}/main.blot`;
    const compiler = await createZigProjectCompiler({
      executable,
      entry,
      prelude: null,
      codegenTier,
      cacheDirectory: false,
    });
    try {
      const source = `
type Choice [a, b] is data = #Left a | #Right b
const reconstruct = fn candidate => case candidate of
  #Left value => do:
    break #Left value
  #Right error => do:
    break #Right error
entry const phantom = fn (value: U32) => case reconstruct (#Left value) of
  #Left result => result
  #Right _ => 0
entry const changed = fn (value: U32) => do:
  let candidate = #Right #[value]
  let changed = case candidate of
    #Left missing => #Left missing
    #Right values => do:
      break #Right #[@u32.add values[0] 1]
  break case changed of
    #Left _ => 0
    #Right values => values[0]
entry const retagged = fn (value: U32) => do:
  let candidate = #Left value
  let changed = case candidate of
    #Left payload => do:
      break #Right payload
    #Right payload => #Right payload
  break case changed of
    #Left payload => payload
    #Right payload => @u32.add payload 100
const holder = fn () => #{ identity: fn x => x, unseen: fn x => x, g: 4 }
const forward = fn value => (holder ()).identity value
entry const unobserved = fn () => (holder ()).g
entry const integer = fn (value: U32) => forward value
entry const fraction = fn (value: F32) => forward value
entry const snapshot = fn (seed: U32) => forward (@array.fill 1024 seed)
entry const alias = fn (seed: U32) => do:
  let kept = #[seed]
  for index in 0 .. 64:
    let original = @array.fill 1024 (@u32.add seed index)
    let aliased = forward original
    kept := forward aliased
  let final = forward kept
  break @array.get final 1023
entry const captured = fn (seed: U32) => do:
  let original = @array.fill 1024 seed
  let alias = forward original
  let read = fn () => @array.get alias 1023
  break read ()
`;
      let original: Uint8Array<ArrayBuffer> | undefined;
      for (let revision = 0; revision < 2; revision++) {
        const result = await compiler.build({ sources: { [entry]: source } });
        assert(result.success, JSON.stringify(result));
        if (original) assert.deepEqual(result.bytes, original);
        original = result.bytes;
        const module = new WebAssembly.Module(result.bytes);
        assert.deepEqual(
          [
            ...new Uint8Array(
              WebAssembly.Module.customSections(module, "blot:ownership")[0],
            ),
          ],
          [2, 2, 0],
        );
        const guest = await instantiateGuest(result.bytes);
        try {
          assert.equal(guest.call("unobserved", null), 4);
          assert.equal(guest.call("integer", 0xffffffff), 0xffffffff);
          assert.equal(guest.call("fraction", 2.5), 2.5);
          assert.equal(guest.call("phantom", 41), 41);
          assert.equal(guest.call("changed", 41), 42);
          assert.equal(guest.call("retagged", 41), 141);
          assert.deepEqual(
            guest.call("snapshot", 41),
            new Uint32Array(1024).fill(41),
          );
          for (const seed of [0, 41, 8192, 41]) {
            assert.equal(guest.call("alias", seed), seed + 63);
            assert.equal(guest.call("captured", seed), seed);
          }
        } finally {
          guest.dispose();
        }
        const raw = new WebAssembly.Instance(module).exports;
        const memory = raw["blot:memory"] as WebAssembly.Memory;
        const alias = raw.alias as (seed: number) => number;
        assert.equal(alias(41), 104);
        const warmBytes = memory.buffer.byteLength;
        for (let index = 0; index < 16; index++) {
          assert.equal(alias(index), index + 63);
          assert.equal((raw["blot:rc_roots"] as WebAssembly.Global).value, 0);
          assert.equal((raw["blot:rc_leases"] as WebAssembly.Global).value, 0);
        }
        assert.equal(memory.buffer.byteLength, warmBytes);
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
