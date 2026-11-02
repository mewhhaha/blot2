import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
import {
  storageCallExpected,
  storageCallSource,
} from "../../scripts/bench/storage_calls.ts";

const witnesses = `const view_leaf = func (rows: &[U32]): U32 => return rows[0]
const view_twice = func (rows: &[U32]): U32 => return @u32.add (view_leaf rows) (view_leaf rows)
const ref_leaf = func (value: Ref U32): U32 => return @storage.load value
const ref_twice = func (value: Ref U32): U32 => return @u32.add (ref_leaf value) (ref_leaf value)
const link_leaf = func (value: Link U32): U32 => return @storage.load value
const link_twice = func (value: Link U32): U32 => return @u32.add (link_leaf value) (link_leaf value)
const row_value = func (rows: ResizeArray U32): U32 => return rows[1]
const mutate_pair = func (left: ResizeArray U32) -> (right: ResizeArray U32) -> (amount: U32): Unit => return do:
  left[1] := @u32.add (row_value left) amount
  right[1] := @u32.add (row_value right) (@u32.add amount 1)
const invoke = func callback -> (amount: U32): Unit => return do:
  callback amount
  callback (@u32.add amount 1)
const invoke_twice = func callback -> (amount: U32): Unit => return do:
  invoke callback amount
  invoke callback (@u32.add amount 2)
entry const answer = func (input: U32) => return do:
  let first: ResizeArray U32 = #[input, @u32.add input 10, @u32.add input 20]
  let second: ResizeArray U32 = #[@u32.add input 100, @u32.add input 110, @u32.add input 120]
  let links: GrowArray U32 = #[@u32.add input 200, @u32.add input 210]
  let first_view = &first[1..3]
  let second_view = &second[1..3]
  let first_ref = @storage.at first 1
  let second_ref = @storage.at second 1
  let first_link = @storage.link links 0
  let second_link = @storage.link links 1
  let before = @u32.add (view_twice first_view) (@u32.add (ref_twice second_ref) (link_twice first_link))
  mutate_pair first first input
  mutate_pair first second 2
  let write_first = func (amount: U32): Unit => return do:
    first[1] := @u32.add first[1] amount
  let write_second = func (amount: U32): Unit => return do:
    second[1] := @u32.add second[1] amount
  invoke_twice write_first 1
  invoke_twice write_second 11
  let total: U32 = 0
  for index in 0 .. 3:
    mutate_pair first second index
    total := @u32.add total (@u32.add (view_twice first_view) (ref_twice second_ref))
  links[0] := @u32.add links[0] 7
  links[1] := @u32.add links[1] 9
  return #[before, total, view_twice first_view, view_twice second_view,
    ref_twice first_ref, ref_twice second_ref, link_twice first_link, link_twice second_link,
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

const scratch = `const leaf = func (rows: GrowArray U32): Unit => return do:
  let temporary: GrowArray U32 = #[rows[0], 3]
  rows[0] := @u32.add temporary[0] temporary[1]
const outer = func (rows: GrowArray U32): Unit => return do:
  leaf rows
  leaf rows
entry const answer = func (input: U32) => return do:
  let rows: GrowArray U32 = #[input, 29]
  leaf rows
  outer rows
  let live: GrowArray U32 = #[71, 73]
  outer rows
  @storage.push live 79
  return #[rows[0], rows[1], live[0], live[1], live[2]]
`;

for (const codegenTier of ["development", "optimized"] as const) {
  for (const kind of ["reader", "writer", "witnesses", "scratch"] as const) {
    Deno.test(`storage descriptor DAGs preserve ${kind} values and owner effects (${codegenTier})`, async () => {
      const directory = await Deno.makeTempDir({ prefix: "blot-storage-dag-" });
      const entry = `${directory}/main.blot`;
      const stdRoot = new URL("../../std", import.meta.url).pathname;
      let compiler:
        | Awaited<ReturnType<typeof createZigProjectCompiler>>
        | undefined;
      try {
        compiler = await createZigProjectCompiler({
          executable: Deno.args[0],
          entry,
          stdRoot,
          prelude: `${stdRoot}/prelude.blot`,
          cacheDirectory: false,
          codegenTier,
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
        if (kind === "scratch") {
          const work = result.stats.workCounters as Record<string, number>;
          assert(work.scoped_function_plan_definitions >= 4, JSON.stringify(work));
          assert(work.scoped_function_plan_hits > 0, JSON.stringify(work));
        }
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
}
