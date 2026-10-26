Deno.test("M01-M09 fixed memory and ownership guest laws", async () => {
// Executed guest tests, including trap paths on separate disposable instances.
const bytes = await Deno.readFile("/tmp/blot-k1-runtime.wasm");
const map = JSON.parse(await Deno.readTextFile("/tmp/blot-k1-runtime-map.json"));
if (!WebAssembly.validate(bytes)) throw new Error("runtime fixture fails Wasm validation");
function assert(value: unknown, message = "assertion failed"): asserts value {
  if (!value) throw new Error(message);
}
async function fresh() {
  const { instance } = await WebAssembly.instantiate(bytes);
  const ex = instance.exports as Record<string, (...args: number[]) => number> & { memory: WebAssembly.Memory };
  const words = new Uint32Array(ex.memory.buffer);
  const at = (address: number) => words[address / 4];
  const entry = (slot: number) => map.owners + (slot - 1) * 32;
  const out = map.frame;
  function reserve(size: number, owned = 0) {
    ex.reserve(out, size, owned);
    return { tag: at(out), error: at(out + 4), slot: at(out + 4), gen: at(out + 8) };
  }
  return { ex, words, at, entry, out, reserve };
}
const { ex, words, at, entry, out, reserve } = await fresh();
const initialBytes = ex.memory.buffer.byteLength;
const a = reserve(1), b = reserve(4096), c = reserve(4096), d = reserve(4096);
assert([a, b, c, d].every(x => x.tag === 0));
assert(a.slot === 1 && a.gen === 1);
assert(reserve(0xffffffff).error === 0, "overflow takes priority over slots");
assert(reserve(0).error === 1, "zero-size still needs a slot");
ex.place(out, a.slot, a.gen, 1, 4, 4);
assert(at(out) === 1 && at(out + 12) === 1 && at(entry(a.slot) + 12) === 0, "rounding slack is inaccessible");
ex.place(out, a.slot, a.gen, 0xffffffff, 4, 4);
assert(at(out) === 1 && at(out + 12) === 0, "placement overflow priority");
ex.place(out, a.slot, a.gen, 0xffffffff, 0, 1);
assert(at(out) === 0 && at(out + 12) === 0 && at(out + 16) === 0xffffffff);
ex.release(b.slot, b.gen, 1); ex.release(d.slot, d.gen, 1);
const before = new Uint8Array(ex.memory.buffer).slice(map.owners, map.frame);
assert(reserve(8192).error === 2, "fragmentation is not repaired implicitly");
assert(before.every((v, i) => v === new Uint8Array(ex.memory.buffer)[map.owners + i]), "failure leaves pool metadata untouched");
ex.release(c.slot, c.gen, 1);
const joined = reserve(8192);
assert(joined.slot === 2 && joined.gen === 2 && at(entry(2)) === map.pool + 4096);
ex.release(joined.slot, joined.gen, 1); ex.release(a.slot, a.gen, 1);
const zero = reserve(0);
assert(zero.tag === 0 && at(entry(zero.slot)) === 0 && at(entry(zero.slot) + 8) === 0);
ex.release(zero.slot, zero.gen, 1);
words[(entry(1) + 16) / 4] = 0xfffffffe;
const last = reserve(0);
assert(last.slot === 1 && last.gen === 0xffffffff);
ex.release(last.slot, last.gen, 1);
assert(at(entry(1) + 20) === 3);
const next = reserve(16);
assert(next.slot === 2 && next.tag === 0);
ex.place(out, next.slot, next.gen, 4, 4, 4);
assert(at(out) === 0 && at(out + 12) === map.pool && at(entry(next.slot) + 12) === 16);
ex.reset(next.slot, next.gen);
assert(at(entry(next.slot) + 12) === 0);
ex.release(next.slot, next.gen, 1);
const padding = reserve(7);
ex.place(out, padding.slot, padding.gen, 7, 1, 4);
assert(at(out) === 0 && at(entry(padding.slot) + 12) === 7);
ex.place(out, padding.slot, padding.gen, 0, 4, 4);
assert(at(out) === 0 && at(out + 12) === 0 && at(entry(padding.slot) + 12) === 7, "empty placement consumes no alignment padding");
ex.release(padding.slot, padding.gen, 1);
const owned = reserve(0, 1);
assert(owned.tag === 0 && at(entry(owned.slot) + 12) === 256);
words[(out + 32) / 4] = 42; words[(out + 36) / 4] = 9;
new Uint8Array(ex.memory.buffer).fill(255, at(entry(owned.slot)), at(entry(owned.slot)) + 256);
ex.seal(owned.slot, owned.gen, 77, out + 32, 2);
const root = ex.open(owned.slot, owned.gen, 77, 2);
assert(at(root) === 42 && at(root + 4) === 9);
for (let i = 2; i < 64; i++) assert(at(root + i * 4) === 0, "capsule tail is canonical zero");
ex.release(owned.slot, owned.gen, 2);
assert(ex.memory.buffer.byteLength === initialBytes, "memory stays fixed");

for (const fault of ["zero-slot", "stale", "wrong-state", "wrong-schema", "bad-alignment"]) {
  const t = await fresh();
  let trapped = false;
  try {
    if (fault === "zero-slot") t.ex.reset(0, 1);
    if (fault === "stale") { const h = t.reserve(0); t.ex.release(h.slot, h.gen, 1); t.ex.reset(h.slot, h.gen); }
    if (fault === "wrong-state") { const h = t.reserve(0, 1); t.ex.reset(h.slot, h.gen); }
    if (fault === "wrong-schema") { const h = t.reserve(0, 1); t.ex.seal(h.slot, h.gen, 3, t.out, 0); t.ex.open(h.slot, h.gen, 4, 0); }
    if (fault === "bad-alignment") { const h = t.reserve(8); t.ex.place(t.out, h.slot, h.gen, 1, 4, 1); }
  } catch (e) { trapped = e instanceof WebAssembly.RuntimeError; }
  assert(trapped, `${fault} must trap`);
  // Deliberately never resume a trapped instance.
}
console.log("K1_EXECUTED_WASM pool placement fragmentation retirement owned boundary-faults: PASS");

});

// Observe private memory only in this test's copy of the emitted module.
// Source scalar exports continue to expose no memory.
class FrameReader {
  at = 0;
  constructor(readonly bytes: Uint8Array) {}
  byte() { return this.bytes[this.at++]; }
  leb() {
    let n = 0, shift = 0;
    for (let i = 0; i < 5; i++) { const b = this.byte(); n += (b & 127) * 2 ** shift; if (b < 128) return n; shift += 7; }
    throw new Error("invalid LEB");
  }
  word() { const n = new DataView(this.bytes.buffer, this.bytes.byteOffset + this.at, 4).getUint32(0, true); this.at += 4; return n; }
  take(n: number) { const b = this.bytes.subarray(this.at, this.at + n); this.at += n; return b; }
}
function frameLeb(n: number): number[] {
  const bytes = [];
  do { const b = n & 127; n = Math.floor(n / 128); bytes.push(b | (n ? 128 : 0)); } while (n);
  return bytes;
}
function frameSections(bytes: Uint8Array): { id: number; bytes: Uint8Array }[] {
  const r = new FrameReader(bytes); r.at = 8;
  const sections = [];
  while (r.at < bytes.length) { const id = r.byte(); sections.push({ id, bytes: r.take(r.leb()) }); }
  return sections;
}
function frameObserved(bytes: Uint8Array): Uint8Array<ArrayBuffer> {
  const result = [...bytes.subarray(0, 8)];
  for (const section of frameSections(bytes)) {
    let payload = section.bytes;
    if (section.id === 7) {
      const r = new FrameReader(payload), count = r.leb(), name = new TextEncoder().encode("test.memory");
      payload = new Uint8Array([...frameLeb(count + 1), ...payload.subarray(r.at), ...frameLeb(name.length), ...name, 2, 0]);
    }
    result.push(section.id, ...frameLeb(payload.length), ...payload);
  }
  return new Uint8Array(result);
}
function frameInstructions(bytes: Uint8Array, local?: (index: number) => void): number[] {
  const r = new FrameReader(bytes), groups = r.leb(), instructions = [];
  for (let i = 0; i < groups; i++) { r.leb(); r.byte(); }
  while (r.at < bytes.length) {
    const op = r.byte(); instructions.push(op);
    if ([2, 3, 4].includes(op)) r.byte();
    else if ([32, 33, 34].includes(op)) { const index = r.leb(); local?.(index); }
    else if ([12, 13, 16, 65].includes(op)) r.leb();
    else if (op === 17 || [40, 42, 45, 54, 56].includes(op)) { r.leb(); r.leb(); }
    else if (op === 67) r.take(4);
    else if (op === 252) { const sub = r.leb(); r.leb(); if (sub === 10) r.leb(); }
  }
  return instructions;
}
Deno.test("M10 zero-frame calls omit frontier traffic and preserve mixed activation bounds", async () => {
  function check(ok: unknown, message: string): asserts ok { if (!ok) throw new Error(message); }
  const root = new URL("../", import.meta.url).pathname;
  for (const telemetry of [false, true]) {
    const output = root + `build/runtime-zero-frame-${telemetry}.wasm`;
    const built = await new Deno.Command(root + "build/blot", {
      cwd: root, args: ["build", "tests/runtime_zero_frame.blot", "--opt=off", "-o", output, ...(telemetry ? ["--telemetry"] : [])], stdout: "piped", stderr: "piped",
    }).output();
    check(built.success, new TextDecoder().decode(built.stderr));
    const bytes = await Deno.readFile(output), module = await WebAssembly.compile(bytes);
    const certificate = new FrameReader(new Uint8Array(WebAssembly.Module.customSections(module, "blot.k1.certificate")[0]));
    certificate.take(8 + 96);
    const geometry = Array.from({ length: 18 }, () => certificate.word());
    certificate.take(8);
    const section = frameSections(bytes).find(s => s.id === 10)!;
    const code = new FrameReader(section.bytes), bodies = Array.from({ length: code.leb() }, () => code.take(code.leb()));
    let zeroBodies = 0, framedBodies = 0, largestFrame = 0, zeroLoads = 0;
    for (let i = 0, count = certificate.word(); i < count; i++) {
      const index = certificate.word(); certificate.word(); const role = certificate.word(); certificate.word();
      const own = certificate.word(); certificate.take(8 + 32);
      certificate.take(certificate.word() * 4); certificate.take(certificate.word() * 8);
      if (role !== 2) continue;
      const ops = frameInstructions(bodies[index]);
      if (own === 0) {
        zeroBodies++;
        if (!telemetry) {
          check(!ops.some(op => [54, 56].includes(op)), "zero-frame bodies must have no frontier stores");
          zeroLoads += ops.filter(op => [40, 42, 45].includes(op)).length;
        }
      } else { framedBodies++; largestFrame = Math.max(largestFrame, own); }
    }
    check(zeroBodies === 4 && framedBodies === 1, "mixed fixture must exercise zero-frame callers, captured callees and one framed activation");
    if (!telemetry) check(zeroLoads === 1, "only the captured scalar is loaded; zero-frame bodies do not load the frontier");
    const instance = await WebAssembly.instantiate(await WebAssembly.compile(frameObserved(bytes)));
    const ex = instance.exports, memory = ex["test.memory"] as WebAssembly.Memory, data = new DataView(memory.buffer);
    const frontier = geometry[2] + 4, incoming = 28;
    data.setUint32(frontier, incoming, true);
    const mixed = ex.mixed as (n: number) => number, zero = ex.zero as (n: number) => number;
    for (const n of [0, 1, 40, 0x7fffffff, 0xffffffff]) {
      check(mixed(n) >>> 0 === (n + 4) >>> 0 && zero(n) >>> 0 === (n + 1) >>> 0, "mixed call result");
      check(data.getUint32(frontier, true) === incoming, "every normal return preserves the incoming frontier");
    }
    if (telemetry) {
      const word = ex["blot.telemetry"] as (n: number) => number;
      check(word(8 * 2) === incoming + largestFrame && word(8 * 2 + 1) === 0, "scratch high-water measures actual mixed live bytes");
      check(word(11 * 2) === 30, "zero-frame source calls remain counted");
    }
    // The full public allowance remains mandatory even though actual frame use
    // is smaller. A trapped instance is discarded immediately.
    data.setUint32(frontier, geometry[8] - 128 + 4, true);
    let trapped = false;
    try { mixed(0); } catch (error) { trapped = error instanceof WebAssembly.RuntimeError; }
    check(trapped && data.getUint32(frontier, true) === geometry[8] - 128 + 4, "wrapper preflight rejects before frame mutation");
  }
});

Deno.test("M10 zero-frame generic Unit adapters preserve frontier and telemetry", async () => {
  function check(ok: unknown, message: string): asserts ok { if (!ok) throw new Error(message); }
  const root = new URL("../", import.meta.url).pathname;
  for (const telemetry of [false, true]) {
    const output = root + `build/runtime-zero-adapter-${telemetry}.wasm`;
    const built = await new Deno.Command(root + "build/blot", {
      cwd: root, args: ["build", "tests/runtime_zero_frame_adapter.blot", "--opt=off", "-o", output, ...(telemetry ? ["--telemetry"] : [])], stdout: "piped", stderr: "piped",
    }).output();
    check(built.success, new TextDecoder().decode(built.stderr));
    const bytes = await Deno.readFile(output), module = await WebAssembly.compile(bytes);
    const certificate = new FrameReader(new Uint8Array(WebAssembly.Module.customSections(module, "blot.k1.certificate")[0]));
    certificate.take(8 + 96);
    const geometry = Array.from({ length: 18 }, () => certificate.word()); certificate.take(8);
    const code = new FrameReader(frameSections(bytes).find(s => s.id === 10)!.bytes);
    const bodies = Array.from({ length: code.leb() }, () => code.take(code.leb()));
    let adapters = 0, sourceFrame = 0;
    for (let i = 0, count = certificate.word(); i < count; i++) {
      const index = certificate.word(); certificate.word(); const role = certificate.word(); certificate.word();
      const own = certificate.word(); certificate.take(8 + 32);
      certificate.take(certificate.word() * 4); certificate.take(certificate.word() * 8);
      if (role === 2) sourceFrame += own;
      if (role !== 6) continue;
      adapters++; check(own === 0, "Unit ABI adapter needs no spill frame");
      if (!telemetry) {
        const ops = frameInstructions(bodies[index]);
        check(!ops.some(op => [40, 42, 45, 54, 56].includes(op)), "zero-frame Unit adapter has no frontier loads or stores");
        check(ops.filter(op => op === 16).length === 1, "adapter still invokes the one shared generic body");
      }
    }
    check(adapters === 1 && sourceFrame > 0, "fixture exercises one adapter and framed generic source execution");
    const instance = await WebAssembly.instantiate(await WebAssembly.compile(frameObserved(bytes)));
    const ex = instance.exports, data = new DataView((ex["test.memory"] as WebAssembly.Memory).buffer);
    const frontier = geometry[2] + 4, incoming = 28;
    data.setUint32(frontier, incoming, true);
    for (let repeat = 0; repeat < 10; repeat++) {
      check((ex.unit as () => number)() === 42, "generic Unit callback executes");
      check(data.getUint32(frontier, true) === incoming, "adapter and generic source restore the incoming frontier");
    }
    if (telemetry) {
      const word = ex["blot.telemetry"] as (n: number) => number;
      check(word(8 * 2) === incoming + sourceFrame && word(8 * 2 + 1) === 0, "zero-frame adapter preserves actual scratch attribution");
      check(word(11 * 2) === 20, "only the two source activations are counted per invocation");
    }
  }
});

Deno.test("C07/M10 generic arguments borrow immutable slots and return trees avoid dispatch", async () => {
  function check(ok: unknown, message: string): asserts ok { if (!ok) throw new Error(message); }
  const root = new URL("../", import.meta.url).pathname;
  for (const telemetry of [false, true]) {
    const output = root + `build/runtime-lowering-${telemetry}.wasm`;
    const built = await new Deno.Command(root + "build/blot", {
      cwd: root, args: ["build", "tests/runtime_lowering.blot", "--opt=off", "-o", output, ...(telemetry ? ["--telemetry"] : [])], stdout: "piped", stderr: "piped",
    }).output();
    check(built.success, new TextDecoder().decode(built.stderr));
    const bytes = await Deno.readFile(output), module = await WebAssembly.compile(bytes);
    const certificate = new FrameReader(new Uint8Array(WebAssembly.Module.customSections(module, "blot.k1.certificate")[0]));
    certificate.take(8 + 96);
    const geometry = Array.from({ length: 18 }, () => certificate.word()); certificate.take(8);
    const code = new FrameReader(frameSections(bytes).find(s => s.id === 10)!.bytes);
    const bodies = Array.from({ length: code.leb() }, () => code.take(code.leb()));
    let sources = 0, generic = 0, actualFrame = 0;
    for (let i = 0, count = certificate.word(); i < count; i++) {
      const index = certificate.word(); certificate.word(); const role = certificate.word(); certificate.word();
      const own = certificate.word(), frame = certificate.word(); certificate.take(4 + 32);
      certificate.take(certificate.word() * 4); certificate.take(certificate.word() * 8);
      if (role !== 2) continue;
      sources++; actualFrame += own;
      const ops = frameInstructions(bodies[index]);
      check(!ops.includes(3), "early-return tree uses direct structured branches, never a dispatch loop");
      if (!telemetry && ops.includes(252)) {
        generic++;
        check(own === 0 && frame >= 256, "generic input slot is borrowed while baseline frame certificate stays conservative");
        check(ops.filter(op => op === 252).length === 1, "generic identity performs only its required result copy");
        check(!ops.includes(54) && !ops.includes(56), "generic identity has no entry or exit frontier stores");
      }
    }
    check(sources === 3 && (telemetry || generic === 1), "fixture retains exactly one generic body and two entrypoints");
    const instance = await WebAssembly.instantiate(await WebAssembly.compile(frameObserved(bytes)));
    const ex = instance.exports, data = new DataView((ex["test.memory"] as WebAssembly.Memory).buffer);
    const frontier = geometry[2] + 4, incoming = 28;
    data.setUint32(frontier, incoming, true);
    for (const n of [0, 1, 40, 0x7fffffff, 0xfffffffc, 0xfffffffd, 0xfffffffe, 0xffffffff]) {
      check((ex.run as (n: number) => number)(n) >>> 0 === n, "generic input forwarded through uniform ABI");
      check((ex.guarded as (n: number) => number)(n) >>> 0 === Math.min(n + 3, 0xffffffff), "all early-return paths preserve checked arithmetic");
      check(data.getUint32(frontier, true) === incoming, "borrowed parameter and branch tree restore the frontier");
    }
    if (telemetry) {
      const word = ex["blot.telemetry"] as (n: number) => number;
      check(word(8 * 2) === incoming + actualFrame, "generic parameter alias does not charge unused maximum-sized storage");
      check(word(9 * 2) === 64 && word(10 * 2) === 32, "only caller scalar materialization and the required result copy initialize bytes");
      check(word(11 * 2) === 24 && word(12 * 2) === 0, "source calls and zero logical loop iterations remain exact");
    }
  }
});

Deno.test("C07 exact machine-local compaction retains F32 groups and nested dictionary scratch", async () => {
  function check(ok: unknown, message: string): asserts ok { if (!ok) throw new Error(message); }
  const root = new URL("../", import.meta.url).pathname;
  for (const telemetry of [false, true]) {
    const output = root + `build/runtime-locals-${telemetry}.wasm`;
    const built = await new Deno.Command(root + "build/blot", {
      cwd: root, args: ["build", "tests/runtime_local_compaction.blot", "--opt=off", "-o", output, ...(telemetry ? ["--telemetry"] : [])], stdout: "piped", stderr: "piped",
    }).output();
    check(built.success, new TextDecoder().decode(built.stderr));
    const bytes = await Deno.readFile(output), module = await WebAssembly.compile(bytes), sections = frameSections(bytes);
    const types = new FrameReader(sections.find(s => s.id === 1)!.bytes), parameters: number[] = [];
    for (let i = 0, count = types.leb(); i < count; i++) {
      check(types.byte() === 0x60, "function type");
      const n = types.leb(); parameters.push(n); types.take(n); types.take(types.leb());
    }
    const functions = new FrameReader(sections.find(s => s.id === 3)!.bytes);
    const signatures = Array.from({ length: functions.leb() }, () => functions.leb());
    const code = new FrameReader(sections.find(s => s.id === 10)!.bytes);
    const bodies = Array.from({ length: code.leb() }, () => code.take(code.leb()));
    const certificate = new FrameReader(new Uint8Array(WebAssembly.Module.customSections(module, "blot.k1.certificate")[0]));
    certificate.take(8 + 96 + 72 + 8);
    let sources = 0, floatLocals = 0;
    for (let i = 0, count = certificate.word(); i < count; i++) {
      const index = certificate.word(); certificate.word(); const role = certificate.word(); certificate.word();
      certificate.take(12 + 32); certificate.take(certificate.word() * 4); certificate.take(certificate.word() * 8);
      if (role !== 2) continue;
      sources++;
      const body = bodies[index], declarations = new FrameReader(body), locals: number[] = [];
      for (let group = 0, count = declarations.leb(); group < count; group++) {
        const n = declarations.leb(), type = declarations.byte();
        for (let j = 0; j < n; j++) locals.push(type);
        if (type === 0x7d) floatLocals += n;
      }
      const used = new Set<number>(); frameInstructions(body, index => used.add(index));
      const args = parameters[signatures[index]];
      check(locals.every((_, index) => used.has(args + index)), "every declared source local is referenced after remapping");
      check([...used].every(index => index < args + locals.length), "all remapped local references remain in range");
      check(locals.length < 69, "fixture does not retain the fixed 69-local scratch reservation");
    }
    check(sources === 3 && floatLocals > 0, "fixture covers one nested generic body and scalar U32/F32 entrypoints");
    const ex = (await WebAssembly.instantiate(module)).exports;
    for (const n of [0, 1, 40, 0x7fffffff, 0xffffffff]) {
      check((ex.run as (n: number) => number)(n) >>> 0 === Math.imul(n, 2) >>> 0, "U32 remapping across nested sums");
    }
    for (const n of [0, -0, 1.25, -1.25, Infinity, -Infinity, NaN]) {
      const result = (ex.run_float as (n: number) => number)(n), expected = Math.fround(Math.fround(n) + Math.fround(n));
      check(Object.is(result, expected), "F32 groups preserve signed zero, infinities, NaN and rounded addition");
    }
    if (telemetry) {
      const word = ex["blot.telemetry"] as (n: number) => number;
      check(word(11 * 2) === 24 && word(12 * 2) === 0, "nested generic source entries remain exact after scratch remapping");
      check(word(8 * 2) > 0, "instrumented scratch locals remain live and correctly typed");
    }
  }
});

Deno.test("C07 compacted machine locals retain implicit I32 and F32 zero initialization", async () => {
  const { instance } = await WebAssembly.instantiate(await Deno.readFile("/tmp/blot-k1-local-init.wasm"));
  const zero = instance.exports.zero as (integer: number, float: number) => number;
  for (const n of [0, -0, 1.25, -1.25, Infinity, -Infinity, NaN]) {
    if (!Object.is(zero(0xffffffff, n), 0)) throw new Error("unassigned compacted I32/F32 locals must start at positive zero");
  }
});
