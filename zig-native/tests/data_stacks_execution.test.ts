import { strict as assert } from "node:assert";

const compiler = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const fixture = new URL(
  "../data-stacks-fixture.wasm",
  new URL(compiler, `file://${Deno.cwd()}/`),
);
type Owner = readonly [number, number, number];
async function runtime() {
  const module = new WebAssembly.Module(await Deno.readFile(fixture));
  assert.deepEqual(WebAssembly.Module.imports(module), []);
  const { exports } = new WebAssembly.Instance(module);
  assert(
    !Object.keys(exports).some((name) =>
      /retain|release|cycle|arena/.test(name)
    ),
  );
  const call = (name: string, ...args: number[]) =>
    Number((exports[name] as CallableFunction)(...args)) >>> 0;
  return {
    memory: exports["blot:memory"] as WebAssembly.Memory,
    call,
    open(region: number): Owner {
      const id = call("open", region);
      return [id, call("epoch_low", id), call("epoch_high", id)];
    },
  };
}

Deno.test("data stacks grow without per-array capacity and reuse independently released slots", async () => {
  const r = await runtime();
  const owner = r.open(0);
  const array = r.call("create", ...owner, 1, 1, 4);
  r.call("write", ...owner, array, 0, 42);
  const address = r.call("address", ...owner, array, 0);
  for (let index = 0; index < 5000; index++) {
    r.call("append", ...owner, array, index);
    const temporary = r.open(1);
    const value = r.call("create", ...temporary, 1, 0, 4);
    r.call("close", ...temporary);
    assert.throws(
      () => r.call("read", ...temporary, value, 0),
      WebAssembly.RuntimeError,
    );
  }
  assert.equal(r.call("address", ...owner, array, 0), address);
  assert.equal(r.call("read", ...owner, array, 0), 42);
  assert.equal(r.call("length", ...owner, array), 5001);
  // The configured 44 KiB payload plus metadata rounds to two Wasm pages.
  assert.equal(r.memory.buffer.byteLength, 2 * 65536);
  assert.throws(() => r.memory.grow(1), RangeError);
  r.call("close", ...owner);
  const fresh = r.open(0);
  assert.equal(r.call("create", ...fresh, 1, 1, 4), array);
  assert.equal(fresh[0], owner[0]);
  assert.notDeepEqual(fresh, owner);
  assert.throws(() => r.call("close", ...owner), WebAssembly.RuntimeError);
  assert.equal(r.call("read", ...fresh, array, 0), 0);
  assert.throws(
    () => r.call("read", ...owner, array, 0),
    WebAssembly.RuntimeError,
  );
});

Deno.test("data-stack overflow bounds and topmost growth are checked before mutation", async () => {
  const r = await runtime();
  for (const region of [3, 0x40000000, 0xffffffff]) {
    assert.throws(() => r.open(region), WebAssembly.RuntimeError);
  }
  const owner = r.open(0);
  for (
    const [count, stride] of [[0xffffffff, 4], [1, 0xfffffffc], [1, 0], [1, 3]]
  ) {
    assert.throws(
      () => r.call("create", ...owner, count, 1, stride),
      WebAssembly.RuntimeError,
    );
  }
  const full = r.call("create", ...owner, (32768 - 16) / 4, 2, 4);
  const count = r.call("length", ...owner, full);
  assert.throws(
    () => r.call("append", ...owner, full, 99),
    WebAssembly.RuntimeError,
  );
  assert.equal(r.call("length", ...owner, full), count);
  assert.throws(
    () => r.call("read", ...owner, full, count),
    WebAssembly.RuntimeError,
  );
  r.call("truncate", ...owner, full, 1);
  r.call("append", ...owner, full, 42);
  assert.equal(r.call("read", ...owner, full, 1), 42);
  const mark = r.call("mark", 0);
  const child = r.open(0);
  const upper = r.call("create", ...child, 1, 0, 4);
  assert.throws(
    () => r.call("append", ...owner, full, 99),
    WebAssembly.RuntimeError,
  );
  assert.throws(
    () => r.call("truncate", ...owner, full, 0),
    WebAssembly.RuntimeError,
  );
  assert.equal(r.call("length", ...owner, full), 2);
  assert.equal(r.call("read", ...child, upper, 0), 0);
  assert.throws(() => r.call("rewind", 0, upper + 4), WebAssembly.RuntimeError);
  assert.equal(r.call("length", ...child, upper), 1);
  r.call("rewind", 0, mark);
  assert.throws(
    () => r.call("read", ...child, upper, 0),
    WebAssembly.RuntimeError,
  );
  r.call("append", ...owner, full, 99);
  assert.equal(r.call("read", ...owner, full, 2), 99);
});

Deno.test("data stacks preserve aggregate stride and invalidate generations across recovery", async () => {
  const r = await runtime();
  const persistent = r.open(0);
  const world = r.call("create", ...persistent, 1, 1, 4);
  r.call("write", ...persistent, world, 0, 42);
  const owner = r.open(1);
  const rows = r.call("create", ...owner, 2, 1, 20);
  assert.equal(
    r.call("address", ...owner, rows, 1) - r.call("address", ...owner, rows, 0),
    20,
  );
  assert.equal(r.call("append_space", ...owner, rows), rows + 16 + 40);
  r.call("freeze", ...owner, rows);
  assert.throws(
    () => r.call("append_space", ...owner, rows),
    WebAssembly.RuntimeError,
  );
  r.call("reset_temporary", 1);
  assert.equal(r.call("read", ...persistent, world, 0), 42);
  const fresh = r.open(1);
  assert.equal(r.call("create", ...fresh, 2, 0, 20), rows);
  assert.throws(
    () => r.call("read", ...owner, rows, 0),
    WebAssembly.RuntimeError,
  );
  assert.equal(r.call("read", ...fresh, rows, 1), 0);
  r.call("reset");
  assert.throws(
    () => r.call("read", ...persistent, world, 0),
    WebAssembly.RuntimeError,
  );
});

Deno.test("packed owners have independent identities beyond 255 entries", async () => {
  const r = await runtime();
  const owners: Owner[] = [];
  const arrays: number[] = [];
  for (let index = 0; index < 300; index++) {
    const owner = r.open(0);
    const array = r.call("create", ...owner, 1, 0, 4);
    r.call("write", ...owner, array, 0, index);
    owners.push(owner);
    arrays.push(array);
    if (index) assert.equal(array - arrays[index - 1], 20);
  }
  const stale = owners[0];
  r.call("close", ...stale);
  const replacement = r.open(0);
  const next = r.call("create", ...replacement, 1, 0, 4);
  assert.equal(replacement[0], stale[0]);
  assert.throws(
    () => r.call("read", ...stale, arrays[0], 0),
    WebAssembly.RuntimeError,
  );
  // Reused metadata cannot authorize the old address with a fresh epoch either.
  assert.throws(
    () => r.call("read", ...replacement, arrays[0], 0),
    WebAssembly.RuntimeError,
  );
  assert.equal(r.call("read", ...owners[299], arrays[299], 0), 299);
  assert.equal(r.call("read", ...replacement, next, 0), 0);
});

Deno.test("owner epochs carry across the low word and trap before full exhaustion", async () => {
  const r = await runtime();
  r.call("seed_epoch", 0xfffffffe, 41);
  const before = r.open(0);
  const array = r.call("create", ...before, 1, 0, 4);
  assert.deepEqual(before.slice(1), [0xffffffff, 41]);
  r.call("close", ...before);
  const after = r.open(0);
  assert.deepEqual(after.slice(1), [0, 42]);
  r.call("create", ...after, 1, 0, 4);
  assert.throws(
    () => r.call("read", ...before, array, 0),
    WebAssembly.RuntimeError,
  );
  r.call("close", ...after);
  r.call("seed_epoch", 0xfffffffe, 0xffffffff);
  const last = r.open(0);
  assert.deepEqual(last.slice(1), [0xffffffff, 0xffffffff]);
  const finalArray = r.call("create", ...last, 1, 0, 4);
  assert.throws(() => r.open(1), WebAssembly.RuntimeError);
  assert.equal(r.call("read", ...last, finalArray, 0), 0);
});

Deno.test("owner retirement preserves high persistent slots and rejects reused holes", async () => {
  const r = await runtime();
  const low = r.open(1);
  const lowRows = r.call("create", ...low, 1, 0, 4);
  const retained = r.open(0);
  const rows = r.call("create", ...retained, 1, 0, 4);
  r.call("write", ...retained, rows, 0, 42);
  const mark = r.call("mark", 2);
  const upper = r.open(2);
  const upperRows = r.call("create", ...upper, 1, 0, 4);
  r.call("close", ...low);
  r.call("rewind", 2, mark);
  assert.throws(
    () => r.call("read", ...upper, upperRows, 0),
    WebAssembly.RuntimeError,
  );
  assert.equal(r.call("read", ...retained, rows, 0), 42);
  const hole = r.open(1);
  assert.equal(hole[0], low[0]);
  r.call("create", ...hole, 1, 0, 4);
  assert.throws(
    () => r.call("read", ...low, lowRows, 0),
    WebAssembly.RuntimeError,
  );
  r.call("reset_temporary", 1);
  assert.equal(r.call("read", ...retained, rows, 0), 42);
  assert.throws(() => r.call("epoch_low", hole[0]), WebAssembly.RuntimeError);
  r.call("close", ...retained);
  const fresh = r.open(0);
  assert.equal(fresh[0], low[0]);
  const next = r.call("create", ...fresh, 1, 0, 4);
  assert.throws(
    () => r.call("read", ...retained, rows, 0),
    WebAssembly.RuntimeError,
  );
  assert.equal(r.call("read", ...fresh, next, 0), 0);
});

Deno.test("data-stack array modes preserve initialized bounds through shrink and freeze", async () => {
  const r = await runtime();
  const grow = r.open(1);
  const a = r.call("create", ...grow, 0, 1, 4);
  assert.equal(r.call("length", ...grow, a), 0);
  assert.throws(() => r.call("read", ...grow, a, 0), WebAssembly.RuntimeError);
  r.call("append", ...grow, a, 0xffffffff);
  assert.equal(r.call("read", ...grow, a, 0), 0xffffffff);
  assert.throws(
    () => r.call("truncate", ...grow, a, 0),
    WebAssembly.RuntimeError,
  );
  r.call("close", ...grow);
  const resize = r.open(1);
  const b = r.call("create", ...resize, 3, 2, 4);
  for (const [index, value] of [10, 20, 30].entries()) {
    r.call("write", ...resize, b, index, value);
  }
  r.call("truncate", ...resize, b, 1);
  assert.throws(
    () => r.call("read", ...resize, b, 1),
    WebAssembly.RuntimeError,
  );
  assert.throws(
    () => r.call("write", ...resize, b, 1, 99),
    WebAssembly.RuntimeError,
  );
  assert.throws(
    () => r.call("truncate", ...resize, b, 2),
    WebAssembly.RuntimeError,
  );
  r.call("append", ...resize, b, 77);
  assert.equal(r.call("read", ...resize, b, 1), 77);
  r.call("freeze", ...resize, b);
  assert.throws(
    () => r.call("append", ...resize, b, 88),
    WebAssembly.RuntimeError,
  );
  assert.throws(
    () => r.call("truncate", ...resize, b, 0),
    WebAssembly.RuntimeError,
  );
  r.call("close", ...resize);
  const fixed = r.open(1);
  assert.throws(
    () => r.call("create", ...fixed, 2, 3, 4),
    WebAssembly.RuntimeError,
  );
  const c = r.call("create", ...fixed, 2, 0, 4);
  assert.equal(r.call("length", ...fixed, c), 2);
  assert.equal(r.call("read", ...fixed, c, 1), 0);
  r.call("write", ...fixed, c, 1, 42);
  assert.equal(r.call("read", ...fixed, c, 1), 42);
  assert.throws(
    () => r.call("append", ...fixed, c, 7),
    WebAssembly.RuntimeError,
  );
  for (const index of [2, 0x40000000, 0xffffffff]) {
    assert.throws(
      () => r.call("read", ...fixed, c, index),
      WebAssembly.RuntimeError,
    );
  }
  r.call("close", ...fixed);
});

Deno.test("empty data stacks and owner-table exhaustion retain valid identities", async () => {
  const r = await runtime();
  const empty = r.open(1);
  const array = r.call("create", ...empty, 0, 1, 4);
  assert.equal(r.call("length", ...empty, array), 0);
  // Growth is region-budgeted, never capped by the initial zero length.
  r.call("append", ...empty, array, 42);
  assert.equal(r.call("read", ...empty, array, 0), 42);
  r.call("close", ...empty);
  const owners: Owner[] = [];
  for (let index = 0; index < 320; index++) owners.push(r.open(1));
  assert.throws(() => r.open(1), WebAssembly.RuntimeError);
  for (const owner of owners) {
    assert.equal(r.call("epoch_low", owner[0]), owner[1]);
    assert.equal(r.call("epoch_high", owner[0]), owner[2]);
  }
  for (const owner of owners.reverse()) r.call("close", ...owner);
  const fresh = r.open(1);
  const value = r.call("create", ...fresh, 1, 0, 4);
  assert.equal(r.call("read", ...fresh, value, 0), 0);
});
