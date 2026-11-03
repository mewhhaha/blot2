import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const source = `entry const transport = func (input: U32): Array U32 => return do:
  let rows: GrowArray U32 = #[input]
  let first = input
  let second = @u32.add input 10
  for index in 0 .. 4:
    let prior = first
    first := second
    second := prior
    if @u32.eq index 1:
      continue
    for inner in 0 .. 2:
      rows[0] := @u32.add self first
      if @u32.eq inner 0:
        break
  return #[rows[0], first, second, @u32.add 19 (@u32.add first second)]
entry const typed = func (input: F32): F32 => return do:
  let marker: GrowArray U32 = #[0]
  let first = input
  let second = -0.0
  for index in 0 .. 2:
    let prior = first
    first := second
    second := prior
  marker[0] := 1
  return first
`;

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`scoped transport preserves nested swaps stack operands and F32 bits (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-transport-" });
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
        signal: AbortSignal.timeout(5_000),
      });
      assert(built.success, JSON.stringify(built));
      assert(WebAssembly.validate(built.bytes));
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(built.bytes, { asynchronous });
        try {
          for (const input of [0, 1, 17, 0xffff_ffff, 0]) {
            let actual: unknown;
            if (asynchronous) actual = await guest.callAsync("transport", input);
            else actual = guest.call("transport", input);
            assert.deepEqual(
              actual,
              new Uint32Array([
                4 * input + 20,
                input,
                input + 10,
                19 + input + input + 10,
              ]),
            );
          }
          for (const input of [-0, 0, 1.25, -7.5, -0]) {
            let actual: unknown;
            if (asynchronous) actual = await guest.callAsync("typed", input);
            else actual = guest.call("typed", input);
            assert(Object.is(actual, input), `${input}: ${String(actual)}`);
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
