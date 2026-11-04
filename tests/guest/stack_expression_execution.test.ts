import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const source = `entry const ordered = func (input: U32): Array U32 => return do:
  let marker: Array U32 = #[input]
  let before = marker[0]
  let reused = @u32.sub input 7
  marker[0] := @u32.add self 5
  let after = marker[0]
  let mixed = @u32.sub (@u32.mul reused 3) (@u32.bit_xor after 12345)
  let chosen = if @u32.eq input 0 then reused else mixed
  let current = input
  let saved = @u32.add current 9
  current := @u32.add self 1
  return #[before, after, reused, @u32.add reused mixed, chosen, saved, current]
entry const floating = func (input: F32): F32 => return do:
  let marker: Array U32 = #[0]
  marker[0] := 1
  let value = @f32.mul input 1.0
  return @f32.div value 1.0
`;
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`stack expressions preserve repeated values reads writes branches and F32 (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-stack-expressions-",
    });
    const entry = `${directory}/main.blot`;
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0],
      entry,
      prelude: null,
      cacheDirectory: false,
      codegenTier,
    });
    try {
      const built = await compiler.build({
        sources: { [entry]: source },
        signal: AbortSignal.timeout(5000),
      });
      assert(built.success, JSON.stringify(built));
      assert(WebAssembly.validate(built.bytes));
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(built.bytes, { asynchronous });
        try {
          for (const input of [0, 1, 17, 0xffff_ffff, 0]) {
            const reused = (input - 7) >>> 0;
            const after = (input + 5) >>> 0;
            const mixed = (Math.imul(reused, 3) - (after ^ 12345)) >>> 0;
            let actual: unknown;
            if (asynchronous) actual = await guest.callAsync("ordered", input);
            else actual = guest.call("ordered", input);
            let chosen = mixed;
            if (input === 0) chosen = reused;
            assert.deepEqual(
              actual,
              new Uint32Array([
                input,
                after,
                reused,
                reused + mixed,
                chosen,
                input + 9,
                input + 1,
              ]),
            );
          }
          for (const input of [-0, 0, 1.25, -7.5, NaN, Infinity, -Infinity]) {
            let actual: unknown;
            if (asynchronous) actual = await guest.callAsync("floating", input);
            else actual = guest.call("floating", input);
            assert(
              Object.is(actual, input),
              `${String(input)}: ${String(actual)}`,
            );
          }
        } finally {
          guest.dispose();
        }
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
