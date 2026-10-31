import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const fields =
  `const pair = func row => return {right: row.right, left: row.left}
const outer = func row => return {inner: pair (pair row), tail: pair row}
const merged_pair = func row => return @record.merge {right: row.right} {left: row.left}
entry const repeated = func (input: U32) => return do:
  let live: GrowArray U32 = #[101, input]
  let total: U32 = 0
  for index in 0 .. input:
    let selected = outer {right: @u32.add index 7, left: index}
    total := @u32.add total (@u32.add selected.inner.left selected.tail.right)
  let last = outer {left: live[1], right: @u32.add live[1] 7}
  @storage.push live 211
  return #[total, live[0], live[1], live[2], last.inner.left, last.tail.right]
entry const floating = func (input: F32) => return do:
  let live: GrowArray F32 = #[input, 3.5]
  let first = outer {left: live[0], right: live[1]}
  let second = outer {right: live[1], left: live[0]}
  return #[first.inner.left, second.tail.left, first.tail.right, live[0]]
entry const boolean = func (input: Bool) => return do:
  let live: GrowArray Bool = #[input]
  let selected = outer {right: true, left: live[0]}
  return selected.inner.left and selected.tail.right
entry const merging = func (input: U32) => return do:
  let live: GrowArray U32 = #[input]
  let first = outer (merged_pair {right: 3.5, left: live[0]})
  let second = merged_pair (pair (@record.merge {left: @u32.add live[0] 1} {right: 7.25}))
  return #[U32.to_f32 first.inner.left, first.tail.right, U32.to_f32 second.left, second.right]
const invoke = func row => return row.callback row.value
const foreign = func (host: U32 -> U32 ! {Foreign}) -> (input: U32): U32 ! {Foreign} => return do:
  let marker: GrowArray U32 = #[input]
  use next <- invoke {callback: host, value: marker[0]}
  let selected = outer {left: next, right: 2}
  return @u32.add selected.inner.left selected.tail.right
entry const foreign_zero = func (host: U32 -> U32 ! {Foreign}) => return foreign host 0
entry const foreign_middle = func (host: U32 -> U32 ! {Foreign}) => return foreign host 35
entry const foreign_wrapping = func (host: U32 -> U32 ! {Foreign}) => return foreign host 4294967293
`;

const destinations =
  `const pair = func row => return {right: row.right, left: row.left}
const outer = func row => return pair (pair row)
const scalar_pack = func (value: U32): Array U32 => return #[value, @u32.add value 1]
const pack = func (value: U32): Array {left: U32, right: U32} => return #[
  outer {right: @u32.add value 1, left: value},
  outer {left: @u32.add value 2, right: @u32.add value 3}]
entry const destination = func (input: U32) => return do:
  let live: GrowArray U32 = #[71]
  let direct = scalar_pack input
  let first = pack input
  @storage.push live 73
  let second = pack (@u32.add input 10)
  return #[direct[0], direct[1], first[0].left, first[0].right,
    first[1].left, first[1].right, second[0].left, second[0].right,
    second[1].left, second[1].right, live[0], live[1]]
type Token a is data = $Token
const touch = func (token: Token a) -> (value: U32): U32 => return value
entry const phantom = func (input: U32) => return do:
  let live: GrowArray U32 = #[input]
  let integer: Token (U32 -> U32) = $Token
  let floating: Token (F32 -> F32) = $Token
  let empty: Token Unit = $Token
  return touch integer (touch floating (touch empty live[0]))
`;

for (const codegenTier of ["development", "optimized"] as const) {
  for (
    const [name, source] of [["fields", fields], ["destinations", destinations]]
  ) {
    Deno.test(`concrete inline ${name} preserve current caller values (${codegenTier})`, async () => {
      const directory = await Deno.makeTempDir({
        prefix: "blot-concrete-fields-",
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
        startupTimeoutMs: 5_000,
      });
      try {
        const result = await compiler.build({
          sources: { [entry]: source },
          signal: AbortSignal.timeout(5_000),
        });
        assert(result.success, JSON.stringify(result));
        const counters = result.stats.workCounters as Record<string, number>;
        assert(
          counters.scoped_inline_definitions > 0,
          JSON.stringify(counters),
        );
        assert(counters.scoped_inline_cache_hits > 0, JSON.stringify(counters));
        assert(counters.scoped_field_recipe_hits > 0, JSON.stringify(counters));
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(result.bytes, { asynchronous });
          try {
            const call = async (entry: string, input: number | boolean) => {
              if (asynchronous) return await guest.callAsync(entry, input);
              return guest.call(entry, input);
            };
            if (name === "fields") {
              for (const input of [0, 1, 3, 100_000, 3]) {
                assert.deepEqual(
                  await call("repeated", input),
                  new Uint32Array([
                    (input * input + 6 * input) >>> 0,
                    101,
                    input,
                    211,
                    input,
                    input + 7,
                  ]),
                );
              }
              for (const input of [0, -0, 1.25, -10.5]) {
                assert.deepEqual(
                  await call("floating", input),
                  new Float32Array([input, input, 3.5, input]),
                );
              }
              for (const input of [false, true, false]) {
                assert.equal(await call("boolean", input), input);
              }
              for (const input of [0, 41, 1000]) {
                assert.deepEqual(
                  await call("merging", input),
                  new Float32Array([input, 3.5, input + 1, 7.25]),
                );
              }
              const observed: number[] = [];
              const receive = (value: number) => {
                observed.push(value);
                return (value + 5) >>> 0;
              };
              let host: ReturnType<typeof guest.capability>;
              if (asynchronous) {
                host = guest.capabilityAsync({
                  parameter: "U32",
                  result: "U32",
                  call: async (value) => {
                    await Promise.resolve();
                    return receive(value);
                  },
                });
              } else {
                host = guest.capability({
                  parameter: "U32",
                  result: "U32",
                  call: receive,
                });
              }
              const cases = [
                ["foreign_zero", 0],
                ["foreign_middle", 35],
                ["foreign_wrapping", 0xffff_fffd],
                ["foreign_middle", 35],
                ["foreign_zero", 0],
              ] as const;
              for (const [entry, input] of cases) {
                let actual;
                if (asynchronous) {
                  actual = await guest.callAsync(entry, host);
                } else {
                  actual = guest.call(entry, host);
                }
                assert.equal(actual, (input + 7) >>> 0);
              }
              assert.deepEqual(observed, cases.map((item) => item[1]));
            } else {
              for (const input of [0, 41, 0xffff_fffd, 3, 0]) {
                assert.deepEqual(
                  await call("destination", input),
                  new Uint32Array([
                    input,
                    input + 1,
                    input,
                    input + 1,
                    input + 2,
                    input + 3,
                    input + 10,
                    input + 11,
                    input + 12,
                    input + 13,
                    71,
                    73,
                  ]),
                );
                assert.equal(await call("phantom", input), input);
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
}
