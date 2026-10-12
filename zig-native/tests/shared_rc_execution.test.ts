import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const fixture = new URL(
  "../shared-rc-fixture.wasm",
  new URL(executable, `file://${Deno.cwd()}/`),
);
async function runtime(bytes?: Uint8Array<ArrayBuffer>) {
  let input = bytes;
  if (input === undefined) input = await Deno.readFile(fixture);
  const module = new WebAssembly.Module(input);
  const instance = new WebAssembly.Instance(module);
  const exports = instance.exports;
  const memory = exports["blot:memory"] as WebAssembly.Memory;
  return {
    exports,
    mode: [
      ...new Uint8Array(
        WebAssembly.Module.customSections(module, "blot:ownership")[0],
      ),
    ],
    call: (name: string, ...args: number[]) =>
      Number((exports[name] as CallableFunction)(...args)) >>> 0,
    count: (name: string) =>
      Number((exports[`blot:rc_${name}`] as WebAssembly.Global).value),
    roots: () => Number((exports.roots as WebAssembly.Global).value),
    heap: () => Number((exports.heap as WebAssembly.Global).value) >>> 0,
    setHeap: (value: number) => {
      (exports.heap as WebAssembly.Global).value = value | 0;
    },
    word: (address: number) =>
      new DataView(memory.buffer).getUint32(address, true),
    put: (address: number, value: number) =>
      new DataView(memory.buffer).setUint32(address, value, true),
  };
}

Deno.test("trial deletion reclaims self cycles and shared children without tracing", async () => {
  const r = await runtime();
  const metric = (name: string) =>
    Number((r.exports[name] as WebAssembly.Global).value);
  const child = r.call("allocate_typed", 4, 0);
  r.call("store_word", child, child, 42);
  const left = r.call("allocate_typed", 12, 7);
  const right = r.call("allocate_typed", 8, 3);
  r.call("store_word", left, left, left);
  r.call("store_word", left, left + 4, right);
  r.call("store_word", left, left + 8, child);
  r.call("store_word", right, right, left);
  r.call("store_word", right, right + 4, child);
  r.call("release_lease", left);
  r.call("cycle_collect");
  assert.equal(r.count("destroyed"), 0);
  // The still-leased right node contributes an outside edge into left.
  assert.equal(r.word(left), left);
  r.call("release_lease", right);
  r.call("cycle_collect");
  assert.equal(r.count("destroyed"), 2);
  assert.equal(r.word(child), 42);
  assert.equal(r.word(child - 16), 1);
  assert.equal(metric("cycle_bytes"), 20);
  assert.equal(metric("cycle_head"), 0);
  r.call("release_lease", child);
  assert.equal(r.count("destroyed"), 3);
});

Deno.test("finite typed masks bound sparse cycles without interpreting scalar tails", async () => {
  const r = await runtime();
  const metric = (name: string) =>
    Number((r.exports[name] as WebAssembly.Global).value);
  const scalar = r.call("allocate_typed", 4, 0);
  r.call("store_word", scalar, scalar, 42);
  for (const mask of [1, 0x40000000]) {
    const object = r.call("allocate_typed", 4194304, mask);
    let edgeOffset = 0;
    if (mask !== 1) edgeOffset = 120;
    r.call("store_word", object, object + edgeOffset, object);
    // This is beyond the finite mask, despite looking like a live pointer.
    r.call("store_word", object, object + 4194300, scalar);
    r.call("release_lease", object);
    const edges = metric("cycle_edges"), vertices = metric("cycle_vertices");
    r.call("cycle_collect");
    assert.equal(metric("cycle_edges") - edges, 1);
    assert.equal(metric("cycle_vertices") - vertices, 1);
    assert.equal(r.word(scalar), 42);
    assert.equal(r.word(scalar - 16), 1);
  }
  assert.equal(r.count("destroyed"), 2);
  r.call("release_lease", scalar);
  assert.equal(r.count("destroyed"), 3);
});

Deno.test("trial deletion preserves alias roots and duplicate capacity edges then retires their cycle", async () => {
  const r = await runtime();
  const leaf = r.call("allocate_typed", 992, 0xfffffff0);
  const node = r.call("allocate_typed", 4, 1);
  // Logical length is zero; these physical capacity slots still own edges.
  r.call("store_word", leaf, leaf + 16, node);
  r.call("store_word", leaf, leaf + 988, node);
  r.call("store_word", node, node, leaf);
  r.call("retain", leaf);
  r.call("release_lease", leaf);
  r.call("release_lease", node);
  r.call("cycle_collect");
  assert.equal(r.count("destroyed"), 0);
  assert.equal(r.word(node - 16), 2);
  assert.equal(r.word(leaf - 16), 2);
  r.call("release", leaf);
  r.call("cycle_collect");
  assert.equal(r.count("destroyed"), 2);
  assert.equal(r.count("leases"), 0);
});

Deno.test("trial deletion is allocation free at exhausted heap and weak candidates survive tracer retirement", async () => {
  const r = await runtime();
  const value = r.call("allocate_typed", 4, 1);
  r.call("store_word", value, value, value);
  r.call("release_lease", value);
  const heap = r.heap();
  r.setHeap(0xfffffff0);
  r.call("cycle_collect");
  assert.equal(r.count("destroyed"), 1);
  r.setHeap(heap);
  const replacement = r.call("allocate_typed", 4, 1);
  assert.equal(replacement, value);
  r.call("store_word", replacement, replacement, replacement);
  r.call("release_lease", replacement);
  r.call("collect", 0);
  r.call("cycle_collect");
  assert.equal(r.count("destroyed"), 2);
  assert.equal(Number((r.exports.cycle_head as WebAssembly.Global).value), 0);
});

Deno.test("trial deletion keeps ready memo cycles alive through force and module journal roots", async () => {
  const r = await runtime();
  const demand = r.call("root_allocate", 16, 10);
  const node = r.call("allocate_typed", 4, 1);
  r.call("store_word", demand, demand + 12, node);
  r.call("store_word", node, node, demand);
  r.put(demand + 8, 2);
  r.call("release_lease", node);
  r.call("cycle_collect");
  assert.equal(r.count("destroyed"), 0);
  r.call("root_enter");
  r.call("root_force", demand);
  r.call("release_lease", demand);
  r.call("cycle_collect");
  assert.equal(r.count("destroyed"), 0);
  assert.equal(r.word(demand + 8), 2);
  assert.equal(r.word(r.word(demand + 12)), demand);
  r.call("root_leave", 0);
  assert.equal(r.count("destroyed"), 2);
  assert.equal(r.roots(), 0);
  r.call("root_leave", 2);
});

Deno.test("candidate discovery remains local and deduplicates repeated nonzero drops", async () => {
  const r = await runtime();
  const metric = (name: string) =>
    Number((r.exports[name] as WebAssembly.Global).value);
  // Unrelated leased allocations must not enter the candidate closure.
  const unrelated = Array.from(
    { length: 8192 },
    () => r.call("allocate_typed", 4, 0),
  );
  const value = r.call("allocate_typed", 4, 1);
  r.call("store_word", value, value, value);
  r.call("retain", value);
  r.call("release_lease", value);
  for (let i = 0; i < 8192; i++) {
    r.call("retain", value);
    r.call("release", value);
  }
  assert.equal(metric("cycle_head"), value);
  r.call("cycle_collect");
  assert.equal(metric("cycle_vertices"), 1);
  assert.equal(metric("cycle_edges"), 1);
  assert.equal(r.count("destroyed"), 0);
  r.call("release", value);
  r.call("cycle_safe", 1);
  assert.equal(r.count("destroyed"), 1);
  for (const child of unrelated) r.call("release_lease", child);
  assert.equal(r.count("destroyed"), 8193);
});

Deno.test("removal traffic triggers a complete pass without allocation or queue duplication", async () => {
  const r = await runtime();
  const metric = (name: string) =>
    Number((r.exports[name] as WebAssembly.Global).value);
  const value = r.call("allocate_typed", 1024, 1);
  r.call("store_word", value, value, value);
  r.call("retain", value);
  r.call("release_lease", value);
  r.call("cycle_collect");
  const heap = r.heap(), passes = metric("cycle_passes");
  for (let i = 0; i < 63; i++) {
    r.call("retain", value);
    r.call("release", value);
    r.call("cycle_safe", 0);
  }
  assert.equal(metric("cycle_passes"), passes);
  r.call("retain", value);
  r.call("release", value);
  r.call("cycle_safe", 0);
  assert.equal(metric("cycle_passes"), passes + 1);
  assert.equal(metric("cycle_head"), 0);
  assert.equal(metric("cycle_vertices"), 2);
  assert.equal(r.heap(), heap);
  r.call("release", value);
  r.call("cycle_safe", 1);
  assert.equal(r.count("destroyed"), 1);
});

Deno.test("checked RC preserves aliases and self stores and retires duplicate children once", async () => {
  const r = await runtime();
  assert.equal(r.mode[1], 1);
  const empty = r.call("allocate_typed", 0, 0xffffffff);
  assert.equal(empty, 0);
  r.call("retain", empty);
  r.call("release", empty);
  r.call("release_lease", empty);
  assert.equal(r.count("leases"), 0);
  assert.equal(r.count("retains"), 0);
  assert.equal(r.count("releases"), 0);
  const child = r.call("allocate_typed", 4, 0);
  const parent = r.call("allocate_typed", 8, 3);
  r.call("store_word", child, child, 42);
  r.call("store_word", parent, parent, child);
  r.call("store_word", parent, parent + 4, child);
  assert.equal(r.word(child - 16), 3);
  r.call("store_word", parent, parent, child);
  assert.equal(r.word(child - 16), 3);
  r.call("release_lease", child);
  r.call("retain", parent);
  r.call("release_lease", parent);
  assert.equal(r.word(r.word(parent)), 42);
  assert.equal(r.count("leases"), 0);
  assert.equal(r.count("destroyed"), 0);
  r.call("release", parent);
  assert.equal(r.count("destroyed"), 2);
  assert.equal(r.word(child - 28), 0);
  assert.throws(() => r.call("release", child), WebAssembly.RuntimeError);
});

Deno.test("checked RC replaces edges and ignores pointer-looking scalar words", async () => {
  const r = await runtime();
  const old = r.call("allocate_typed", 4, 0);
  const replacement = r.call("allocate_typed", 4, 0);
  const parent = r.call("allocate_typed", 8, 1);
  r.call("store_word", parent, parent, old);
  r.call("store_word", parent, parent + 4, old);
  r.call("release_lease", old);
  r.call("store_word", parent, parent, replacement);
  assert.equal(r.count("destroyed"), 1);
  r.call("release_lease", replacement);
  r.call("release_lease", parent);
  assert.equal(r.count("leases"), 0);
  assert.equal(r.count("destroyed"), 3);
  const overflow = r.call("allocate_typed", 4, 0);
  r.put(overflow - 16, 0xffffffff);
  assert.throws(() => r.call("retain", overflow), WebAssembly.RuntimeError);
  r.put(overflow - 16, 1);
  assert.throws(
    () => r.call("release", overflow + 1),
    WebAssembly.RuntimeError,
  );
  r.call("release_lease", overflow);
});

Deno.test("tracer dead-set retirement removes internal edges and preserves an outgoing live child", async () => {
  const r = await runtime();
  const child = r.call("allocate_typed", 4, 0);
  const left = r.call("allocate_typed", 8, 3);
  const right = r.call("allocate_typed", 4, 1);
  r.call("store_word", child, child, 42);
  r.call("store_word", left, left, right);
  r.call("store_word", left, left + 4, child);
  r.call("store_word", right, right, left);
  r.call("collect", child);
  assert.equal(r.word(child), 42);
  assert.equal(r.word(child - 16), 1);
  assert.equal(r.count("leases"), 1);
  assert.equal(r.count("destroyed"), 2);
  r.call("release_lease", child);
  assert.equal(r.count("destroyed"), 3);
});

Deno.test("checked reference copies preserve both overlap directions and reject partial publication", async () => {
  const r = await runtime();
  const children = [0, 1, 2].map(() => r.call("allocate_typed", 4, 0));
  const parent = r.call("allocate_typed", 12, 7);
  for (let i = 0; i < children.length; i++) {
    r.call("store_word", parent, parent + i * 4, children[i]);
    r.call("release_lease", children[i]);
  }
  r.call("copy_words", parent, parent + 4, parent, 8);
  assert.deepEqual([0, 4, 8].map((i) => r.word(parent + i)), [
    children[0],
    children[0],
    children[1],
  ]);
  assert.equal(r.word(children[0] - 16), 2);
  assert.equal(r.count("destroyed"), 1);
  r.call("copy_words", parent, parent, parent + 4, 8);
  assert.deepEqual([0, 4, 8].map((i) => r.word(parent + i)), [
    children[0],
    children[1],
    children[1],
  ]);
  assert.equal(r.word(children[1] - 16), 2);
  const retains = r.count("retains");
  r.call("copy_words", parent, parent, parent, 12);
  assert.equal(r.count("retains"), retains);
  assert.throws(
    () => r.call("copy_words", parent, parent + 8, parent, 8),
    WebAssembly.RuntimeError,
  );
  assert.throws(
    () => r.call("copy_words", parent, parent, parent, 3),
    WebAssembly.RuntimeError,
  );
  assert.equal(r.count("retains"), retains);
  r.call("release_lease", parent);
  assert.equal(r.count("leases"), 0);
  assert.equal(r.count("destroyed"), 4);
});

Deno.test("a million-node acyclic graph destroys without recursive Wasm calls", async () => {
  const r = await runtime();
  assert.equal(r.call("chain", 1_000_000), 0);
  assert.equal(r.count("leases"), 0);
  assert.equal(r.count("retains"), 999_999);
  assert.equal(r.count("releases"), 1_999_999);
  assert.equal(r.count("destroyed"), 1_000_000);
});

Deno.test("typed collection descriptors count shared leaves and skip owner tokens and scalar leaves", async () => {
  const r = await runtime();
  const child = r.call("allocate_typed", 4, 0);
  const leaf = r.call("allocate_typed", 992, 0xfffffff0);
  const scalar = r.call("allocate_typed", 992, 0);
  const branch = r.call("allocate_typed", 24, 0x30);
  const descriptor = r.call("allocate_typed", 24, 6);
  r.call("store_word", leaf, leaf, descriptor + 1);
  r.call("store_word", leaf, leaf + 16, child);
  r.call("store_word", leaf, leaf + 20, child);
  r.call("store_word", scalar, scalar + 16, child);
  r.call("store_word", branch, branch + 16, leaf);
  r.call("store_word", branch, branch + 20, scalar);
  r.call("store_word", descriptor, descriptor + 4, branch);
  r.call("store_word", descriptor, descriptor + 8, leaf);
  assert.equal(r.word(descriptor - 16), 1);
  assert.equal(r.word(leaf - 16), 3);
  assert.equal(r.word(child - 16), 3);
  for (const node of [child, leaf, scalar, branch]) {
    r.call("release_lease", node);
  }
  r.call("release_lease", descriptor);
  assert.equal(r.count("leases"), 0);
  assert.equal(r.count("destroyed"), 5);
});

const source = `
entry const array_group = fn (value: U32) => do:
  let child = #[value, value, value, value, value, value, value, value, value, value, value, value, value, value, value, value, value, value + 1]
  let left = #[child, child]
  let right = #[child, child]
  return left[0][17] + right[1][0]
entry const arrays = fn (value: U32) => do:
  if value == 0:
    return 0
  let child = #[value, value + 1]
  let values = @array.fill 4 child
  let before = values
  values[0] := #[value + 10, value + 20]
  return before[0][1] + values[0][1] + values[1][0]
entry const lists = fn (value: U32) => do:
  if value == 0:
    return 0
  let child = #[value, value + 1]
  let values = @list.fill 500 child
  let before = values
  values := [#[value + 10, value + 20], ...self]
  let copied = @array.from_list values
  let old = @array.from_list before
  return old[0][1] + copied[0][1] + copied[500][0]
entry const clear = fn () => 0
entry const trapped = fn (value: U32) => do:
  let values = @list.fill 500 #[value]
  let copied = @array.from_list values
  return copied[501][0]
`;
Deno.test("source reference Arrays and persistent Lists preserve versions and retire typed invocation roots", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  try {
    for (const tier of ["development", "optimized"] as const) {
      const compiler = await createZigProjectCompiler({
        executable,
        entry,
        prelude: new URL("../../std/prelude.blot", import.meta.url),
        cacheDirectory: false,
        codegenTier: tier,
      });
      try {
        const result = await compiler.build({ sources: { [entry]: source } });
        assert(result.success, JSON.stringify(result));
        const r = await runtime(result.bytes);
        assert.deepEqual(r.mode, [2, 2, 0]);
        assert.equal(r.call("array_group", 41), 83);
        assert.equal(r.count("leases"), 0);
        assert(r.count("destroyed") > 0);
        if (tier === "development") assert(r.count("retains") > 0);
        assert.throws(() => r.call("trapped", 41), WebAssembly.RuntimeError);
        assert(r.count("leases") > 0);
        r.call("clear", 0);
        assert.equal(r.count("leases"), 0);
        for (const name of ["arrays", "lists"]) {
          for (const value of [41, 7, 41]) {
            const before = r.count("destroyed");
            assert.equal(r.call(name, value), 3 * value + 21);
            assert(r.count("destroyed") > before);
            assert.equal(r.count("roots"), 0);
            assert(r.count("retains") > 0);
            const retired = r.count("destroyed");
            r.call(name, 0);
            assert.equal(r.count("destroyed"), retired);
            assert.equal(r.count("leases"), 0);
          }
        }
      } finally {
        await compiler.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("private roots move fresh returns and retain borrowed children before closing frames", async () => {
  const r = await runtime();
  r.call("root_enter");
  r.call("root_open");
  const child = r.call("root_allocate", 4, 0);
  r.call("store_word", child, child, 42);
  const parent = r.call("root_allocate", 4, 1);
  r.call("store_word", parent, parent, child);
  assert.equal(r.roots(), 2);
  r.call("root_close", parent);
  assert.equal(r.roots(), 1);
  assert.equal(r.count("leases"), 1);
  r.call("root_open");
  r.call("root_close", child);
  assert.equal(r.roots(), 2);
  assert.equal(r.word(child - 16), 2);
  r.call("reset", 0);
  assert.equal(r.word(child), 42);
  r.call("root_leave", 0);
  assert.equal(r.roots(), 0);
  assert.equal(r.count("leases"), 0);
  assert.equal(r.count("destroyed"), 2);
  r.call("root_leave", 2);
});

Deno.test("frame markers transfer owning returns across journal page retirement", async () => {
  const r = await runtime();
  const capacity = Number(
    (r.exports.root_capacity as WebAssembly.Global).value,
  );
  let retired = r.count("destroyed");
  for (let attempt = 0; attempt < 3; attempt++) {
    r.call("root_enter");
    r.call("root_open");
    const returned = r.call("root_allocate", 4, 0);
    r.call("store_word", returned, returned, 42);
    for (let index = 0; index < capacity * 3; index++) {
      r.call("root_allocate", 4, 0);
    }
    r.call("root_close", returned);
    assert.equal(r.word(returned), 42);
    assert.equal(r.roots(), 1);
    assert.equal(r.count("leases"), 1);
    assert.equal(r.count("destroyed") - retired, capacity * 3);
    r.call("root_leave", 0);
    assert.equal(r.roots(), 0);
    assert.equal(r.count("leases"), 0);
    assert.equal(r.count("destroyed") - retired, capacity * 3 + 1);
    retired = r.count("destroyed");
  }
  r.call("root_leave", 2);
});

Deno.test("private root pages preserve module roots and retire nested failed invocations", async () => {
  const r = await runtime();
  const persistent = r.call("root_allocate", 4, 0);
  r.call("store_word", persistent, persistent, 42);
  for (let attempt = 0; attempt < 3; attempt++) {
    r.call("root_enter");
    r.call("root_open");
    for (let index = 0; index < 1024; index++) r.call("root_allocate", 4, 0);
    r.call("root_open");
    for (let index = 0; index < 1024; index++) r.call("root_allocate", 4, 0);
    r.call("root_leave", 1);
    assert.equal(r.roots(), 1);
    assert.equal(r.count("leases"), 1);
    r.call("reset", 0);
    assert.equal(r.word(persistent), 42);
  }
  r.call("root_leave", 2);
  assert.equal(r.roots(), 0);
  assert.equal(r.count("leases"), 0);
  assert.equal(r.count("destroyed"), 6145);
});

Deno.test("private roots clear original slots when local lifetime release consumes them", async () => {
  const r = await runtime();
  r.call("root_enter");
  const value = r.call("root_allocate", 4, 0);
  assert.equal(r.roots(), 1);
  r.call("release_lease", value);
  assert.equal(r.roots(), 0);
  r.call("root_leave", 0);
  assert.equal(r.count("destroyed"), 1);
  assert.throws(() => r.call("root_leave", 0), WebAssembly.RuntimeError);
  assert.throws(() => r.call("root_leave", 3), WebAssembly.RuntimeError);
  r.call("root_enter");
  assert.throws(() => r.call("root_enter"), WebAssembly.RuntimeError);
  assert.throws(() => r.call("root_leave", 2), WebAssembly.RuntimeError);
  r.call("root_leave", 1);
});

Deno.test("failed invocation frame reservation retires its empty prefix without touching module owners", async () => {
  const r = await runtime();
  const persistent = r.call("root_allocate", 4, 0);
  r.put(persistent, 42);
  const capacity = Number(
    (r.exports.root_capacity as WebAssembly.Global).value,
  );
  // Fill the page after its persistent owner. The marker requires growth;
  // the private allocator seam forces overflow before it can be published.
  for (let index = 1; index < capacity; index++) r.call("root_reserve");
  const heap = r.heap();
  r.setHeap(0xfffffff0);
  assert.throws(() => r.call("root_enter"), WebAssembly.RuntimeError);
  r.setHeap(heap);
  r.call("root_leave", 1);
  assert.equal(r.roots(), 1);
  assert.equal(r.count("leases"), 1);
  assert.equal(r.word(persistent), 42);
  const before = r.heap();
  r.call("root_enter");
  assert.equal(r.heap(), before, "empty suffix records retired before retry");
  r.call("root_leave", 0);
  assert.equal(r.roots(), 1);
  r.call("root_leave", 2);
  assert.equal(r.roots(), 0);
  assert.equal(r.count("leases"), 0);
});

Deno.test("force records distinguish exceptional terminal demands from canceled pending and ready memos", async () => {
  const r = await runtime();
  const { exports: e } = r;
  const memory = e["blot:memory"] as WebAssembly.Memory;
  const view = () => new DataView(memory.buffer);
  const force = e.root_force as CallableFunction;
  const enter = e.root_enter as CallableFunction;
  const leave = e.root_leave as CallableFunction;
  const allocate = e.root_allocate as CallableFunction;
  const staticDemand = Number((e.static_demand as WebAssembly.Global).value);
  for (const [state, outcome, expected] of [[1, 1, 3], [0, 0, 0], [2, 1, 2]]) {
    enter();
    const demand = allocate(16, 2);
    r.call("retain", demand);
    force(demand);
    view().setUint32(demand + 8, state, true);
    leave(outcome);
    assert.equal(view().getUint32(demand + 8, true), expected);
    r.call("release", demand);
    assert.equal((e.roots as WebAssembly.Global).value, 0);
    assert.equal((e["blot:rc_leases"] as WebAssembly.Global).value, 0);
  }
  enter();
  force(staticDemand);
  view().setUint32(staticDemand + 8, 1, true);
  leave(1);
  assert.equal(view().getUint32(staticDemand + 8, true), 3);
  assert.equal((e.roots as WebAssembly.Global).value, 0);
  leave(2);
});
