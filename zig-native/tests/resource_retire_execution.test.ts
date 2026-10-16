import { strict as assert } from "node:assert";

const compiler = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const fixture = new URL(
  "../resource-retire-fixture.wasm",
  new URL(compiler, `file://${Deno.cwd()}/`),
);
async function runtime() {
  const events = new Uint32Array(16);
  let count = 0;
  let view: DataView;
  let observedBox = 0;
  let observedChild = 0;
  let boxTokenAtMark = -1;
  let childCountAtMark = -1;
  const instance = new WebAssembly.Instance(
    new WebAssembly.Module(await Deno.readFile(fixture)),
    {
      "blot:resource/2": {
        retire(token: number) {
          // The host mark only flips existing state: no guest call or cleanup.
          events[count++] = token;
          boxTokenAtMark = view.getUint32(observedBox + 4, true);
          if (observedChild) {
            childCountAtMark = view.getUint32(observedChild - 16, true);
          }
        },
      },
    },
  );
  const exports = instance.exports;
  (exports.allocator_mode as WebAssembly.Global).value = 1;
  const memory = exports["blot:memory"] as WebAssembly.Memory;
  view = new DataView(memory.buffer);
  const call = (name: string, ...args: number[]) => {
    const result = Number((exports[name] as CallableFunction)(...args)) >>> 0;
    if (view.buffer !== memory.buffer) view = new DataView(memory.buffer);
    return result;
  };
  const word = (p: number) => view.getUint32(p, true);
  const put = (p: number, value: number) => view.setUint32(p, value, true);
  return {
    exports,
    call,
    word,
    put,
    events: () => [...events.subarray(0, count)],
    observation: () => [boxTokenAtMark, childCountAtMark],
    observe: (box: number, child = 0) => {
      observedBox = box;
      observedChild = child;
    },
    owner: (box: number, token: number) => {
      put(box - 24, word(box - 24) | 2048);
      put(box + 4, token);
    },
    destroyed: () =>
      Number((exports["blot:rc_destroyed"] as WebAssembly.Global).value),
  };
}

Deno.test("owning retirement enqueues once after child accounting and before box free", async () => {
  const r = await runtime();
  const child = r.call("allocate_typed", 4, 0);
  const box = r.call("allocate_typed", 8, 1);
  r.call("store_word", box, box, child);
  r.call("release_lease", child);
  r.owner(box, 71);
  r.observe(box, child);
  r.call("retain", box);
  r.call("release_lease", box);
  assert.deepEqual(r.events(), []);
  r.call("release", box);
  assert.deepEqual(r.events(), [71]);
  assert.deepEqual(r.observation(), [0, 0]);
  assert.equal(r.destroyed(), 2);
  assert.equal(r.word(box - 4), 0);
  assert.equal(r.word(child - 4), 0);
  const reused = r.call("allocate_typed", 8, 0);
  assert.equal(r.word(reused + 4), 0);
  assert.equal(r.word(reused - 24) & 2048, 0);
  r.call("release_lease", reused);
  assert.deepEqual(r.events(), [71]);
});

Deno.test("owning cycle retirement enqueues once at exhausted heap with no cleanup reentry", async () => {
  const r = await runtime();
  const box = r.call("allocate_typed", 8, 1);
  r.call("store_word", box, box, box);
  r.owner(box, 73);
  r.observe(box);
  r.call("release_lease", box);
  assert.deepEqual(r.events(), []);
  const heap = r.exports.heap as WebAssembly.Global;
  const before = heap.value;
  heap.value = 0xfffffff0;
  r.call("cycle_collect");
  assert.deepEqual(r.events(), [73]);
  assert.equal(r.observation()[0], 0);
  assert.equal(r.destroyed(), 1);
  assert.equal(Number((r.exports.cycle_head as WebAssembly.Global).value), 0);
  assert.equal(
    Number((r.exports.cycle_members as WebAssembly.Global).value),
    0,
  );
  r.call("cycle_collect");
  assert.deepEqual(r.events(), [73]);
  heap.value = before;
});

Deno.test("ordinary boxes and explicitly cleared owners never enqueue tokens", async () => {
  const r = await runtime();
  for (const owning of [false, true]) {
    const box = r.call("allocate_typed", 8, 0);
    r.observe(box);
    if (owning) r.owner(box, 0);
    else r.put(box + 4, 97);
    r.call("release_lease", box);
  }
  assert.deepEqual(r.events(), []);
  assert.equal(r.destroyed(), 2);
});

Deno.test("root last owners retire before their children and previously queued objects in exact drain order", async () => {
  for (const pending of [false, true]) {
    const r = await runtime();
    (r.exports.ownership_mode as WebAssembly.Global).value = 1;
    r.call("root_enter");
    const child = r.call("root_allocate", 8, 0);
    r.owner(child, 301);
    const parent = r.call("root_allocate", 8, 1);
    r.owner(parent, 302);
    r.call("store_word", parent, parent, child);
    r.call("release_lease", child);
    const sibling = r.call("root_allocate", 8, 0);
    r.owner(sibling, 303);
    r.observe(parent, child);
    if (pending) {
      const earlier = r.call("allocate_typed", 8, 0);
      r.owner(earlier, 304);
      r.call("retain", earlier);
      r.call("release_lease", earlier);
      r.call("decrement", earlier);
    }
    assert.deepEqual(r.events(), []);
    r.call("root_leave", 0);
    const expected = [303, 302, 301];
    if (pending) expected.splice(1, 0, 304);
    assert.deepEqual(r.events(), expected);
    assert.equal(r.destroyed(), expected.length);
    assert.deepEqual(r.observation(), [0, 0]);
    r.call("root_leave", 2);
    assert.deepEqual(r.events(), expected);
  }
});

Deno.test("closing moves an exact ordinary result slot and preserves ancestor lease identity", async () => {
  for (const ancestorLease of [false, true]) {
    for (const tagged of [false, true]) {
      const r = await runtime();
      (r.exports.ownership_mode as WebAssembly.Global).value = 1;
      r.call("root_enter");
      let value;
      if (ancestorLease) value = r.call("root_allocate", 8, 0);
      else {
        value = r.call("allocate_typed", 8, 0);
        r.call("retain", value);
        r.call("release_lease", value);
      }
      r.owner(value, 501);
      r.observe(value);
      const originalOwner = r.word(value - 8);
      const frame = r.call("root_open");
      const resultSlot = r.call("root_reserve");
      r.call("root_store", resultSlot, value);
      if (tagged) r.put(resultSlot + 4, frame | 1);
      const retains = Number((r.exports["blot:rc_retains"] as WebAssembly.Global).value);
      r.call("root_close", value);
      assert.equal(r.word(value - 16), 2);
      assert.equal(r.word(value - 8), originalOwner);
      const expectedRetains = retains + Number(tagged);
      assert.equal(Number((r.exports["blot:rc_retains"] as WebAssembly.Global).value), expectedRetains);
      assert.deepEqual(r.events(), []);
      if (ancestorLease) r.call("release_lease", value);
      else r.call("release", value);
      assert.equal(r.word(value - 16), 1);
      assert.deepEqual(r.events(), []);
      r.call("root_leave", 0);
      assert.deepEqual(r.events(), [501]);
      assert.equal(r.destroyed(), 1);
      r.call("root_leave", 2);
      assert.deepEqual(r.events(), [501]);
    }
  }
});
