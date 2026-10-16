import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
const executable = Deno.args[0] ?? new URL("../zig-out/bin/blotc", import.meta.url);
const source = `
import * as iter from "std/iter"
const skip = fn count => fn cursor => do:
  for index in 0..count:
    cursor := @cursor.advance self
  return cursor
entry const scalar = fn (seed: U32) => do:
  let values = @list.generate 800 (fn index => index + seed)
  let left = values.iter
  let right = skip 243 values.iter
  values := @list.prepend self 9000
  values := @list.append self 9001
  let changed = Array.from_list values
  return #[@cursor.value left, @cursor.value right, @cursor.value (@cursor.advance right), changed[0], values.length]
entry const references = fn (seed: U32) => do:
  let values = @list.generate 800 (fn index => #[index, seed])
  let left = values.iter
  let right = skip 243 values.iter
  values := @list.prepend self #[9000, seed + 1]
  values := @list.append self #[9001, seed + 2]
  let changed = Array.from_list values
  for index in 0..128:
    let pressure = @array.fill 8192 index
    if pressure[8191] != index:
      @panic "snapshot pressure"
  return #[(@cursor.value left)[0], (@cursor.value right)[0], (@cursor.value (@cursor.advance right))[0], changed[0][0], values.length]
entry const windows = fn (count: U32) => do:
  let stream = iter.windows 3 (iter.range 0 count)
  let #Some (first, next) = stream.next else:
    return 0
  let saved = first.iter
  let #Some (second, _) = next.next else:
    return 0
  return @cursor.value saved + iter.fold_left add 0 first + iter.fold_left add 0 second
entry const constant = fn () => @cursor.value [40, 41, 42].iter
`;
Deno.test("List cursor snapshots defer copying across writers forks references windows and checkpoints", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  try {
    for (const codegenTier of ["optimized", "development"] as const) {
      const options = { executable, entry, codegenTier, cacheDirectory: false as const, prelude: new URL("../../std/prelude.blot", import.meta.url), stdRoot: new URL("../../std/", import.meta.url) };
      const compiler = await createZigProjectCompiler(options);
      try {
        const first = await compiler.build({sources: {[entry]: source}});
        assert(first.success, JSON.stringify(first));
        const checkpoint = await compiler.exportCheckpoint();
        const unchanged = await compiler.build({sources: {[entry]: source}});
        assert(unchanged.success, JSON.stringify(unchanged));
        assert.deepEqual(unchanged.bytes, first.bytes);
        const restored = await createZigProjectCompiler({...options, checkpoint});
        try {
          const replayed = await restored.build({sources: {[entry]: source}});
          assert(replayed.success, JSON.stringify(replayed));
          assert.deepEqual(replayed.bytes, first.bytes);
          for (const bytes of [first.bytes, replayed.bytes]) {
            const guest = await instantiateGuest(bytes);
            try {
              assert.deepEqual(guest.call("scalar", 7), Uint32Array.of(7, 250, 251, 9000, 802));
              assert.deepEqual(guest.call("references", 7), Uint32Array.of(0, 243, 244, 9000, 802));
              assert.equal(guest.call("windows", 4), 9);
              assert.equal(guest.call("constant", null), 40);
            } finally { guest.dispose(); }
          }
        } finally { await restored.dispose(); }
      } finally { await compiler.dispose(); }
    }
  } finally { await Deno.remove(directory, {recursive: true}); }
});
