import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const source = `type Box a is data = $Box {value: a}
type Pair [a, b] is data = $Pair (a, b)
type Envelope a is data = $Envelope {box: Maybe (Box a), pair: Maybe (Pair [U32, a])}
const Box.item = func ($Box {value}) => return value
const read = func (pool: ResizeArray (Envelope a)) => return pool[0]
const unbox = func fallback -> maybe => return case maybe of
  $Some box => box.item
  $Nothing => fallback
const pair_or = func fallback -> maybe => return case maybe of
  $Some value => value
  $Nothing => fallback
entry const answer = func (input: F32) => return do:
  let floats: ResizeArray (Envelope F32) = #[$Envelope {box: $Some ($Box {value: input}), pair: $Some ($Pair (7, input + 1.0))}]
  let integers: ResizeArray (Envelope U32) = #[$Envelope {box: $Some ($Box {value: 13}), pair: $Nothing}]
  let first = read floats
  let second = read integers
  floats[0] := $Envelope {box: $Nothing, pair: $Some ($Pair (8, input + 10.0))}
  let third = read floats
  let $Pair (first_id, first_amount) = pair_or ($Pair (0, 0.0)) first.pair
  let $Pair (third_id, third_amount) = pair_or ($Pair (0, 0.0)) third.pair
  return #[unbox (-1.0) first.box, U32.to_f32 (unbox 0 second.box), unbox (-5.0) third.box,
    U32.to_f32 first_id, first_amount, U32.to_f32 third_id, third_amount]
`;
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`closed generic layout witnesses survive mixed caller contexts (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-closed-generics-",
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
          for (const input of [-0, 1.25, -10.5, 99]) {
            const value = asynchronous
              ? await guest.callAsync("answer", input)
              : guest.call("answer", input);
            assert.deepEqual(
              value,
              new Float32Array([input, 13, -5, 7, input + 1, 8, input + 10]),
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
