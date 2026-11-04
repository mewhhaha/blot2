import { strict as assert } from "node:assert";
const compiler = Deno.args[0] ??
  new URL("../../compiler/zig-out/bin/blotc", import.meta.url).pathname;
const fixture = new URL(
  "../region-owner-publication-fixture.wasm",
  new URL(compiler, `file://${Deno.cwd()}/`),
);
const bytes = await Deno.readFile(fixture);
const module = new WebAssembly.Module(bytes);
function runtime() {
  const e = new WebAssembly.Instance(module).exports;
  const memory = e["blot:memory"] as WebAssembly.Memory;
  const call = (name: string, ...args: number[]) =>
    Number((e[name] as CallableFunction)(...args)) >>> 0;
  const global = (name: string) =>
    Number((e[name] as WebAssembly.Global).value);
  const count = (name: string) => global(`blot:rc_${name}`);
  const word = (p: number) => new DataView(memory.buffer).getUint32(p, true);
  const put = (p: number, value: number) =>
    new DataView(memory.buffer).setUint32(p, value, true);
  (e.root_enabled as WebAssembly.Global).value = 3;
  (e.rc_enabled as WebAssembly.Global).value = 1;
  const balanced = () => {
    assert.equal(global("root_count"), 0);
    assert.equal(count("leases"), 0);
  };
  return { e, memory, call, global, count, word, put, balanced };
}
Deno.test("interior result publication moves its real owner before closing the producer frame", () => {
  const r = runtime();
  r.call("root_open");
  r.call("root_open");
  const owner = r.call("allocate"), member = owner + 20;
  r.put(member, 42);
  assert.equal(r.call("project", member, owner), owner);
  r.call("close", member, owner);
  assert.equal(r.count("destroyed"), 0);
  assert.equal(r.word(member), 42);
  assert.equal(r.word(owner - 16), 1);
  assert.equal(r.count("retains"), 0);
  r.call("root_close", 0);
  r.balanced();
  assert.equal(r.count("destroyed"), 1);
});
Deno.test("interior aliases and changed carry slots own the enclosing region once", () => {
  const r = runtime();
  r.call("root_open");
  const owner = r.call("allocate");
  const slot = r.call("root_reserve");
  r.call("store", slot, owner + 36, owner);
  assert.equal(r.word(slot), owner);
  assert.equal(r.word(owner - 16), 2);
  r.call("store", slot, owner + 44, owner);
  assert.equal(r.count("retains"), 1);
  assert.equal(r.word(owner - 16), 2);
  r.call("store", slot, 0, owner);
  assert.equal(r.word(owner - 16), 1);
  r.call("root_close", 0);
  r.balanced();
  assert.equal(r.count("destroyed"), 1);
});
Deno.test("forged endpoints wrong owners and retired owners reject before publication", () => {
  const r = runtime();
  r.call("root_open");
  const first = r.call("allocate"), second = r.call("allocate");
  const roots = r.global("root_count"), retains = r.count("retains");
  assert.throws(
    () => r.call("project", first + 24, first),
    WebAssembly.RuntimeError,
  );
  assert.throws(
    () => r.call("close", first + 20, second),
    WebAssembly.RuntimeError,
  );
  assert.throws(
    () => r.call("project", first + 37, first),
    WebAssembly.RuntimeError,
  );
  assert.throws(() => r.call("retain", first + 20), WebAssembly.RuntimeError);
  assert.equal(r.global("root_count"), roots);
  assert.equal(r.count("retains"), retains);
  r.call("release_lease", first);
  assert.throws(
    () => r.call("project", first + 20, first),
    WebAssembly.RuntimeError,
  );
  r.call("root_close", 0);
  r.balanced();
  assert.equal(r.count("destroyed"), 2);
});
Deno.test("region owner keeps its ordinary external Frame edge counted", () => {
  const r = runtime();
  const external = r.call("root_allocate", 4, 0);
  r.put(external, 42);
  r.call("root_open");
  const owner = r.call("allocate");
  // Ordinary store helper is absent from this fixture; retain is the exact
  // matching field owner, and the unchanged typed destructor discharges it.
  r.call("retain", external);
  r.put(owner + 8, external);
  r.call("root_close", 0);
  assert.equal(r.count("destroyed"), 1);
  assert.equal(r.word(external - 16), 1);
  assert.equal(r.word(external), 42);
  r.call("release_lease", external);
  r.balanced();
  assert.equal(r.count("destroyed"), 2);
});

Deno.test("repeated region cleanup preserves bounded physical storage", () => {
  const r = runtime();
  let settled = 0;
  for (let round = 0; round < 24; round++) {
    r.call("root_enter");
    for (let index = 0; index < 256; index++) {
      r.call("root_open");
      const owner = r.call("allocate");
      r.call("root_close", 0);
    }
    r.call("root_leave", 0);
    r.balanced();
    if (round === 1) settled = r.memory.buffer.byteLength;
    if (round > 1) assert.equal(r.memory.buffer.byteLength, settled);
  }
  assert.equal(r.count("destroyed"), 24 * 256);
});
