import { strict as assert } from "node:assert";
import { type Guest, instantiateGuest } from "../../host/guest.ts";
import {
  createZigProjectCompiler,
  type ZigProjectCompiler,
} from "../../host/zig_project_client.ts";

type Tier = "development" | "optimized";

async function withCompiler(
  codegenTier: Tier,
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
    cacheDirectory: false,
    codegenTier,
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
    extract(quick, "const quick_sort =", "const run =") + `
entry const merge_sorted = func (input: Array U32): Array U32 => return do:
  let values = @storage.copy input
  let temp: Array U32 = @array.fill 64 0
  if @u32.lt 0 values.length:
    merge_sort_helper values temp 0 (@u32.sub values.length 1)
  return values
entry const quick_sorted = func (input: Array U32): Array U32 => return do:
  let values = @storage.copy input
  quick_sort values 0 values.length
  return values
entry const empty_range = func (): Array U32 => return do:
  let values: Array U32 = #[9, 5, 3]
  quick_sort values 1 1
  return values
entry const singleton_range = func (): Array U32 => return do:
  let values: Array U32 = #[9, 5, 3]
  let temp: Array U32 = #[0, 0, 0]
  quick_sort values 1 2
  merge_sort_helper values temp 1 1
  return values
`;
}

const depthSource =
  `const descend = func (values: Array U32) -> (unused: Array U32) -> (remaining: U32) -> (left: U32) -> (right: U32): Unit => return do:
  if @u32.eq remaining 0:
    return ()
  let saved = @u32.add remaining 17
  if @u32.eq (@u32.rem remaining 2) 0:
    values[0] := @u32.add values[0] left
    descend values unused (@u32.sub remaining 1) (@u32.add left 1) (@u32.add right 3)
    values[1] := @u32.add values[1] saved
  else:
    values[0] := @u32.add values[0] right
    descend values unused (@u32.sub remaining 1) (@u32.add left 2) (@u32.add right 1)
    values[2] := @u32.add values[2] saved
  values[3] := @u32.add values[3] (@u32.add left right)
  return ()
const pair = func (left: Array U32) -> (right: Array U32) -> (remaining: U32): Unit => return do:
  left[0] := @u32.add left[0] right[0]
  if @u32.lt 0 remaining:
    pair left right (@u32.sub remaining 1)
  right[0] := @u32.add right[0] 1
  return ()
const touch = func (values: Array U32) -> (remaining: U32): Unit => return do:
  if @u32.lt 0 remaining:
    touch values (@u32.sub remaining 1)
  values[remaining] := remaining
  return ()
entry const answer = func (depth: U32): Array U32 => return do:
  let values: Array U32 = #[0, 0, 0, 0]
  let unused: Array U32 = #[]
  let caller = @u32.add depth 900
  descend values unused depth 0 0
  descend values unused depth depth 3
  return #[values[0], values[1], values[2], values[3], caller]
entry const distinct = func (depth: U32): Array U32 => return do:
  let left: Array U32 = #[1]
  let right: Array U32 = #[2]
  pair left right depth
  return #[left[0], right[0]]
entry const aliased = func (depth: U32): Array U32 => return do:
  let values: Array U32 = #[1]
  pair values values depth
  return #[values[0], values[0]]
entry const checked = func (depth: U32): U32 => return do:
  let values: Array U32 = #[0, 0, 0, 0]
  touch values depth
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

const rejected = [
  {
    name: "mutual recursion",
    source:
      `const first = func (values: Array U32) -> (n: U32): Unit => return do:
  if @u32.lt 0 n:
    second values (@u32.sub n 1)
  return ()
const second = func (values: Array U32) -> (n: U32): Unit => return do:
  values[0] := @u32.add values[0] n
  first values n
  return ()
entry const bad = func (n: U32) => return do:
  let values: Array U32 = #[0]
  first values n
  return values[0]
`,
  },
  {
    name: "captured closure backedge",
    body: `  values[0] := @u32.add values[0] n
  let again = func (next: U32): Unit => return walk values next
  if @u32.lt 0 n:
    again (@u32.sub n 1)`,
  },
  {
    name: "local allocation",
    body: `  let temporary: Array U32 = #[n]
  values[0] := temporary[0]
  if @u32.lt 0 n:
    walk values (@u32.sub n 1)`,
  },
  {
    name: "transitive allocation",
    prefix:
      `const allocate = func (values: Array U32) -> (n: U32): Unit => return do:
  let temporary: Array U32 = #[n]
  values[0] := temporary[0]
  return ()\n`,
    body: `  allocate values n
  if @u32.lt 0 n:
    walk values (@u32.sub n 1)`,
  },
  {
    name: "implicit global owner",
    prefix: "const hidden: Array U32 = #[42]\n",
    body: `  values[0] := hidden[0]
  if @u32.lt 0 n:
    walk values (@u32.sub n 1)`,
  },
  {
    name: "changed formal owner correspondence",
    source:
      `const walk = func (left: Array U32) -> (right: Array U32) -> (n: U32): Unit => return do:
  left[0] := right[0]
  if @u32.lt 0 n:
    walk right left (@u32.sub n 1)
  return ()
entry const bad = func (n: U32) => return do:
  let left: Array U32 = #[1]
  let right: Array U32 = #[2]
  walk left right n
  return left[0]
`,
  },
  {
    name: "resize",
    mode: "ResizeArray",
    body: `  @storage.truncate values 0
  if @u32.lt 0 n:
    walk values (@u32.sub n 1)`,
  },
  {
    name: "freeze",
    mode: "GrowArray",
    body: `  let fixed = @storage.freeze values
  if @u32.lt 0 n:
    walk values (@u32.sub n 1)`,
  },
  {
    name: "borrowed formal",
    source: `const walk = func (value: &U32) -> (n: U32): Unit => return do:
  @storage.write value n
  if @u32.lt 0 n:
    walk value (@u32.sub n 1)
  return ()
entry const bad = func (n: U32) => return do:
  let values: Array U32 = #[0]
  walk (&values[0]) n
  return values[0]
`,
  },
];

function rejectedSource(item: typeof rejected[number]): string {
  if (item.source !== undefined) return item.source;
  let mode = "Array";
  if (item.mode !== undefined) mode = item.mode;
  let prefix = "";
  if (item.prefix !== undefined) prefix = item.prefix;
  return `${prefix}const walk = func (values: ${mode} U32) -> (n: U32): Unit => return do:
${item.body}
  return ()
entry const bad = func (n: U32) => return do:
  let values: ${mode} U32 = #[0]
  walk values n
  return n
`;
}

// reserve on a caller-owned grower forces inline fallback. Its dynamic scalar
// body exceeds the real outline threshold before machine optimization, so the
// recursive call executes beneath an actual bank-sharing extracted region.
const outlineUpdates = 1500;
const outlineSource =
  `const accumulate = func (values: Array U32) -> (remaining: U32): Unit => return do:
  if @u32.lt 0 remaining:
    let saved = values[0]
    accumulate values (@u32.sub remaining 1)
    values[0] := @u32.add values[0] remaining
    values[1] := @u32.add values[1] saved
  return ()
const bulky = func (rows: ResizeArray U32) -> (values: Array U32) -> (input: U32): U32 => return do:
  @storage.reserve rows 4
  let total = input
${
    "  total := @u32.add total input\n".repeat(outlineUpdates / 2)
  }  accumulate values input
${
    "  total := @u32.add total input\n".repeat(outlineUpdates / 2)
  }  rows[0] := @u32.add rows[0] 1
  return @u32.add total values[0]
entry const answer = func (input: U32): Array U32 => return do:
  let rows: ResizeArray U32 = #[input]
  let values: Array U32 = #[input, 0]
  let saved = @u32.add input 333
  let result = bulky rows values input
  return #[result, values[0], values[1], rows[0], saved]
`;

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`unchanged recursive Goose sorts execute bounded inputs (${codegenTier})`, async () => {
    const source = await sortSource();
    await withCompiler(codegenTier, async (compiler, entry) => {
      const result = await build(compiler, entry, source);
      assert(result.success, JSON.stringify(result));
      const counters = result.stats.workCounters as Record<string, number>;
      assert(
        counters.scoped_recursive_definitions > 0,
        JSON.stringify(counters),
      );
      assert(counters.scoped_recursive_backedges > 0, JSON.stringify(counters));
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

  Deno.test(`recursive fixed ABI preserves scalars owner aliases and trap recovery (${codegenTier})`, async () => {
    await withCompiler(codegenTier, async (compiler, entry) => {
      const result = await build(compiler, entry, depthSource);
      assert(result.success, JSON.stringify(result));
      const counters = result.stats.workCounters as Record<string, number>;
      assert(
        counters.scoped_recursive_definitions > 0,
        JSON.stringify(counters),
      );
      assert(counters.scoped_recursive_calls > 0, JSON.stringify(counters));
      await withGuests(result.bytes, async (guest, call) => {
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
          const aliased = (2 ** (depth + 1) + depth + 1) >>> 0;
          assert.deepEqual(
            await call("aliased", depth),
            new Uint32Array([aliased, aliased]),
          );
        }
        await assert.rejects(() => call("checked", 5));
        assert.equal(await call("checked", 3), 6);
        // More invocations than the owner-slot budget expose retained owners;
        // committed Wasm memory must also remain fixed after warmup and traps.
        for (let index = 0; index < 32; index++) await call("checked", 3);
        const memory = guest.memoryBytes();
        for (let index = 0; index < 8192; index++) {
          assert.equal(await call("checked", 3), 6);
        }
        assert.equal(guest.memoryBytes(), memory);
        assert.deepEqual(
          await call("answer", 257),
          new Uint32Array(depthExpected(257)),
        );
      });
    });
  });

  Deno.test(`outlined caller preserves live bank values across ordinary recursion (${codegenTier})`, async () => {
    await withCompiler(codegenTier, async (compiler, entry) => {
      const result = await build(compiler, entry, outlineSource);
      assert(result.success, JSON.stringify(result));
      const counters = result.stats.workCounters as Record<string, number>;
      assert(counters.scoped_outlined_regions > 0, JSON.stringify(counters));
      assert(counters.scoped_outlined_globals > 0, JSON.stringify(counters));
      assert(
        counters.scoped_recursive_definitions > 0,
        JSON.stringify(counters),
      );
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

  for (const item of rejected) {
    Deno.test(`recursive admission rejects ${item.name} and retries (${codegenTier})`, async () => {
      await withCompiler(codegenTier, async (compiler, entry) => {
        const invalid = await build(compiler, entry, rejectedSource(item));
        assert(!invalid.success, item.name);
        assert(
          invalid.diagnostics.some((diagnostic) =>
            ["storage_unsupported", "storage_borrow_conflict", "storage_escape"]
              .includes(diagnostic.code)
          ),
          JSON.stringify(invalid),
        );
        const valid = await build(compiler, entry, depthSource);
        assert(valid.success, JSON.stringify(valid));
        await withGuests(valid.bytes, async (_guest, call) => {
          assert.equal(await call("checked", 3), 6);
        });
      });
    });
  }
}
