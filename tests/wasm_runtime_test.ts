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
