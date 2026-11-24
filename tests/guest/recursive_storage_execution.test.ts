import { strict as assert } from "node:assert";
import { type Guest, instantiateGuest } from "../../host/guest.ts";
import {
  createZigProjectCompiler,
  type ZigProjectCompiler,
} from "../../host/zig_project_client.ts";

async function withCompiler(
  run: (compiler: ZigProjectCompiler, entry: string) => Promise<void>,
): Promise<void> {
  const directory = await Deno.makeTempDir({ prefix: "blot-recursion-" });
  const entry = `${directory}/main.blot`;
  const stdRoot = new URL("../../std", import.meta.url).pathname;
  const compiler = await createZigProjectCompiler({
    executable: Deno.args[0],
    entry,
    stdRoot,
    prelude: `${stdRoot}/prelude.blot`,
    startupTimeoutMs: 5000,
  });
  try {
    await run(compiler, entry);
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
}

function build(compiler: ZigProjectCompiler, entry: string, source: string) {
  return compiler.build({
    sources: { [entry]: source },
    signal: AbortSignal.timeout(5000),
  });
}

async function withGuests(
  bytes: Uint8Array<ArrayBuffer>,
  run: (
    guest: Guest,
    call: (name: string, argument: unknown) => Promise<unknown>,
  ) => Promise<void>,
): Promise<void> {
  for (const asynchronous of [false, true]) {
    const guest = await instantiateGuest(bytes, { asynchronous });
    const call = async (name: string, argument: unknown) => {
      if (asynchronous) return await guest.callAsync(name, argument);
      return guest.call(name, argument);
    };
    try {
      await run(guest, call);
    } finally {
      guest.dispose();
    }
  }
}

// Read the exact original helpers, including both recursive branches. The test
// wrapper only supplies small initialized owners and observes the complete output.
async function sortSource(): Promise<string> {
  const merge = await Deno.readTextFile(
    new URL("../../benchmarks/goose/ports/sort_merge.blot", import.meta.url),
  );
  const quick = await Deno.readTextFile(
    new URL("../../benchmarks/goose/ports/sort_quick.blot", import.meta.url),
  );
  const extract = (source: string, start: string, end: string) => {
    const first = source.indexOf(start);
    const last = source.indexOf(end, first);
    assert(first >= 0 && last > first, `Missing original helper: ${start}`);
    return source.slice(first, last);
  };
  return extract(merge, "const merge =", "const merge_sort_inplace =") +
    extract(quick, "const quick_sort:", "const run =") + `
entry const merge_sorted = func (input: Array U32): Array U32 => return do:
  let values = @storage.copy input
  let temp: Array U32 = @array.fill 64 0
  if @u32.lt 0 values.length:
    let (sorted, _) = merge_sort_helper values temp 0 (@u32.sub values.length 1)
    return sorted
  return values
entry const quick_sorted = func (input: Array U32): Array U32 => return do:
  let values = @storage.copy input
  return quick_sort values 0 values.length
entry const empty_range = func (): Array U32 => return do:
  let values: Array U32 = #[9, 5, 3]
  return quick_sort values 1 1
entry const singleton_range = func (): Array U32 => return do:
  let values: Array U32 = #[9, 5, 3]
  let temp: Array U32 = #[0, 0, 0]
  let values = quick_sort values 1 2
  let (values, _) = merge_sort_helper values temp 1 1
  return values
`;
}

const depthSource =
  `const descend: own Array U32 -> Array U32 -> U32 -> U32 -> U32 -> Array U32 = func (values: own Array U32) -> (unused: Array U32) -> (remaining: U32) -> (left: U32) -> (right: U32): Array U32 => return do:
  if @u32.eq remaining 0:
    return values
  let saved = @u32.add remaining 17
  if @u32.eq (@u32.rem remaining 2) 0:
    values[0] := @u32.add values[0] left
    values := descend own values unused (@u32.sub remaining 1) (@u32.add left 1) (@u32.add right 3)
    values[1] := @u32.add values[1] saved
  else:
    values[0] := @u32.add values[0] right
    values := descend own values unused (@u32.sub remaining 1) (@u32.add left 2) (@u32.add right 1)
    values[2] := @u32.add values[2] saved
  values[3] := @u32.add values[3] (@u32.add left right)
  return values
const pair: own Array U32 -> own Array U32 -> U32 -> (Array U32, Array U32) = func (left: own Array U32) -> (right: own Array U32) -> (remaining: U32): (Array U32, Array U32) => return do:
  left[0] := @u32.add left[0] right[0]
  if @u32.lt 0 remaining:
    let (next_left, next_right) = pair own left own right (@u32.sub remaining 1)
    left := next_left
    right := next_right
  right[0] := @u32.add right[0] 1
  return (left, right)
const touch: own Array U32 -> U32 -> Array U32 = func (values: own Array U32) -> (remaining: U32): Array U32 => return do:
  if @u32.lt 0 remaining:
    values := touch own values (@u32.sub remaining 1)
  values[remaining] := remaining
  return values
entry const answer = func (depth: U32): Array U32 => return do:
  let values: Array U32 = #[0, 0, 0, 0]
  let unused: Array U32 = #[]
  let caller = @u32.add depth 900
  values := descend values unused depth 0 0
  values := descend values unused depth depth 3
  return #[values[0], values[1], values[2], values[3], caller]
entry const distinct = func (depth: U32): Array U32 => return do:
  let left: Array U32 = #[1]
  let right: Array U32 = #[2]
  let (left, right) = pair left right depth
  return #[left[0], right[0]]
entry const checked = func (depth: U32): U32 => return do:
  let values: Array U32 = #[0, 0, 0, 0]
  values := touch values depth
  return @u32.add (@u32.add values[0] values[1]) (@u32.add values[2] values[3])
`;

function depthExpected(depth: number): number[] {
  const values = [0, 0, 0, 0, depth + 900];
  for (const initial of [[0, 0], [depth, 3]]) {
    let [left, right] = initial;
    for (let remaining = depth; remaining > 0; remaining--) {
      const saved = remaining + 17;
      if (remaining % 2 === 0) {
        values[0] += left;
        values[1] += saved;
        values[3] += left + right;
        left += 1;
        right += 3;
      } else {
        values[0] += right;
        values[2] += saved;
        values[3] += left + right;
        left += 2;
        right += 1;
      }
    }
  }
  return values.map((value) => value >>> 0);
}

// Recursion through each of these forms runs like any other call; the
// scoped backend's recursive storage admission declined them.
const recursive: {
  name: string;
  expected: (n: number) => number;
  source?: string;
  body?: string;
  prefix?: string;
  mode?: string;
}[] = [
  {
    name: "mutual recursion",
    expected: (n) => (n * (n - 1) / 2) >>> 0,
    source:
      `const first: own Array U32 -> U32 -> Array U32 = func (values: own Array U32) -> (n: U32): Array U32 => return do:
  if @u32.lt 0 n:
    return second own values (@u32.sub n 1)
  return values
const second: own Array U32 -> U32 -> Array U32 = func (values: own Array U32) -> (n: U32): Array U32 => return do:
  values[0] := @u32.add values[0] n
  return first own values n
entry const bad = func (n: U32) => return do:
  let values: Array U32 = #[0]
  values := first values n
  return values[0]
`,
  },
  {
    name: "captured closure backedge",
    expected: (n) => n,
    body: `  values[0] := @u32.add values[0] n
  let again = func (vs: own Array U32) -> (next: U32): Array U32 => return walk own vs next
  if @u32.lt 0 n:
    values := again values (@u32.sub n 1)`,
  },
  {
    name: "local allocation",
    expected: (n) => n,
    body: `  let temporary: Array U32 = #[n]
  values[0] := temporary[0]
  if @u32.lt 0 n:
    values := walk own values (@u32.sub n 1)`,
  },
  {
    name: "transitive allocation",
    expected: (n) => n,
    prefix:
      `const allocate = func (values: own Array U32) -> (n: U32): Array U32 => return do:
  let temporary: Array U32 = #[n]
  values[0] := temporary[0]
  return values\n`,
    body: `  values := allocate values n
  if @u32.lt 0 n:
    values := walk own values (@u32.sub n 1)`,
  },
  {
    name: "implicit global owner",
    expected: (n) => n,
    prefix: "const hidden: Array U32 = #[42]\n",
    body: `  values[0] := hidden[0]
  if @u32.lt 0 n:
    values := walk own values (@u32.sub n 1)`,
  },
  {
    name: "changed formal owner correspondence",
    expected: () => 2,
    source:
      `const walk: own Array U32 -> own Array U32 -> U32 -> (Array U32, Array U32) = func (left: own Array U32) -> (right: own Array U32) -> (n: U32): (Array U32, Array U32) => return do:
  left[0] := right[0]
  if @u32.lt 0 n:
    let (next_right, next_left) = walk own right own left (@u32.sub n 1)
    return (next_left, next_right)
  return (left, right)
entry const bad = func (n: U32) => return do:
  let left: Array U32 = #[1]
  let right: Array U32 = #[2]
  let (left, _) = walk left right n
  return left[0]
`,
  },
  {
    name: "resize",
    expected: (n) => n,
    mode: "ResizeArray",
    body: `  @storage.truncate values 0
  if @u32.lt 0 n:
    values := walk own values (@u32.sub n 1)`,
  },
  {
    name: "freeze",
    expected: (n) => n,
    mode: "GrowArray",
    body: `  let fixed = @storage.freeze (@storage.copy values)
  if @u32.lt 0 n:
    values := walk own values (@u32.sub n 1)`,
  },
  {
    name: "borrowed formal",
    expected: (n) => n + 1,
    source: `const walk: &U32 -> own Array U32 -> U32 -> Array U32 = func (value: &U32) -> (sink: own Array U32) -> (n: U32): Array U32 => return do:
  sink[0] := @u32.add sink[0] (@storage.load value)
  if @u32.lt 0 n:
    return walk value own sink (@u32.sub n 1)
  return sink
entry const bad = func (n: U32) => return do:
  let values: Array U32 = #[1]
  let sink: Array U32 = #[0]
  sink := walk (&values[0]) sink n
  return sink[0]
`,
  },
];

function recursiveSource(item: typeof recursive[number]): string {
  if (item.source !== undefined) return item.source;
  let mode = "Array";
  if (item.mode !== undefined) mode = item.mode;
  let prefix = "";
  if (item.prefix !== undefined) prefix = item.prefix;
  return `${prefix}const walk: own ${mode} U32 -> U32 -> ${mode} U32 = func (values: own ${mode} U32) -> (n: U32): ${mode} U32 => return do:
${item.body}
  return values
entry const bad = func (n: U32) => return do:
  let values: ${mode} U32 = #[0]
  let _ = walk values n
  return n
`;
}

// reserve on a caller-owned grower forces inline fallback. Its dynamic scalar
// body exceeds the real outline threshold before machine optimization, so the
// recursive call executes beneath an actual bank-sharing extracted region.
const outlineUpdates = 1500;
const outlineSource =
  `const accumulate: own Array U32 -> U32 -> Array U32 = func (values: own Array U32) -> (remaining: U32): Array U32 => return do:
  if @u32.lt 0 remaining:
    let saved = values[0]
    values := accumulate own values (@u32.sub remaining 1)
    values[0] := @u32.add values[0] remaining
    values[1] := @u32.add values[1] saved
  return values
const bulky = func (rows: own ResizeArray U32) -> (values: own Array U32) -> (input: U32): (ResizeArray U32, Array U32, U32) => return do:
  @storage.reserve rows 4
  let total = input
${
    "  total := @u32.add total input\n".repeat(outlineUpdates / 2)
  }  values := accumulate values input
${
    "  total := @u32.add total input\n".repeat(outlineUpdates / 2)
  }  rows[0] := @u32.add rows[0] 1
  let result = @u32.add total values[0]
  return (rows, values, result)
entry const answer = func (input: U32): Array U32 => return do:
  let rows: ResizeArray U32 = #[input]
  let values: Array U32 = #[input, 0]
  let saved = @u32.add input 333
  let (rows, values, result) = bulky rows values input
  return #[result, values[0], values[1], rows[0], saved]
`;

Deno.test(`unchanged recursive Goose sorts execute bounded inputs`, async () => {
  const source = await sortSource();
  await withCompiler(async (compiler, entry) => {
    const result = await build(compiler, entry, source);
    assert(result.success, JSON.stringify(result));
    let state = 42;
    const random = Array.from({ length: 32 }, () => {
      state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
      return state % 1000;
    });
    const cases = [
      [],
      [42],
      [0, 1, 2, 3, 4, 5, 6, 7],
      [7, 6, 5, 4, 3, 2, 1, 0],
      [3, 3, 1, 3, 1, 0, 0, 3],
      random,
    ];
    await withGuests(result.bytes, async (_guest, call) => {
      for (const name of ["merge_sorted", "quick_sorted"]) {
        for (const values of cases) {
          const input = new Uint32Array(values);
          const output = await call(name, input);
          assert.deepEqual(
            output,
            new Uint32Array(values.toSorted((a, b) => a - b)),
          );
          assert.deepEqual(input, new Uint32Array(values));
        }
      }
      for (const name of ["empty_range", "singleton_range"]) {
        assert.deepEqual(await call(name, null), new Uint32Array([9, 5, 3]));
      }
    });
  });
});

Deno.test(`recursive fixed ABI preserves scalars owner aliases and trap recovery`, async () => {
  await withCompiler(async (compiler, entry) => {
    const result = await build(compiler, entry, depthSource);
    assert(result.success, JSON.stringify(result));
    await withGuests(result.bytes, async (_guest, call) => {
      for (const depth of [0, 1, 2, 129, 257, 512, 3, 0, 257]) {
        assert.deepEqual(
          await call("answer", depth),
          new Uint32Array(depthExpected(depth)),
        );
      }
      for (const depth of [0, 1, 3, 7]) {
        assert.deepEqual(
          await call("distinct", depth),
          new Uint32Array([1 + 2 * (depth + 1), depth + 3]),
        );
      }
      await assert.rejects(() => call("checked", 5));
      assert.equal(await call("checked", 3), 6);
      // More invocations than the owner-slot budget expose retained owners.
      for (let index = 0; index < 8192; index++) {
        assert.equal(await call("checked", 3), 6);
      }
      assert.deepEqual(
        await call("answer", 257),
        new Uint32Array(depthExpected(257)),
      );
    });
  });
});

Deno.test(`outlined caller preserves live bank values across ordinary recursion`, async () => {
  await withCompiler(async (compiler, entry) => {
    const result = await build(compiler, entry, outlineSource);
    assert(result.success, JSON.stringify(result));
    await withGuests(result.bytes, async (guest, call) => {
      assert.equal(guest.abi.version, 8);
      for (const input of [0, 1, 7, 129, 3, 0, 129]) {
        const first = input + input * (input + 1) / 2;
        const total = input * (outlineUpdates + 1);
        assert.deepEqual(
          await call("answer", input),
          new Uint32Array([
            total + first,
            first,
            input * input,
            input + 1,
            input + 333,
          ]),
        );
      }
    });
  });
});

for (const item of recursive) {
  Deno.test(`recursion through ${item.name} runs`, async () => {
    await withCompiler(async (compiler, entry) => {
      const built = await build(compiler, entry, recursiveSource(item));
      assert(built.success, JSON.stringify(built));
      await withGuests(built.bytes, async (_guest, call) => {
        for (const n of [0, 1, 2, 5]) {
          assert.equal(await call("bad", n), item.expected(n), item.name);
        }
      });
    });
  });
}
