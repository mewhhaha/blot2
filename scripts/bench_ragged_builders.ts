// deno run -A scripts/bench_ragged_builders.ts BASELINE CANDIDATE STD OUTPUT
import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { cpuUsage } from "node:process";
import { createZigProjectCompiler } from "../compiler/zig_project_client.ts";

assert(Deno.args.length === 4);
const [baseline, candidate, stdRoot, output] = Deno.args.map((path) =>
  resolve(path)
);
await Deno.mkdir(output, { recursive: true });
const variants = [
  { name: "ordinary", compiler: baseline },
  { name: "ragged", compiler: candidate },
];
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
for await (const entry of Deno.readDir(stdRoot)) {
  if (entry.isFile && entry.name.endsWith(".blot")) {
    pins[`${stdRoot}/${entry.name}`] = await hash(`${stdRoot}/${entry.name}`);
  }
}
const load = async () => (await Deno.readTextFile("/proc/loadavg")).trim();
const loadStart = await load();
pins[new URL(import.meta.url).pathname] = await hash(
  new URL(import.meta.url).pathname,
);
function source(count: number): string {
  return `let inputs = @array.generate ${count} (fn i => i)
let rows2 = @array.generate ${count} (fn i => {a:i,b:i+1})
let rows4 = @array.generate ${count} (fn i => {a:i,b:i+1,c:i+2,d:i+3})
let refs = @array.generate ${count} (fn i => @array.fill 2 i)
let list_inputs = @list.from_array inputs
let list_rows2 = @list.from_array rows2
entry const triangle_array = fn count => do:
  let values: List U32 = []
  for x in 0..count:
    for y in 0..x:
      values := [...self, x * 10 + y]
  return @array.from_list values
const list = fn count => do:
  let values: List U32 = []
  for x in 0..count:
    for y in 0..x:
      values := [...self, x * 10 + y]
  return values
entry const triangle_list = fn count => @list.length (list count)
entry const filter_none = fn (count: U32) => #[x | x <- inputs, #False]
entry const filter_half = fn count => #[x | x <- inputs, @u32.lt x (@u32.shr count 1)]
entry const filter_all = fn (count: U32) => #[x | x <- inputs, #True]
entry const packed2 = fn count => @array.length (#[row | row <- rows2, row.a < count])
entry const packed4 = fn count => @array.length (#[row | row <- rows4, row.a < count])
entry const references = fn (count: U32) => @array.length (#[value | value <- refs, #True])
entry const list_packed2 = fn count => @array.length (#[row | row <- list_rows2, row.a < count])
entry const list_nested = fn (count: U32) => #[y | x <- list_inputs, y <- list_inputs, y < x]
entry const exhausted = fn (count: U32) => do:
  let result: List U32 = []
  for x in 0..count:
    if #False:
      result := [...self, x]
  return @array.from_list result
`;
}
async function compile(
  variant: typeof variants[number],
  input: string,
  name: string,
) {
  const path = `${output}/${name}-${variant.name}.wasm`;
  const started = performance.now();
  const result = await new Deno.Command(variant.compiler, {
    args: [
      "build",
      input,
      path,
      "--std-root",
      stdRoot,
      "--prelude",
      `${stdRoot}/prelude.blot`,
    ],
    stdout: "piped",
    stderr: "piped",
    env: { BLOT_CACHE_DIR: "" },
  }).output();
  const wall_ms = performance.now() - started;
  const log = new TextDecoder().decode(result.stdout);
  assert(result.success, log + new TextDecoder().decode(result.stderr));
  const metrics = log.trim().split("\n").map((line) => JSON.parse(line)).find((
    item,
  ) => item.kind === "compilation");
  assert(metrics.success && metrics.memory.live_bytes === 0);
  await Deno.writeTextFile(`${output}/${name}-${variant.name}.jsonl`, log);
  return { bytes: await Deno.readFile(path), metrics, wall_ms };
}
const median = (values: number[]) =>
  [...values].sort((left, right) =>
    left - right
  )[Math.floor(values.length / 2)];
const p90 = (values: number[]) =>
  [...values].sort((left, right) =>
    left - right
  )[Math.floor(values.length * .9)];
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
      assert(heap >= 0);
    }
    if (section === 7) {
      assert(heap !== undefined);
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
      const next = [...leb(count + 3), ...rest, ...additions];
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
  const traffic = exported["qual:traffic"] as WebAssembly.Global;
  const before = Number(traffic.value);
  (exported[name] as CallableFunction)(count);
  const heap = Number((exported["qual:heap"] as WebAssembly.Global).value);
  const base = Number((exported["qual:base"] as WebAssembly.Global).value);
  const view = new DataView(
    (exported["blot:memory"] as WebAssembly.Memory).buffer,
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
const runtime: Record<string, unknown>[] = [];
let consumed = 0;
for (const count of [0, 1, 8, 32, 128, 256, 16384]) {
  const input = `${output}/runtime-${count}.blot`;
  await Deno.writeTextFile(input, source(count));
  pins[input] = await hash(input);
  const built = [];
  for (const variant of variants) {
    built.push(await compile(variant, input, `runtime-${count}`));
  }
  const instances = [];
  const measured = [];
  for (const item of built) {
    instances.push((await WebAssembly.instantiate(item.bytes)).instance);
    measured.push(
      new WebAssembly.Instance(new WebAssembly.Module(telemetry(item.bytes))),
    );
  }
  let names = [
    "triangle_array",
    "triangle_list",
    "filter_none",
    "filter_half",
    "filter_all",
    "packed2",
    "packed4",
    "references",
    "list_packed2",
    "list_nested",
  ];
  if (count === 16384) {
    names = names.slice(2).filter((name) => name !== "list_nested");
  }
  if (count === 0) names.push("exhausted");
  for (const name of names) {
    let argument = count;
    if (name === "exhausted") argument = 1_048_577;
    let selected = count;
    let candidates = argument;
    if (name.startsWith("triangle")) {
      selected = count * (count - 1) / 2;
      candidates = selected;
    }
    if (name === "list_nested") {
      selected = count * (count - 1) / 2;
      candidates = count * count;
    }
    if (name === "filter_none") selected = 0;
    if (name === "exhausted") selected = 0;
    if (name === "filter_half") selected = count >>> 1;
    for (const instance of instances) {
      const fn = instance.exports[name] as CallableFunction;
      for (let warm = 0; warm < 16; warm++) consumed ^= fn(argument);
      const pointer = fn(argument);
      const view = new DataView(
        (instance.exports["blot:memory"] as WebAssembly.Memory).buffer,
      );
      if (
        ["triangle_list", "packed2", "packed4", "references", "list_packed2"]
          .includes(name)
      ) {
        assert(pointer === selected);
      } else assert(view.getUint32(pointer, true) === selected);
    }
    let repeats = 1;
    while (repeats < 10000) {
      const start = performance.now();
      for (let i = 0; i < repeats; i++) {
        consumed ^= (instances[0].exports[name] as CallableFunction)(argument);
      }
      if (performance.now() - start >= 10) break;
      repeats *= 2;
    }
    const samples: { wall_us: number[]; cpu_us: number[] }[] = variants.map(
      () => ({ wall_us: [], cpu_us: [] }),
    );
    for (let pair = 0; pair < 15; pair++) {
      const order = [0, 1];
      if ((pair & 1) !== 0) order.reverse();
      for (const index of order) {
        const fn = instances[index].exports[name] as CallableFunction;
        const cpu = cpuUsage(), wall = performance.now();
        for (let i = 0; i < repeats; i++) consumed ^= fn(argument);
        const elapsed = performance.now() - wall, used = cpuUsage(cpu);
        samples[index].wall_us.push(elapsed * 1000 / repeats);
        samples[index].cpu_us.push((used.user + used.system) / repeats);
      }
    }
    for (let i = 0; i < variants.length; i++) {
      runtime.push({
        count,
        argument,
        candidates,
        selected,
        generator_visits: candidates +
          count * Number(name.startsWith("triangle") || name === "list_nested"),
        depth: 1 +
          Number(name.startsWith("triangle") || name === "list_nested"),
        row_words: { packed2: 2, packed4: 4, list_packed2: 2 }[name] ?? 1,
        name,
        variant: variants[i].name,
        repeats,
        samples: samples[i],
        wall_median_us: median(samples[i].wall_us),
        wall_p90_us: p90(samples[i].wall_us),
        cpu_median_us: median(samples[i].cpu_us),
        allocation: allocation(measured[i], name, argument),
        counters: built[i].metrics.work_counters,
      });
    }
  }
  await Deno.writeTextFile(
    `${output}/runtime.json`,
    JSON.stringify(
      { pins, loadStart, loadEnd: await load(), runtime, consumed },
      null,
      2,
    ),
  );
}
const compilation: Record<string, unknown>[] = [];
const input = `${output}/compile.blot`;
const original = source(128) +
  "const saved = list 32\nentry const staged = fn () => @array.length (@array.from_list saved)\n";
await Deno.writeTextFile(input, original);
for (let pair = 0; pair < 7; pair++) {
  const order = [...variants];
  if ((pair & 1) !== 0) order.reverse();
  for (const variant of order) {
    const fresh = await compile(variant, input, `fresh-${pair}`);
    compilation.push({
      pair,
      variant: variant.name,
      kind: "fresh",
      wall_ms: fresh.wall_ms,
      metrics: fresh.metrics,
    });
    const client = await createZigProjectCompiler({
      executable: variant.compiler,
      entry: input,
      stdRoot,
      prelude: `${stdRoot}/prelude.blot`,
      cacheDirectory: false,
    });
    try {
      for (
        const [kind, text] of [
          ["first", original],
          ["edit", original.replaceAll("x * 10 + y", "x * 11 + y")],
          ["no_op", original.replaceAll("x * 10 + y", "x * 11 + y")],
          ["failure", "entry const broken = absent\n"],
          ["recovery", original],
        ] as const
      ) {
        const wall = performance.now();
        const result = await client.build({ sources: { [input]: text } });
        const wall_ms = performance.now() - wall;
        if (kind === "failure") assert(!result.success);
        else assert(result.success, JSON.stringify(result));
        compilation.push({
          pair,
          variant: variant.name,
          kind,
          wall_ms,
          result,
        });
      }
    } finally {
      await client.dispose();
    }
  }
}
// Avoid embedding repeated Wasm byte arrays in the durable cost evidence.
for (const row of compilation) {
  const result = row.result as { bytes?: Uint8Array } | undefined;
  if (result?.bytes) {
    row.wasm_bytes = result.bytes.length;
    delete result.bytes;
  }
}
await Deno.writeTextFile(
  `${output}/compilation.json`,
  JSON.stringify(
    { pins, loadStart, loadEnd: await load(), compilation },
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
