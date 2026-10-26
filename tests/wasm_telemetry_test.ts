import { Blot } from "../host/blot.ts";
const root = new URL("../", import.meta.url).pathname;
function assert(ok: unknown, message = "telemetry assertion failed"): asserts ok { if (!ok) throw new Error(message); }
function counter(exports: WebAssembly.Exports, id: number) {
  const word = exports["blot.telemetry"] as (index: number) => number;
  return BigInt(word(id * 2) >>> 0) | (BigInt(word(id * 2 + 1) >>> 0) << 32n);
}
Deno.test("K1-C13 runtime telemetry counts failures cleanup and 64-bit carry", async () => {
  const { instance } = await WebAssembly.instantiate(await Deno.readFile("/tmp/blot-k1-runtime-telemetry.wasm"));
  const map = JSON.parse(await Deno.readTextFile("/tmp/blot-k1-runtime-telemetry-map.json"));
  const ex = instance.exports as Record<string, (...args: number[]) => number> & { memory: WebAssembly.Memory };
  const words = new Uint32Array(ex.memory.buffer), out = map.frame;
  ex.reserve(out, 1, 0); assert(words[out / 4] === 0); const slot = words[out / 4 + 1], generation = words[out / 4 + 2];
  ex.reserve(out, 0xffffffff, 0); assert(words[out / 4] === 1);
  ex.reset(slot, generation); ex.release(slot, generation, 1);
  assert(counter(ex, 0) === 2n && counter(ex, 1) === 1n && counter(ex, 2) === 1n);
  assert(counter(ex, 3) === 1n && counter(ex, 4) === 1n);
  assert(counter(ex, 5) === 0n && counter(ex, 6) === 4096n);
  words[(map.control + 16) / 4] = 0xffffffff; words[(map.control + 20) / 4] = 7;
  ex.reserve(out, 0, 0); assert(counter(ex, 0) === 8n << 32n, "carry must preserve cumulative counts above U32");
  ex.release(words[out / 4 + 1], words[out / 4 + 2], 1); assert(counter(ex, 5) === 0n);
  ex.reserve(out, 4, 1); const ownedSlot = words[out / 4 + 1], ownedGeneration = words[out / 4 + 2];
  words[(out + 64) / 4] = 42; ex.seal(ownedSlot, ownedGeneration, 17, out + 64, 1);
  assert(counter(ex, 9) === 256n && counter(ex, 10) === 4n);
  ex.release(ownedSlot, ownedGeneration, 2); assert(counter(ex, 5) === 0n);
});
async function compile(source: string, name: string, telemetry: boolean, bridge?: string) {
  const output = `build/telemetry-${name}.wasm`;
  const args = ["build", source, "-o", output, "--opt=off"];
  if (telemetry) args.push("--telemetry");
  if (bridge) args.push(`--bridge-config=${bridge}`);
  const result = await new Deno.Command(root + "build/blot", { cwd: root, args, stdout: "piped", stderr: "piped" }).output();
  assert(result.success, new TextDecoder().decode(result.stderr));
  const bytes = await Deno.readFile(root + output), module = await WebAssembly.compile(bytes);
  return { bytes, module, instance: await WebAssembly.instantiate(module) };
}
Deno.test("K1-C13 instrumented counted loop preserves results and isolates timing mode", async () => {
  const plain = await compile("examples/counted_loop.blot", "loop-plain", false);
  const traced = await compile("examples/counted_loop.blot", "loop-traced", true);
  assert(!("blot.telemetry" in plain.instance.exports));
  assert(!("memory" in traced.instance.exports), "diagnostic scalar export must not expose memory");
  const runPlain = plain.instance.exports.count as () => number, runTrace = traced.instance.exports.count as () => number;
  for (let i = 0; i < 3; i++) assert(runPlain() === 10 && runTrace() === 10);
  assert(counter(traced.instance.exports, 11) === 3n && counter(traced.instance.exports, 12) === 30n);
  assert(counter(traced.instance.exports, 0) === 0n && counter(traced.instance.exports, 7) === 4n);
  const section = WebAssembly.Module.customSections(traced.module, "blot.k1.manifest");
  const manifest = JSON.parse(new TextDecoder().decode(section[0]));
  assert(manifest.telemetry.counter_bits === 64 && manifest.telemetry.counters.length === 13);
});
Deno.test("K1-C13 particle telemetry measures copies iterations and normal cleanup", async () => {
  const { module, instance } = await compile("examples/particles.blot", "particle", true, "examples/particles.json");
  const manifest = JSON.parse(new TextDecoder().decode(WebAssembly.Module.customSections(module, "blot.k1.manifest")[0]));
  const ex = instance.exports as Record<string, (...args: number[]) => number> & { memory: WebAssembly.Memory };
  const data = new DataView(ex.memory.buffer), entry = manifest.exports[0], input = manifest.memory.ingress, output = manifest.memory.egress;
  const n = 3, source = entry.fields.find((f: { name: string }) => f.name === "source"), dt = entry.fields.find((f: { name: string }) => f.name === "dt");
  for (let i = 0; i < 8; i++) data.setUint32(input + i * 4, 0, true);
  data.setUint32(input, 0x4b310001, true); data.setUint32(input + 4, entry.id, true);
  data.setUint32(input + 12, entry.fixed_bytes + n * 16, true);
  data.setUint32(input + 32 + source.offset, n, true); data.setUint32(input + 36 + source.offset, entry.fixed_bytes, true);
  data.setFloat32(input + 32 + dt.offset, 0.5, true);
  for (let i = 0; i < n; i++) for (let j = 0; j < 4; j++) data.setFloat32(input + 32 + entry.fixed_bytes + i * 16 + j * 4, i + j, true);
  assert(ex.blot_call(entry.id, 32 + entry.fixed_bytes + n * 16, 32) === 0);
  assert(data.getUint32(output + 12, true) === 32);
  assert(counter(ex, 0) === 1n && counter(ex, 1) === 1n && counter(ex, 2) === 0n);
  assert(counter(ex, 4) === 1n && counter(ex, 5) === 0n && counter(ex, 6) > 0n);
  assert(counter(ex, 11) === 1n && counter(ex, 12) === 3n);
  assert(counter(ex, 7) === 32n && counter(ex, 8) > 0n && counter(ex, 9) >= 72n && counter(ex, 10) >= 72n);
  assert(ex.blot_call(entry.id, 32 + entry.fixed_bytes + n * 16, 0) === 2);
  assert(counter(ex, 0) === 2n && counter(ex, 4) === 2n && counter(ex, 5) === 0n && counter(ex, 12) === 6n);
});

Deno.test("K1-C13 diagnostic exports cannot collide with source identifiers", async () => {
  const { instance } = await compile("tests/runtime_telemetry_name.blot", "name", true);
  assert((instance.exports.blot_telemetry as () => number)() === 42);
  assert(counter(instance.exports, 11) === 1n);
});
Deno.test("K1-C13 full try_append evaluates its unused element exactly once", async () => {
  const { instance } = await compile("tests/runtime_try_append.blot", "append-evaluation", true);
  const run = instance.exports.run as () => number;
  assert(run() === 99);
  assert(counter(instance.exports, 11) === 3n, "entry, builder exercise and one element evaluation");
  assert(counter(instance.exports, 0) === 1n && counter(instance.exports, 4) === 1n && counter(instance.exports, 5) === 0n);
});

Deno.test("K1-C13 host telemetry snapshots are immutable copies with private memory", async () => {
  const plain = await compile("examples/particles.blot", "host-plain", false, "examples/particles.json");
  const traced = await compile("examples/particles.blot", "host-traced", true, "examples/particles.json");
  const defaultHost = await Blot.load(plain.bytes), host = await Blot.load(traced.bytes);
  assert(defaultHost.telemetry() === null);
  const before = host.telemetry(); assert(before && Object.isFrozen(before) && before.source_calls === 0n);
  const source = [{ x: 2, y: 3, vx: 4, vy: 6 }, { x: 1, y: 2, vx: 8, vy: 10 }];
  const result = host.invoke("project", { source, dt: 0.5 }); assert(result.status === "Ok");
  const first = host.telemetry(); assert(first && first !== before && Object.isFrozen(first));
  assert(first.backing_reservations === 1n && first.backing_successes === 1n && first.backing_failures === 0n);
  assert(first.region_releases === 1n && first.backing_live_bytes === 0n && first.source_calls === 1n && first.loop_iterations === 2n);
  assert(first.result_high_water_bytes === 24n && first.scratch_high_water_bytes > 0n);
  assert(Object.values(first).every(value => typeof value === "bigint"));
  let rejected = false;
  try { (first as Record<string, bigint>).source_calls = 999n; } catch { rejected = true; }
  assert(rejected && before.source_calls === 0n && first.source_calls === 1n);
  assert(host.invoke("project", { source: [], dt: 0.5 }).status === "Ok");
  const second = host.telemetry(); assert(second && second.source_calls === 2n && first.source_calls === 1n);
  assert(!("memory" in host) && !("instance" in host) && !host.poisoned);
});
