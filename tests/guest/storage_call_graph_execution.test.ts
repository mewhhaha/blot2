import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";
import {
  storageCallExpected,
  storageCallSource,
} from "../../benchmarks/tools/storage_calls.ts";

const witnesses = `const view_leaf = func (rows: &[U32]): U32 => return rows[0]
const view_twice = func (rows: &[U32]): U32 => return @u32.add (view_leaf rows) (view_leaf rows)
const ref_leaf = func (value: Ref U32): U32 => return @storage.load value
const ref_twice = func (value: Ref U32): U32 => return @u32.add (ref_leaf value) (ref_leaf value)
const link_leaf = func (value: Link U32): U32 => return @storage.load value
const link_twice = func (value: Link U32): U32 => return @u32.add (link_leaf value) (link_leaf value)
const read_link = func (rows: Array U32) -> (index: U32): U32 => return link_twice (@storage.link rows index)
const row_value = func (rows: Array U32): U32 => return rows[1]
const mutate_pair = func (left: own Array U32) -> (right: own Array U32) -> (amount: U32): (Array U32, Array U32) => return do:
  left[1] := @u32.add (row_value left) amount
  right[1] := @u32.add (row_value right) (@u32.add amount 1)
  return (left, right)
const invoke = func (callback: own Array U32 -> U32 -> Array U32) -> (rows: own Array U32) -> (amount: U32): Array U32 => return do:
  rows := callback rows amount
  return callback rows (@u32.add amount 1)
const invoke_twice = func (callback: own Array U32 -> U32 -> Array U32) -> (rows: own Array U32) -> (amount: U32): Array U32 => return do:
  rows := invoke callback rows amount
  return invoke callback rows (@u32.add amount 2)
const add_second = func (rows: own Array U32) -> (amount: U32): Array U32 => return do:
  rows[1] := @u32.add rows[1] amount
  return rows
io const answer = func (input: U32) => return do:
  let first: Array U32 = #[input, @u32.add input 10, @u32.add input 20]
  let second: Array U32 = #[@u32.add input 100, @u32.add input 110, @u32.add input 120]
  let links: Array U32 = #[@u32.add input 200, @u32.add input 210]
  let before = @u32.add (view_twice (&first[1..3])) (@u32.add (ref_twice (@storage.at second 1)) (read_link links 0))
  first[1] := @u32.add first[1] (@u32.add (@u32.mul 2 input) 1)
  let (first, second) = mutate_pair first second 2
  let first = invoke_twice add_second first 1
  let second = invoke_twice add_second second 11
  let total: U32 = 0
  for index in 0 .. 3:
    let (next_first, next_second) = mutate_pair first second index
    first := next_first
    second := next_second
    total := @u32.add total (@u32.add (view_twice (&first[1..3])) (ref_twice (@storage.at second 1)))
  links[0] := @u32.add links[0] 7
  links[1] := @u32.add links[1] 9
  return #[before, total, view_twice (&first[1..3]), view_twice (&second[1..3]),
    ref_twice (@storage.at first 1), ref_twice (@storage.at second 1),
    link_twice (@storage.link links 0), link_twice (@storage.link links 1),
    first[0], first[2], second[0], second[2]]
`;

function witnessExpected(input: number): Uint32Array {
  const first = [input, input + 10, input + 20];
  const second = [input + 100, input + 110, input + 120];
  const links = [input + 200, input + 210];
  const before = 2 * (first[1] + second[1] + links[0]);
  first[1] += 2 * input + 1 + 2;
  second[1] += 3;
  first[1] += 10;
  second[1] += 50;
  let total = 0;
  for (let index = 0; index < 3; index++) {
    first[1] += index;
    second[1] += index + 1;
    total += 2 * (first[1] + second[1]);
  }
  links[0] += 7;
  links[1] += 9;
  return new Uint32Array([
    before,
    total,
    2 * first[1],
    2 * second[1],
    2 * first[1],
    2 * second[1],
    2 * links[0],
    2 * links[1],
    first[0],
    first[2],
    second[0],
    second[2],
  ]);
}

const scratch = `const leaf = func (rows: own Array U32): Array U32 => return do:
  let temporary: Array U32 = #[rows[0], 3]
  rows[0] := @u32.add temporary[0] temporary[1]
  return rows
const outer = func (rows: own Array U32): Array U32 => return leaf (leaf rows)
io const answer = func (input: U32) => return do:
  let rows: Array U32 = #[input, 29]
  rows := leaf rows
  rows := outer rows
  let live: Array U32 = #[71, 73]
  rows := outer rows
  @storage.push live 79
  return #[rows[0], rows[1], live[0], live[1], live[2]]
`;

for (const kind of ["reader", "writer", "witnesses", "scratch"] as const) {
  Deno.test(`storage descriptor DAGs preserve ${kind} values and owner effects`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "squid-storage-dag-" });
    const entry = `${directory}/main.sq`;
    const stdRoot = new URL("../../std", import.meta.url).pathname;
    let compiler:
      | Awaited<ReturnType<typeof createZigProjectCompiler>>
      | undefined;
    try {
      compiler = await createZigProjectCompiler({
        executable: Deno.args[0],
        entry,
        stdRoot,
        prelude: `${stdRoot}/prelude.sq`,
        startupTimeoutMs: 5_000,
      });
      let source = witnesses;
      if (kind === "scratch") source = scratch;
      if (kind === "reader" || kind === "writer") {
        source = storageCallSource(kind, 4, 5);
      }
      const result = await compiler.build({
        sources: { [entry]: source },
        signal: AbortSignal.timeout(5_000),
      });
      assert(result.success, JSON.stringify(result));
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(result.bytes, { asynchronous });
        try {
          for (const input of [0, 1, 7, 41, 0xfffffffd, 3, 0]) {
            let expected: Uint32Array;
            if (kind === "witnesses") expected = witnessExpected(input);
            else if (kind === "scratch") {
              expected = new Uint32Array([input + 15, 29, 71, 73, 79]);
            } else expected = storageCallExpected(kind, 4, 5, input);
            let actual;
            if (asynchronous) actual = await guest.callAsync("answer", input);
            else actual = guest.call("answer", input);
            assert.deepEqual(actual, expected);
          }
        } finally {
          guest.dispose();
        }
      }
    } finally {
      await compiler?.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
