import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const source = `
type Event is data = $Down U32 | $Move {x: F32, y: F32} | $None
const require = func (ok: Bool) => return if ok then () else @panic "invalid"
const decode = func (input: Array F32) => return func (start: U32) => return do:
  let tag = @f32.to_u32 input[start]
  return case tag of
    1 => do:
      use require (@f32.eq input[start + 1] 0.0)
      return $Down 7
    2 => do:
      use require (@f32.eq input[start + 1] 0.0)
      return $Move {x: 2.0, y: 3.0}
    _ => @panic "invalid"
entry const answer = func (tag: U32) => return do:
  let marker: ResizeArray U32 = #[0]
  let values: Array F32 = #[@u32.to_f32 (@u32.add tag marker[0]), 0.0]
  let event = decode values 0
  return case event of
    $Down code => code
    $Move {x, y} => @f32.to_u32 (@f32.add x y)
    $None => 0

entry const mixed = func (tag: U32) => return do:
  let rows: ResizeArray U32 = #[tag]
  return case rows[0] of
    0 => do:
      return 10
    _ => 20

`;
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`owned returns preserve completed and continuing match exits (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-owned-return-",
    });
    const entry = `${directory}/main.blot`;
    const stdRoot = new URL("../../std", import.meta.url).pathname;
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0],
      entry,
      stdRoot,
      prelude: `${stdRoot}/prelude.blot`,
      cacheDirectory: false,
      codegenTier,
    });
    try {
      const result = await compiler.build({ sources: { [entry]: source } });
      assert(result.success, JSON.stringify(result));
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(result.bytes, { asynchronous });
        try {
          for (
            const [name, input, expected] of [
              ["answer", 1, 7],
              ["answer", 2, 5],
              ["mixed", 0, 10],
              ["mixed", 1, 20],
            ] as const
          ) {
            const actual = asynchronous
              ? await guest.callAsync(name, input)
              : guest.call(name, input);
            assert.equal(actual, expected);
          }
          if (asynchronous) {
            await assert.rejects(() => guest.callAsync("answer", 0));
          } else assert.throws(() => guest.call("answer", 0));
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
