import { strict as assert } from "node:assert";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const fixture = new URL(
  "../cohort-fixture.wasm",
  new URL(executable, `file://${Deno.cwd()}/`),
);
const input = await Deno.readFile(fixture);
function runtime(complete = true) {
  const instance = new WebAssembly.Instance(new WebAssembly.Module(input));
  const exports = instance.exports;
  const memory = exports["blot:memory"] as WebAssembly.Memory;
  const call = (name: string, ...args: number[]) =>
    Number((exports[name] as CallableFunction)(...args)) >>> 0;
  const global = (name: string) =>
    Number((exports[name] as WebAssembly.Global).value) >>> 0;
  const set = (name: string, value: number) => {
    (exports[name] as WebAssembly.Global).value = value | 0;
  };
  const word = (p: number) => new DataView(memory.buffer).getUint32(p, true);
  const put = (p: number, n: number) =>
    new DataView(memory.buffer).setUint32(p, n, true);
  if (complete) set("root_enabled", 3);
  const count = (name: string) => global(`blot:rc_${name}`);
  const owner = () => {
    const p = call("root_allocate", 4, 1);
    call("begin", p);
    return p;
  };
  const balanced = () => {
    assert.equal(global("root_count"), 0);
    assert.equal(count("leases"), 0);
  };
  return { call, global, set, word, put, count, owner, balanced, memory };
}

Deno.test("cohorts require complete ownership before changing headers or roots", () => {
  const r = runtime(false);
  r.call("root_open");
  const p = r.call("root_allocate", 4, 1);
  const flags = r.word(p - 24);
  assert.throws(() => r.call("begin", p), WebAssembly.RuntimeError);
  assert.equal(r.word(p - 24), flags);
  assert.equal(r.word(p - 16), 1);
  r.set("root_enabled", 3);
  r.call("begin", p);
  assert.throws(() => r.call("begin", p), WebAssembly.RuntimeError);
  const roots = r.global("root_count");
  r.set("rc_enabled", 0);
  assert.throws(() => r.call("allocate", 4, 1, p), WebAssembly.RuntimeError);
  r.set("rc_enabled", 1);
  assert.equal(r.global("root_count"), roots);
  r.call("root_close", 0);
  r.balanced();
});

Deno.test("cohort retirement reclaims a local cycle with truthful pins and leases", () => {
  const r = runtime();
  r.call("root_open");
  const p = r.owner();
  const a = r.call("allocate", 4, 1, p);
  const b = r.call("allocate", 4, 1, p);
  r.put(p, a);
  r.put(a, b);
  r.put(b, a);
  // Allocation transfers each fresh lease into its owner without a member journal.
  assert.equal(r.word(a - 16), 1);
  assert.equal(r.word(b - 16), 1);
  assert.equal(r.count("retains"), 0);
  assert.equal(r.global("root_count"), 1);
  assert.equal(r.count("leases"), 1);
  for (const value of [a, b]) {
    assert.equal(r.word(value - 24) & 8, 0);
    assert.throws(
      () => r.call("release_lease", value),
      WebAssembly.RuntimeError,
    );
    assert.equal(r.word(value - 16), 1);
  }
  r.call("root_close", 0);
  r.balanced();
  assert.equal(r.count("releases"), 3);
  assert.equal(r.count("destroyed"), 3);
  assert.equal(r.global("cycle_vertices"), 0);
  for (const value of [p, a, b]) assert.equal(r.word(value - 28), 0);
});

Deno.test("cohorts preserve ordinary ownership of live outgoing children", () => {
  const r = runtime();
  const child = r.call("root_allocate", 4, 0);
  r.put(child, 42);
  r.call("root_open");
  const p = r.owner();
  const a = r.call("allocate", 8, 3, p);
  r.put(p, a);
  r.put(a, a);
  r.call("store_word", a, a + 4, child);
  assert.equal(r.word(child - 16), 2);
  r.call("root_close", 0);
  assert.equal(r.count("destroyed"), 2);
  assert.equal(r.word(child), 42);
  assert.equal(r.word(child - 16), 1);
  r.call("release_lease", child);
  r.balanced();
  assert.equal(r.count("destroyed"), 3);
});

Deno.test("cohort capacity rejects the next allocation before reserving a root", () => {
  const r = runtime();
  r.call("root_open");
  const p = r.owner();
  for (let i = 0; i < 64; i++) r.call("allocate", 4, 0, p);
  const roots = r.global("root_count");
  const heap = r.global("heap");
  assert.throws(() => r.call("allocate", 4, 0, p), WebAssembly.RuntimeError);
  assert.equal(r.global("root_count"), roots);
  assert.equal(r.global("heap"), heap);
  r.call("root_close", 0);
  r.balanced();
  assert.equal(r.count("destroyed"), 65);
});

Deno.test("cohort retirement validates all external retains before marking any member dead", () => {
  const r = runtime();
  r.call("root_open");
  const p = r.owner();
  const a = r.call("allocate", 4, 1, p);
  const b = r.call("allocate", 4, 1, p);
  r.put(a, b);
  r.put(b, a);
  r.call("retain", a);
  assert.throws(() => r.call("root_close", 0), WebAssembly.RuntimeError);
  assert.equal(r.count("destroyed"), 0);
  for (const value of [p, a, b]) {
    assert.equal(r.word(value - 24) & 16, 0);
    assert.equal(r.word(value - 28), 4);
  }
  r.call("release", a);
  r.call("retire", p);
  r.call("root_close", 0);
  r.balanced();
  assert.equal(r.count("destroyed"), 3);
});

Deno.test("cohorts reject corrupt lists and premature member retirement transactionally", () => {
  const r = runtime();
  r.call("root_open");
  const p = r.owner();
  const a = r.call("allocate", 4, 0, p);
  assert.throws(() => r.call("retire", a), WebAssembly.RuntimeError);
  assert.equal(r.word(a - 16), 1);
  r.put(a - 4, a);
  assert.throws(() => r.call("root_close", 0), WebAssembly.RuntimeError);
  assert.equal(r.count("destroyed"), 0);
  assert.equal(r.word(a - 24) & 16, 0);
  r.put(a - 4, 0);
  r.call("retire", p);
  r.call("root_close", 0);
  r.balanced();
});

Deno.test("cycle discovery cannot overwrite a cohort member list through an external candidate", () => {
  const r = runtime();
  r.call("root_open");
  const p = r.owner();
  const a = r.call("allocate", 4, 1, p);
  const b = r.call("allocate", 4, 1, p);
  r.put(p, a);
  r.put(a, b);
  r.put(b, a);
  const external = r.call("root_allocate", 8, 3);
  r.call("store_word", external, external, external);
  r.call("store_word", external, external + 4, b);
  // Members have no journal lease to release; only the ordinary external
  // candidate drops its allocation lease before cycle discovery.
  assert.equal(r.word(a - 16), 1);
  assert.equal(r.word(b - 16), 2);
  r.call("release_lease", external);
  const next = r.word(b - 4);
  r.call("cycle_collect");
  assert.equal(r.count("destroyed"), 1);
  assert.equal(r.word(b - 4), next);
  assert.equal(r.word(b - 16), 1);
  r.call("root_close", 0);
  r.balanced();
  assert.equal(r.count("destroyed"), 4);
});

Deno.test("cohort roots spill pages and unwind invocation traps with bounded retained memory", () => {
  const r = runtime();
  let settled = 0;
  for (let round = 0; round < 24; round++) {
    r.call("root_enter");
    for (let group = 0; group < 16; group++) {
      const p = r.owner();
      for (let i = 0; i < 40; i++) {
        // A real force record publishes this Memo-shaped member. Its
        // environment edge is a local self-cycle, and failure terminalizes
        // evaluating status before releasing the journal owner.
        const a = r.call("allocate", 16, 2, p);
        r.put(a + 4, a);
        r.put(a + 8, 1);
        r.call("root_force", a);
        assert.equal(r.word(a - 16), 2);
      }
    }
    assert.equal(r.global("root_count"), 16 * 41);
    assert.notEqual(
      r.word(r.global("root_page")),
      0,
      "real journal records spill into a second page",
    );
    r.call("root_leave", 1);
    r.call("root_leave", 2);
    r.balanced();
    if (round === 1) settled = r.memory.buffer.byteLength;
    if (round > 1) assert.equal(r.memory.buffer.byteLength, settled);
  }
  assert.equal(r.count("destroyed"), 24 * 16 * 41);
});

for (const journal of ["root_force", "root_authority"]) {
  Deno.test(`a cohort owner cannot retire before a member's ${journal} record`, () => {
    const r = runtime();
    r.call("root_open");
    const p = r.owner();
    let bytes = 4;
    if (journal === "root_force") bytes = 16;
    const a = r.call("allocate", bytes, 0, p);
    assert.equal(r.word(a - 16), 1);
    assert.equal(r.global("root_count"), 1);
    assert.equal(r.count("leases"), 1);
    // These actual runtime records, not forged strong counts or lease bits,
    // publish an additional owner of the member.
    r.call(journal, a);
    assert.equal(r.word(a - 16), 2);
    assert.equal(r.global("root_count"), 2);
    assert.equal(r.count("leases"), 1);
    assert.throws(() => r.call("release_lease", p), WebAssembly.RuntimeError);
    assert.equal(r.count("destroyed"), 0);
    assert.equal(r.word(a - 16), 2);
    for (const value of [p, a]) assert.equal(r.word(value - 24) & 16, 0);
    // Closing retires the real record, leaving the cohort's member pin. The
    // failed owner's ordinary lease was already consumed before validation.
    r.call("root_close", 0);
    assert.equal(r.word(a - 16), 1);
    r.call("retire", p);
    r.balanced();
    assert.equal(r.count("destroyed"), 2);
  });
}

Deno.test("dropping a live member pin cannot bypass cohort retirement", () => {
  const r = runtime();
  r.call("root_open");
  const p = r.owner();
  const a = r.call("allocate", 4, 0, p);
  assert.equal(r.word(a - 16), 1);
  assert.throws(() => r.call("release", a), WebAssembly.RuntimeError);
  assert.equal(r.count("destroyed"), 0);
  assert.equal(r.word(a - 28), 4);
  assert.equal(r.word(a - 24) & 16, 0);
  assert.equal(r.word(p - 4), a);
});
