import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`literal record projections preserve imported names F32 bits source traps and retained edits (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-literal-projection-",
    });
    const entry = `${directory}/main.blot`;
    const producer = `${directory}/palette.blot`;
    const other = `${directory}/other.blot`;
    const stdRoot = new URL("../../std", import.meta.url).pathname;
    const options = {
      executable: Deno.args[0],
      entry,
      stdRoot,
      prelude: `${stdRoot}/prelude.blot`,
      cacheDirectory: false as const,
      codegenTier,
    };
    const caller = `import * as left from "./palette"
import * as right from "./other"
type Noise is data = $Noise {m: Bool, unrelated: U32, z: F32, a: U32}
entry const answer = func (input: U32): Array U32 => return do:
  let marker: GrowArray U32 = #[input]
  return #[left.palette.z, left.palette.m, right.palette.z, right.palette.m, marker[0]]
entry const floating = func (): Array F32 => return do:
  let marker: GrowArray F32 = #[0.0]
  return #[left.palette.a, right.palette.a, marker[0]]
entry const trapped = func (): U32 => return do:
  let marker: GrowArray U32 = #[0]
  return left.poison.z
`;
    const right = `type Palette is data = $Palette {a: F32, m: U32, z: U32}
const palette: Palette = $Palette {z: 17, a: 1.5, m: 23}
`;
    const compiler = await createZigProjectCompiler(options);
    try {
      let latest: Uint8Array<ArrayBuffer> | undefined;
      let sources: Record<string, string> = {};
      for (const [word, floating] of [[11, 0.1], [29, 1.5], [43, 2.5]]) {
        const left = `type Palette is data = $Palette {z: U32, a: F32, m: U32}
const palette: Palette = $Palette {m: 7, z: ${word}, a: ${floating}}
const poison: Palette = $Palette {z: 7, a: 1.5, m: @u32.div 19 0}
`;
        sources = { [entry]: caller, [producer]: left, [other]: right };
        const result = await compiler.build({ sources });
        assert(result.success, JSON.stringify(result));
        const counters = result.stats.workCounters as Record<string, number>;
        assert(counters.scoped_literal_record_projections > 0);
        latest = result.bytes;
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(result.bytes, { asynchronous });
          try {
            const call = async (name: string, input: unknown) => {
              if (asynchronous) return await guest.callAsync(name, input);
              return guest.call(name, input);
            };
            assert.deepEqual(
              await call("answer", 99),
              new Uint32Array([word, 7, 17, 23, 99]),
            );
            const actual = await call("floating", null) as Float32Array;
            const expected = new Float32Array([floating, 1.5, 0]);
            assert.deepEqual(
              new Uint32Array(actual.buffer, actual.byteOffset, actual.length),
              new Uint32Array(expected.buffer),
            );
            await assert.rejects(
              async () => await call("trapped", null),
              WebAssembly.RuntimeError,
            );
            assert.deepEqual(
              await call("answer", 3),
              new Uint32Array([word, 7, 17, 23, 3]),
            );
          } finally {
            guest.dispose();
          }
        }
      }
      const fresh = await createZigProjectCompiler(options);
      try {
        const result = await fresh.build({ sources });
        assert(result.success, JSON.stringify(result));
        assert.deepEqual(result.bytes, latest);
      } finally {
        await fresh.dispose();
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
