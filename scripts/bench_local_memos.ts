// deno run -A scripts/bench_local_memos.ts BASELINE CANDIDATE OUTPUT [--callbacks]
import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { cpuUsage } from "node:process";
import { createZigProjectCompiler } from "../compiler/zig_project_client.ts";
assert(Deno.args.length === 3 || Deno.args.length === 4);
assert(Deno.args[3] === undefined || Deno.args[3] === "--callbacks");
const [baseline, candidate, output] = Deno.args.slice(0, 3).map((path) =>
  resolve(path)
);
await Deno.mkdir(output, { recursive: true });
const variants = [{ name: "cells", compiler: baseline }, {
  name: "memos",
  compiler: candidate,
}];
const hash = async (path: string) =>
  [
    ...new Uint8Array(
      await crypto.subtle.digest("SHA-256", await Deno.readFile(path)),
    ),
  ].map((byte) => byte.toString(16).padStart(2, "0")).join("");
const pins: Record<string, string> = {};
for (const variant of variants) {
  pins[variant.compiler] = await hash(variant.compiler);
}
pins[new URL(import.meta.url).pathname] = await hash(
  new URL(import.meta.url).pathname,
);
const load = async () => (await Deno.readTextFile("/proc/loadavg")).trim();
const loadStart = await load();
let body =
  `const sum = func (count: U32) => return func ~(value: U32) => return do:
  let first = value
  let second = first
  let total = 0
  for i in 0..count:
    use current <- @demand second
    total := @u32.add self current
  break total
`;
if (Deno.args[3] === "--callbacks") {
  body =
    `const sum = func (count: U32) => return func ~(value: U32) => return do:
  let first = func () => return @demand value
  let alias = first
  let second = func () => return @demand value
  let total = 0
  for i in 0..count:
    use current <- alias ()
    use second ()
    total := @u32.add self current
  break total
`;
}
const source = body +
  `entry const outside = func (count: U32) => return sum count 21
entry const inside = func (count: U32) => return do:
  let total = 0
  for i in 0..count:
    use current <- sum 4 i
    total := @u32.add self current
  break total
`;
async function compile(
  variant: typeof variants[number],
  input: string,
  name: string,
) {
  const path = `${output}/${name}-${variant.name}.wasm`;
  const wall = performance.now();
  const result = await new Deno.Command(variant.compiler, {
    args: ["build", input, path, "--prelude", "none"],
    stdout: "piped",
    stderr: "piped",
    env: { BLOT_CACHE_DIR: "" },
  }).output();
  const wall_ms = performance.now() - wall;
  const log = new TextDecoder().decode(result.stdout);
  assert(result.success, log + new TextDecoder().decode(result.stderr));
  const metrics = log.trim().split("\n").map((line) => JSON.parse(line)).find(
    (item) => item.kind === "compilation",
  );
  assert(metrics.success && metrics.memory.live_bytes === 0);
  await Deno.writeTextFile(`${output}/${name}-${variant.name}.jsonl`, log);
  return { bytes: await Deno.readFile(path), metrics, wall_ms };
}
const median = (values: number[]) =>
  [...values].sort((a, b) => a - b)[Math.floor(values.length / 2)];
function leb(value: number): number[] {
  const bytes: number[] = [];
  do {
    let byte = value & 127;
    value >>>= 7;
    if (value !== 0) byte |= 128;
    bytes.push(byte);
  } while (value !== 0);
  return bytes;
}
// Telemetry adds exports only; CPU runs the original bytes. No executable
// instruction, collection representation or allocation behavior is changed.
function telemetry(bytes: Uint8Array): Uint8Array<ArrayBuffer> {
  let cursor = 8;
  const read = () => {
    let result = 0, shift = 0, byte: number;
    do {
      byte = bytes[cursor++];
      result |= (byte & 127) << shift;
      shift += 7;
    } while ((byte & 128) !== 0);
    return result >>> 0;
  };
  let heap: number | undefined;
  const parts: number[] = [...bytes.slice(0, 8)];
  while (cursor < bytes.length) {
    const start = cursor;
    const section = bytes[cursor++];
    const length = read(), payload = cursor, end = cursor + length;
    if (section === 6) {
      const count = read();
      const globals: { type: number; mutable: number; value: number }[] = [];
      for (let i = 0; i < count; i++) {
        const type = bytes[cursor++],
          mutable = bytes[cursor++],
          opcode = bytes[cursor++];
        let value = 0;
        if (opcode === 0x41) value = read();
        else if (opcode === 0x43) cursor += 4;
        else throw new Error("Unsupported telemetry global initializer");
        assert(bytes[cursor++] === 0x0b);
        globals.push({ type, mutable, value });
      }
      heap = globals.findIndex((item, i) =>
        item.type === 0x7f && item.mutable === 1 &&
        globals[i + 1]?.mutable === 1 && globals[i + 2]?.mutable === 0 &&
        globals[i + 3]?.value === 0 && globals[i + 1]?.value === item.value &&
        globals[i + 2]?.value === item.value
      );
      if (heap < 0) heap = undefined;
    }
    if (section === 7) {
      if (heap === undefined) {
        parts.push(...bytes.slice(start, end));
        cursor = end;
        continue;
      }
      cursor = payload;
      const count = read();
      const rest = [...bytes.slice(cursor, end)];
      const additions: number[] = [];
      for (
        const [name, index] of [["qual:heap", heap], ["qual:base", heap + 1], [
          "qual:traffic",
          heap + 3,
        ]] as const
      ) {
        const encoded = new TextEncoder().encode(name);
        additions.push(...leb(encoded.length), ...encoded, 3, ...leb(index));
      }
      const memory = new TextEncoder().encode("qual:memory");
      additions.push(...leb(memory.length), ...memory, 2, ...leb(0));
      const next = [...leb(count + 4), ...rest, ...additions];
      parts.push(7, ...leb(next.length), ...next);
    } else parts.push(...bytes.slice(start, end));
    cursor = end;
  }
  return Uint8Array.from(parts);
}
function allocation(
  instance: WebAssembly.Instance,
  name: string,
  count: number,
) {
  const exported = instance.exports;
  const traffic = exported["qual:traffic"] as WebAssembly.Global | undefined;
  if (traffic === undefined) {
    return {
      traffic_block_bytes: 0,
      active_blocks: 0,
      active_requested_bytes: 0,
      arena_peak_bytes: 0,
      committed_bytes: 0,
    };
  }
  const before = Number(traffic.value);
  (exported[name] as CallableFunction)(count);
  const heap = Number((exported["qual:heap"] as WebAssembly.Global).value);
  const base = Number((exported["qual:base"] as WebAssembly.Global).value);
  const view = new DataView(
    (exported["qual:memory"] as WebAssembly.Memory).buffer,
  );
  let blocks = 0, requested_bytes = 0, cursor = view.getUint32(4, true);
  while (cursor !== 0 && cursor < heap) {
    const size = view.getUint32(cursor, true),
      requested = view.getUint32(cursor + 4, true);
    assert(size >= 16 && (size & (size - 1)) === 0);
    if (cursor >= base && requested !== 0) {
      blocks++;
      requested_bytes += requested;
    }
    cursor += size;
  }
  return {
    traffic_block_bytes: (Number(traffic.value) - before) >>> 0,
    active_blocks: blocks,
    active_requested_bytes: requested_bytes,
    arena_peak_bytes: heap - base,
    committed_bytes: view.byteLength,
  };
}
const input = `${output}/runtime.blot`;
await Deno.writeTextFile(input, source);
pins[input] = await hash(input);
const built = [];
for (const variant of variants) {
  built.push(await compile(variant, input, "runtime"));
}
const instances = built.map((item) =>
  new WebAssembly.Instance(new WebAssembly.Module(item.bytes))
);
const measured = built.map((item) =>
  new WebAssembly.Instance(new WebAssembly.Module(telemetry(item.bytes)))
);
const runtime: Record<string, unknown>[] = [];
let consumed = 0;
for (const name of ["outside", "inside"]) {
  for (const count of [0, 1, 128, 16384]) {
    let expected = count * 21;
    if (name === "inside") expected = 2 * count * (count - 1);
    for (const instance of instances) {
      const fn = instance.exports[name] as CallableFunction;
      for (let warm = 0; warm < 100; warm++) {
        assert.equal(fn(count) >>> 0, expected >>> 0);
      }
    }
    let repeats = 1;
    while (repeats < 131072) {
      const wall = performance.now();
      for (let i = 0; i < repeats; i++) {
        consumed ^= (instances[0].exports[name] as CallableFunction)(count);
      }
      if (performance.now() - wall >= 20) break;
      repeats *= 2;
    }
    const samples = variants.map(() => ({
      wall_us: [] as number[],
      cpu_us: [] as number[],
    }));
    for (let pair = 0; pair < 15; pair++) {
      const order = [0, 1];
      if ((pair & 1) !== 0) order.reverse();
      for (const index of order) {
        const fn = instances[index].exports[name] as CallableFunction;
        const cpu = cpuUsage(), wall = performance.now();
        for (let i = 0; i < repeats; i++) consumed ^= fn(count);
        const elapsed = performance.now() - wall, used = cpuUsage(cpu);
        samples[index].wall_us.push(elapsed * 1000 / repeats);
        samples[index].cpu_us.push((used.user + used.system) / repeats);
      }
    }
    for (let i = 0; i < variants.length; i++) {
      runtime.push({
        name,
        count,
        variant: variants[i].name,
        repeats,
        wasm_bytes: built[i].bytes.length,
        ...samples[i],
        wall_median_us: median(samples[i].wall_us),
        cpu_median_us: median(samples[i].cpu_us),
        allocation: allocation(measured[i], name, count),
      });
    }
  }
}
const compilation: Record<string, unknown>[] = [];
const main = `${output}/main.blot`, library = `${output}/library.blot`;
await Deno.writeTextFile(
  main,
  'import { sum } from "./library"\nentry const run = func (count: U32) => return sum count 21\n',
);
await Deno.writeTextFile(library, body);
pins[main] = await hash(main);
pins[library] = await hash(library);
for (let pair = 0; pair < 7; pair++) {
  const order = [...variants];
  if ((pair & 1) !== 0) order.reverse();
  for (const variant of order) {
    const fresh = await compile(variant, main, `fresh-${pair}`);
    compilation.push({
      pair,
      variant: variant.name,
      kind: "fresh",
      wall_ms: fresh.wall_ms,
      metrics: fresh.metrics,
    });
    const client = await createZigProjectCompiler({
      executable: variant.compiler,
      entry: main,
      prelude: null,
      cacheDirectory: false,
    });
    try {
      const edited = body.replace(
        "@u32.add self current",
        "@u32.add self (@u32.add current 1)",
      );
      for (
        const [kind, text] of [
          ["first", body],
          ["edit", edited],
          ["no_op", edited],
          ["failure", "const sum = @demand 42\n"],
          ["recovery", body],
        ] as const
      ) {
        const wall = performance.now();
        const result = await client.build({ sources: { [library]: text } });
        const wall_ms = performance.now() - wall;
        if (kind === "failure") assert(!result.success);
        else {
          assert(result.success, JSON.stringify(result));
          const instance = new WebAssembly.Instance(
            new WebAssembly.Module(result.bytes),
          );
          let factor = 21;
          if (kind === "edit" || kind === "no_op") factor = 22;
          assert.equal(
            (instance.exports.run as CallableFunction)(7),
            factor * 7,
          );
        }
        const row: Record<string, unknown> = {
          pair,
          variant: variant.name,
          kind,
          wall_ms,
          result,
        };
        if (result.success) {
          row.wasm_bytes = result.bytes.length;
          delete (result as { bytes?: Uint8Array }).bytes;
        }
        compilation.push(row);
      }
    } finally {
      await client.dispose();
    }
  }
}
await Deno.writeTextFile(
  `${output}/measurements.json`,
  JSON.stringify(
    { pins, loadStart, loadEnd: await load(), runtime, compilation, consumed },
    null,
    2,
  ),
);
console.log(
  JSON.stringify({
    output,
    runtime_rows: runtime.length,
    compilation_rows: compilation.length,
    loadStart,
    loadEnd: await load(),
  }),
);
