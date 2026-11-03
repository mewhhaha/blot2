import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
const source = `entry const lanes = func (input: U32): Array U32 => return do:
  let marker: Array U32 = #[input]
  let row = {first: input, second: @u32.add input 1, steady: @u32.add input 9}
  for index in 0 .. 4:
    row.first := @u32.add self 1
    if @u32.eq index 1:
      continue
    row.second := @u32.add self 2
    if @u32.eq index 2:
      break
  return #[row.first, row.second, row.steady, marker[0]]
entry const changed = func (input: U32): Array U32 => return do:
  let marker: Array U32 = #[input]
  let row = {first: input, second: @u32.add input 1, steady: @u32.add input 9}
  for index in 0 .. 4:
    row.first := @u32.add self 1
    if @u32.eq index 1:
      row.steady := @u32.add self 7
      continue
  return #[row.first, row.second, row.steady, marker[0]]
entry const zero = func (input: U32): Array U32 => return do:
  let marker: Array U32 = #[input]
  let row = {first: input, second: @u32.add input 1, steady: @u32.add input 9}
  for index in 0 .. 0:
    row.first := @u32.add self 1
  return #[row.first, row.second, row.steady, marker[0]]
entry const swaps = func (input: U32): Array U32 => return do:
  let marker: Array U32 = #[input]
  let row = {first: input, second: @u32.add input 1, steady: @u32.add input 9}
  for index in 0 .. 3:
    row := @record.merge self {first: self.second, second: self.first}
    if @u32.eq index 1:
      continue
  return #[row.first, row.second, row.steady, marker[0]]
entry const nested = func (input: U32): Array U32 => return do:
  let marker: Array U32 = #[input]
  let row = {first: input, second: @u32.add input 1, steady: @u32.add input 9}
  for index in 0 .. 3:
    for inner in 0 .. 3:
      row.first := @u32.add self 1
      if @u32.eq inner 1:
        break
  return #[row.first, row.second, row.steady, marker[0]]
entry const breakchange = func (input: U32): Array U32 => return do:
  let marker: Array U32 = #[input]
  let row = {first: input, second: @u32.add input 1, steady: @u32.add input 9}
  for index in 0 .. 4:
    row.first := @u32.add self 1
    if @u32.eq index 1:
      row.steady := @u32.add self 7
      break
  return #[row.first, row.second, row.steady, marker[0]]
`;
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`flat loop lanes preserve zero iterations swaps and all exits (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-loop-lanes-" });
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
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(built.bytes, { asynchronous });
        try {
          for (const input of [0, 1, 17, 0xffff_ffff, 0]) {
            const expected: Record<string, number[]> = {
              lanes: [input + 3, input + 5, input + 9, input],
              changed: [input + 4, input + 1, input + 16, input],
              zero: [input, input + 1, input + 9, input],
              swaps: [input + 1, input, input + 9, input],
              nested: [input + 6, input + 1, input + 9, input],
              breakchange: [input + 2, input + 1, input + 16, input],
            };
            for (const [name, words] of Object.entries(expected)) {
              let actual: unknown;
              if (asynchronous) actual = await guest.callAsync(name, input);
              else actual = guest.call(name, input);
              assert.deepEqual(
                actual,
                new Uint32Array(words),
                `${name} input ${input}`,
              );
            }
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
