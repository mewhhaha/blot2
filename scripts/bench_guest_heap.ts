// deno run -A scripts/bench_guest_heap.ts [COMPILER [OUTPUT]]
// Observe the public nested-Array workload without changing executable code.
import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { createZigProjectCompiler } from "../compiler/zig_project_client.ts";

const root = new URL("../", import.meta.url).pathname;
const executable = resolve(
  Deno.args[0] ?? `${root}zig-native/zig-out/bin/blotc`,
);
const output = resolve(Deno.args[1] ?? `${root}build/bench/guest-heap`);
await Deno.mkdir(output, { recursive: true });
const source = `entry const gen = fn (count: U32) => do:
  let rows = @array.generate count (fn index => #[128578, 97 + index % 26])
  let checksum = 0
  for row in rows:
    checksum := self + row[0] + row[1]
  break checksum
`;
const entry = `${output}/main.blot`;
await Deno.writeTextFile(entry, source);
const sha = async (bytes: Uint8Array) =>
  [
    ...new Uint8Array(
      await crypto.subtle.digest("SHA-256", Uint8Array.from(bytes)),
    ),
  ].map((x) => x.toString(16).padStart(2, "0")).join("");
function leb(value: number): number[] {
  const bytes = [];
  do {
    const next = value & 127;
    value >>>= 7;
    bytes.push(next | (value ? 128 : 0));
  } while (value);
  return bytes;
}
function observeGlobals(
  bytes: Uint8Array,
  includeGlobals = true,
): Uint8Array<ArrayBuffer> {
  let cursor = 8;
  const read = () => {
    let value = 0, shift = 0, byte: number;
    do {
      byte = bytes[cursor++];
      value |= (byte & 127) << shift;
      shift += 7;
    } while (byte & 128);
    return value >>> 0;
  };
  let arena: number | undefined;
  const parts: Uint8Array[] = [bytes.slice(0, 8)];
  while (cursor < bytes.length) {
    const start = cursor, section = bytes[cursor++], length = read();
    const payload = cursor, end = cursor + length;
    if (section === 6) {
      const globals: { type: number; mutable: number; value: number }[] = [];
      for (let n = read(); n > 0; n--) {
        const type = bytes[cursor++], mutable = bytes[cursor++];
        const opcode = bytes[cursor++];
        let value = 0;
        if (opcode === 0x41) value = read();
        else if (opcode === 0x43) cursor += 4;
        else throw new Error(`Unsupported global initializer ${opcode}`);
        assert.equal(bytes[cursor++], 0x0b);
        globals.push({ type, mutable, value });
      }
      const candidates = globals.flatMap((g, i) =>
        g.type === 0x7f && g.mutable === 1 &&
          globals[i + 1]?.mutable === 1 &&
          globals[i + 1]?.value === g.value &&
          globals[i + 2]?.mutable === 0 &&
          globals[i + 2]?.value === g.value &&
          globals[i + 3]?.mutable === 1 &&
          globals[i + 3]?.value === 0
          ? [i]
          : []
      );
      assert.equal(candidates.length, 1, "Arena globals must be unambiguous");
      arena = candidates[0];
    }
    if (section === 7) {
      assert(arena !== undefined);
      cursor = payload;
      const count = read();
      const entries = [...bytes.slice(cursor, end)];
      for (
        const [name, index] of [["heap", arena], [
          "static_end",
          arena + 2,
        ]] as const
      ) {
        if (!includeGlobals) continue;
        const encoded = new TextEncoder().encode(`qual:${name}`);
        entries.push(...leb(encoded.length), ...encoded, 3, ...leb(index));
      }
      const memory = new TextEncoder().encode("qual:memory");
      entries.push(...leb(memory.length), ...memory, 2, ...leb(0));
      const next = Uint8Array.from([
        ...leb(count + (includeGlobals ? 3 : 1)),
        ...entries,
      ]);
      parts.push(Uint8Array.from([7, ...leb(next.length)]), next);
    } else parts.push(bytes.slice(start, end));
    cursor = end;
  }
  const result = new Uint8Array(
    parts.reduce((sum, part) => sum + part.length, 0),
  );
  let offset = 0;
  for (const part of parts) {
    result.set(part, offset);
    offset += part.length;
  }
  assert(WebAssembly.validate(result));
  return result;
}
const compiler = await createZigProjectCompiler({
  executable,
  entry,
  prelude: `${root}std/prelude.blot`,
  cacheDirectory: false,
  codegenTier: "optimized",
});
try {
  const built = await compiler.build({ sources: { [entry]: source } });
  assert(built.success, JSON.stringify(built));
  const bytes = built.bytes;
  await Deno.writeFile(`${output}/original.wasm`, bytes);
  const originalModule = new WebAssembly.Module(bytes);
  assert.deepEqual([
    ...new Uint8Array(
      WebAssembly.Module.customSections(originalModule, "blot:ownership")[0],
    ),
  ], [2, 2, 0]);
  const observedModule = new WebAssembly.Module(observeGlobals(bytes));
  const rows = [];
  for (const count of [1024, 2048, 4096, 8192]) {
    const raw = new WebAssembly.Instance(observedModule).exports;
    const call = (name: string, arg = 0) =>
      (raw[name] as CallableFunction)(arg);
    const global = (name: string) =>
      Number((raw[name] as WebAssembly.Global).value);
    const memory = raw["qual:memory"] as WebAssembly.Memory;
    call("blot:ownership_enter");
    const expected = count * (128578 + 97) +
      Array.from({ length: count }, (_, index) => index % 26).reduce(
        (a, b) => a + b,
        0,
      );
    assert.equal(call("gen", count), expected);
    const words = new DataView(memory.buffer);
    const histogram: Record<
      number,
      { blocks: number; bytes: number; requested: number }
    > = {};
    const heap = global("qual:heap");
    // The allocator reserves at least the first 64 KiB even when immutable
    // static data ends earlier. Above that, it starts after the actual data.
    const start = Math.max(65536, global("qual:static_end"));
    let cursor = start;
    while (cursor < heap) {
      const size = words.getUint32(cursor, true),
        requested = words.getUint32(cursor + 4, true);
      assert(size >= 48 && size % 16 === 0 && cursor + size <= heap);
      const bin = histogram[size] ??= { blocks: 0, bytes: 0, requested: 0 };
      bin.blocks++;
      bin.bytes += size;
      bin.requested += requested;
      cursor += size;
    }
    assert.equal(cursor, heap);
    assert.equal(
      histogram[48]?.blocks,
      count,
      "One inner Array per input must remain in the allocation histogram",
    );
    assert(
      (histogram[4096]?.blocks ?? 0) >= 1,
      "The invocation must exercise root journal storage",
    );
    const committed = memory.buffer.byteLength;
    call("blot:ownership_leave");
    assert.equal(global("blot:rc_roots"), 0);
    assert.equal(global("blot:rc_leases"), 0);
    // A control adds the private memory export alone. Neither control nor
    // full telemetry changes the executable sections.
    const plain = new WebAssembly.Instance(
      new WebAssembly.Module(observeGlobals(bytes, false)),
    ).exports;
    (plain["blot:ownership_enter"] as CallableFunction)();
    assert.equal((plain.gen as CallableFunction)(count), expected);
    assert.equal(
      (plain["qual:memory"] as WebAssembly.Memory).buffer.byteLength,
      committed,
    );
    (plain["blot:ownership_leave"] as CallableFunction)(0);
    rows.push({
      count,
      committed_bytes: committed,
      heap_start: start,
      heap_end: heap,
      heap_bytes: heap - start,
      histogram,
    });
  }
  assert(rows[2].committed_bytes < 448 * 1024);
  const report = {
    compiler: executable,
    compiler_sha256: await sha(await Deno.readFile(executable)),
    harness_sha256: await sha(await Deno.readFile(new URL(import.meta.url))),
    source,
    wasm_sha256: await sha(bytes),
    telemetry:
      "Adds only global/memory exports; compared with a memory-export-only control",
    histogram_scope:
      "All dynamic arena blocks at return, including retired/recycled blocks; requested bytes count active payloads only",
    rows,
  };
  await Deno.writeTextFile(
    `${output}/results.json`,
    JSON.stringify(report, null, 2) + "\n",
  );
  console.log(JSON.stringify(report));
} finally {
  await compiler.dispose();
}
