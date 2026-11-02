import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const plain = `type Pair is data = $Pair {left: U32, right: U32}
const adjust = func (value: U32): U32 => return do:
  let original = value
  value := @u32.add value 1
  return @u32.add original value
const exchange = func (pair: Pair): U32 => return do:
  let saved = func () => return pair.left
  for 0 .. 3:
    let old = pair.left
    pair.left := pair.right
    pair.right := old
  return @u32.add (saved ()) (@u32.add (@u32.mul pair.left 10) pair.right)
entry const answer = func (input: U32): Array U32 => return do:
  let owned: ResizeArray U32 = #[input]
  @storage.push owned input
  let value = owned[1]
  return #[adjust value, exchange ($Pair {left: value, right: @u32.add value 1})]
`;
const addressed =
  `const observe = func (original: U32) -> (reference: Ref U32): U32 => return do:
  @storage.write reference 42
  return original
entry const answer = func (input: U32): Array U32 => return do:
  let value = input
  let original = observe value (&value)
  return #[original, value]
`;

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`parameter copies preserve rebinding captures carries and address fallback (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-parameter-copy-",
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
      // Retained edits must recompute the inventory fact in both directions.
      const edited = plain.replace("@u32.add value 1", "@u32.add value 2");
      for (const source of [plain, addressed, edited]) {
        const built = await compiler.build({
          sources: { [entry]: source },
          signal: AbortSignal.timeout(5_000),
        });
        assert(built.success, JSON.stringify(built));
        const work = built.stats.workCounters as Record<string, number>;
        if (source !== addressed) {
          assert(work.scoped_parameter_words_shared > 0);
        } else assert.equal(work.scoped_parameter_words_shared, 0);
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(built.bytes, { asynchronous });
          try {
            for (const input of [0, 1, 17, 0xfffffffd, 0]) {
              let expected = [input, 42];
              if (source !== addressed) {
                let extra = 1;
                if (source === edited) extra = 2;
                expected = [input * 2 + extra, input * 12 + 10];
              }
              let actual;
              if (asynchronous) actual = await guest.callAsync("answer", input);
              else actual = guest.call("answer", input);
              assert.deepEqual(actual, new Uint32Array(expected));
            }
          } finally {
            guest.dispose();
          }
        }
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
