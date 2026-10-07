// deno run --allow-read --allow-write scripts/bench_packed_storage.ts FIXTURE OUTPUT
// Build with: zig build packed-layout-fixture -Doptimize=debug --prefix zig-out-dev
import { strict as assert } from "node:assert";
const bytes = await Deno.readFile(Deno.args[0]);
assert(WebAssembly.validate(bytes));
async function runtime() {
  const { instance } = await WebAssembly.instantiate(bytes);
  const memory = instance.exports["blot:memory"] as WebAssembly.Memory;
  const call = (name: string, ...args: number[]) =>
    Number((instance.exports[name] as CallableFunction)(...args)) >>> 0;
  const word = (address: number) =>
    new DataView(memory.buffer).getUint32(address, true);
  return { call, word, memory };
}
const report = {
  note:
    "Isolated storage prototype: identical escaping three-word rows, one U32 and two F32 fields. No production collection ABI change. Times exclude host decoding; heap deltas include allocator size classes.",
  versions: Deno.version,
  rows: [] as Record<string, unknown>[],
};
const modes = ["boxed", "packed"] as const;
// Test exact scalar bits, including NaN payloads and signed zero.
for (const seed of [0, 0x80000000, 0x80100000, 0x7fc00000, 0xffffffff]) {
  const r = await runtime();
  const pointers = modes.map((mode) => r.call(mode, 257, seed));
  modes.forEach((mode, v) => {
    const pointer = pointers[v];
    assert.equal(r.word(pointer), 257);
    for (let i = 0; i < 257; i++) {
      const row = mode === "packed"
        ? pointer + 4 + i * 12
        : r.word(pointer + 4 + i * 4);
      for (let field = 0; field < 3; field++) {
        assert.equal(
          r.word(row + field * 4),
          (((i + seed) >>> 0) ^ (field * 0x100000)) >>> 0,
        );
      }
    }
  });
  assert.equal(
    r.call("sum_boxed", pointers[0]),
    r.call("sum_packed", pointers[1]),
  );
}
for (const count of [0, 1, 248, 10000, 100000]) {
  const guests = await Promise.all(modes.map(() => runtime()));
  const sample: number[][] = [[], []];
  const heaps: number[] = [];
  const checksums: number[] = [];
  for (let i = -10; i < 25; i++) {
    for (const v of i % 2 ? [1, 0] : [0, 1]) {
      const r = guests[v], mode = modes[v];
      r.call("blot:reset");
      const before = Math.max(r.call("heap"), 65536);
      const start = performance.now();
      const pointer = r.call(mode, count, 0);
      const checksum = r.call(`sum_${mode}`, pointer);
      const elapsed = performance.now() - start;
      if (i >= 0) sample[v].push(elapsed);
      heaps[v] = r.call("heap") - before;
      checksums[v] = checksum;
    }
    assert.equal(checksums[0], checksums[1]);
  }
  modes.forEach((mode, v) =>
    report.rows.push({
      count,
      mode,
      samples_ms: sample[v],
      heap_bytes: heaps[v],
      memory_bytes: guests[v].memory.buffer.byteLength,
    })
  );
}
await Deno.writeTextFile(Deno.args[1], JSON.stringify(report, null, 2) + "\n");
console.log(JSON.stringify(
  report.rows.map(({ samples_ms, ...row }) => ({
    ...row,
    median_ms: (samples_ms as number[]).toSorted((a, b) => a - b)[12],
  })),
  null,
  2,
));
