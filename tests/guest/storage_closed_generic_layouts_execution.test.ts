import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

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
const read_first = func (fallback: F32) -> (pool: ResizeArray (Envelope F32)): (F32, U32, F32) => return do:
  let first = read pool
  let box_val = unbox fallback first.box
  let $Pair (id, amount) = pair_or ($Pair (0, 0.0)) first.pair
  return (box_val, id, amount)
entry const answer = func (input: F32) => return do:
  let floats: ResizeArray (Envelope F32) = #[$Envelope {box: $Some ($Box {value: input}), pair: $Some ($Pair (7, input + 1.0))}]
  let integers: ResizeArray (Envelope U32) = #[$Envelope {box: $Some ($Box {value: 13}), pair: $Nothing}]
  let (first_box, first_id, first_amount) = read_first (-1.0) floats
  let second = read integers
  floats[0] := $Envelope {box: $Nothing, pair: $Some ($Pair (8, input + 10.0))}
  let (third_box, third_id, third_amount) = read_first (-5.0) floats
  return #[first_box, U32.to_f32 (unbox 0 second.box), third_box,
    U32.to_f32 first_id, first_amount, U32.to_f32 third_id, third_amount]
`;
Deno.test(`closed generic layout witnesses survive mixed caller contexts`, async () => {
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
