import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const program = `import * as iter from "std/iter"
type Stats is data = #Stats {pulls: U32, trace: U32}

type Counter is data = #Counter {value: U32, end: U32}

const Counter.iter = func (cursor: Counter) => return cursor
const Counter.next = func (cursor: Counter) => return do:
  let state = cursor
  use stats <- @state.get #Stats
  use @state.set (#Stats {pulls: stats.pulls + 1, trace: stats.trace * 31 + state.value + 1})
  if state.value == state.end:
    break #Nothing
  break #Some (state.value, #Counter {value: state.value + 1, end: state.end})
const sum = func window => return iter.fold_left add 0 window
entry const effects = func input => return do:
  let mode = input / 16777216
  let width = input / 65536 % 256 + 1
  let count = input % 65536
  let (stats, answer) = @state.run (#Stats {pulls: 0, trace: 0}) (func () => return do:
    let cursor = iter.windows width (#Counter {value: 0, end: count})
    if mode == 0:
      break iter.fold_left (func total => return func window => return total + sum window) 0 cursor
    if mode == 1:
      break iter.fold_left (func total => return func window => return total + sum window) 0 (iter.take 0 cursor)
    if mode == 2:
      break iter.fold_left (func total => return func window => return total + sum window) 0 (iter.take 1 cursor)
    if mode == 3:
      let total = 0
      for window in cursor:
        total := sum window
        break
      break total
    if mode == 4:
      for window in cursor:
        break sum window
      break 999
    break iter.fold_left (func total => return func pair => return do:
      let (window, _) = pair
      break total + sum window) 0 (iter.zip cursor (iter.range 0 1)))
  break #[stats.pulls, stats.trace, answer]
entry const snapshots = func input => return do:
  let width = input / 65536 + 1
  let count = input % 65536
  let source = iter.map (func value => return #[value, value + 100]) (iter.range 0 count)
  let cursor = iter.windows width source
  let saved = cursor.next
  let #Some (first, rest) = saved else:
    break 999
  let sum_rows = func window => return iter.fold_left (func total => return func (row: Array U32) => return total + row[0] + row[1]) 0 window
  let total = 0
  for window in rest:
    let pressure = @array.generate 8192 identity
    total := self + sum_rows window + pressure[0]
  let #Some (again, _) = cursor.next else:
    break 999
  break total + sum_rows first + sum_rows again
`;

Deno.test("completed window producers preserve all widths snapshots pull order and early exits in both tiers", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-completed-windows-",
  });
  const entry = `${directory}/main.blot`;
  try {
    for (const codegenTier of ["optimized", "development"] as const) {
      const compiler = await createZigProjectCompiler({
        executable: Deno.args[0],
        entry,
        codegenTier,
        prelude: new URL("../../std/prelude.blot", import.meta.url).pathname,
        stdRoot: new URL("../../std", import.meta.url).pathname,
        cacheDirectory: false,
      });
      try {
        const result = await compiler.build({ sources: { [entry]: program } });
        assert(result.success, JSON.stringify(result));
        const guest = await instantiateGuest(result.bytes);
        try {
          for (let width = 1; width <= 17; width++) {
            for (const count of [0, 1, width - 1, width, width + 1, 65, 245]) {
              const windows = Math.max(0, count - width + 1);
              const first = width * (width - 1) / 2;
              for (let mode = 0; mode < 6; mode++) {
                let pulls = count + 1;
                let answer = width * windows * (count - 1) / 2;
                if (mode === 1) {
                  pulls = 0;
                  answer = 0;
                }
                if (mode >= 2 && mode <= 4) {
                  if (windows > 0) pulls = width;
                  answer = 0;
                  if (windows > 0) answer = first;
                  else if (mode === 4) answer = 999;
                }
                if (mode === 5) {
                  pulls = Math.min(count + 1, width + 1);
                  answer = 0;
                  if (windows > 0) answer = first;
                }
                let trace = 0;
                for (let value = 0; value < pulls; value++) {
                  trace = (Math.imul(trace, 31) + value + 1) >>> 0;
                }
                assert.deepEqual(
                  guest.call(
                    "effects",
                    mode * 16777216 + (width - 1) * 65536 + count,
                  ),
                  Uint32Array.from([pulls, trace, answer >>> 0]),
                  JSON.stringify({ codegenTier, width, count, mode }),
                );
              }
              let snapshots = 999;
              if (windows > 0) {
                snapshots = width * windows * (count + 99) +
                  width * (width + 99);
              }
              assert.equal(
                guest.call("snapshots", (width - 1) * 65536 + count),
                snapshots,
                JSON.stringify({ codegenTier, width, count }),
              );
            }
          }
        } finally {
          guest.dispose();
        }
      } finally {
        await compiler.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
