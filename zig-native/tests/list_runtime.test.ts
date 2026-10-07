import { deepStrictEqual, ok } from "node:assert/strict";
import { equal } from "./compile_helpers.ts";

const compiler = Deno.args[0] ?? new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const fixture = new URL("../list-runtime-fixture.wasm", new URL(compiler, `file://${Deno.cwd()}/`));
async function runtime() {
  const bytes = await Deno.readFile(fixture);
  ok(WebAssembly.validate(bytes));
  const { instance } = await WebAssembly.instantiate(bytes);
  const exports = instance.exports;
  const memory = exports["blot:memory"] as WebAssembly.Memory;
  const call = (name: string, ...args: number[]) => Number((exports[name] as CallableFunction)(...args)) >>> 0;
  const word = (address: number) => new DataView(memory.buffer).getUint32(address, true);
  const put = (address: number, value: number) => new DataView(memory.buffer).setUint32(address, value, true);
  const get = (list: number, index: number) => word(call("address", list, index));
  const create = (count: number) => {
    const list = call("new", count);
    for (let i = 0; i < count; i++) put(call("address", list, i), i);
    return list;
  };
  const inspect = (list: number) => {
    const chunks: number[] = [];
    const nodes = new Set<number>();
    const visit = (node: number): { size: number; height: number } => {
      ok(!nodes.has(node), "Tree nodes cannot cycle or repeat within one version");
      nodes.add(node);
      const height = word(node + 4), size = word(node + 8);
      if (height === 0) {
        chunks.push(node);
        const capacity = word(node + 12);
        ok(size > 0 && size <= capacity && capacity <= 248);
        for (let i = size; i < capacity; i++) equal(word(node + 16 + i * 4), 0);
      } else {
        const left = visit(word(node + 16)), right = visit(word(node + 20));
        equal(size, left.size + right.size);
        equal(height, Math.max(left.height, right.height) + 1);
        ok(Math.abs(left.height - right.height) <= 1, "AVL balance");
      }
      return { size, height };
    };
    const root = word(list + 4);
    equal(root ? visit(root).size : 0, word(list));
    return { chunks, nodes };
  };
  return { call, word, put, get, create, inspect };
}

Deno.test("list growth preserves balanced trees and dense leaves at boundaries", async () => {
  const r = await runtime();
  for (const size of [0, 1, 8, 9, 24, 25, 247, 248, 249, 255, 256, 257, 8191, 8192, 8193, 262143, 262144, 262145]) {
    const original = r.create(size);
    const appended = r.call("push", original, 0xfffffffe, 0, 0);
    const prepended = r.call("push", original, 0xffffffff, 1, 0);
    r.inspect(original); r.inspect(appended); r.inspect(prepended);
    equal(r.get(appended, size), 0xfffffffe);
    equal(r.get(prepended, 0), 0xffffffff);
    for (let i = 0; i < size; i++) {
      equal(r.get(original, i), i);
      equal(r.get(appended, i), i);
      equal(r.get(prepended, i + 1), i);
    }
  }
});

Deno.test("shared list edits detach a logarithmic spine before exclusive mutation", async () => {
  const r = await runtime();
  const original = r.create(1_000_000);
  const tree = r.inspect(original);
  const before = r.call("heap");
  const changed = r.call("set", original, 123456, 42, 0);
  const copiedBytes = r.call("heap") - before;
  ok(copiedBytes > 0 && copiedBytes < 4096, `Shared copy allocated ${copiedBytes} bytes`);
  const changedTree = r.inspect(changed);
  equal(changedTree.chunks.filter(p => tree.nodes.has(p)).length, tree.chunks.length - 1);
  equal(r.get(original, 123456), 123456);
  equal(r.get(changed, 123456), 42);
  // Either tree can subsequently be consumed without affecting the other.
  r.call("set", changed, 900000, 99, 1);
  equal(r.get(original, 900000), 900000);
  equal(r.get(changed, 900000), 99);
  // The original tree also remains independently writable.
  r.call("set", original, 500000, 77, 1);
  equal(r.get(changed, 500000), 500000);
  equal(r.get(original, 500000), 77);
  const uniqueHeap = r.call("heap");
  for (let i = 0; i < 100; i++) r.call("set", changed, 900000, i, 1);
  equal(r.call("heap"), uniqueHeap);
});

Deno.test("chunk copies and owned edits retain every observed version", async () => {
  const r = await runtime();
  let list = r.create(8200);
  let values = Array.from({ length: 8200 }, (_, i) => i);
  const snapshots: { list: number; values: number[] }[] = [];
  let random = 17;
  for (let step = 0; step < 2300; step++) {
    random = (Math.imul(random, 1664525) + 1013904223) >>> 0;
    const owned = step % 79 !== 0;
    if (!owned) snapshots.push({ list, values: [...values] });
    if (step % 3 === 0) {
      const index = random % values.length;
      list = r.call("set", list, index, random, +owned);
      values[index] = random;
    } else if (step % 3 === 1) {
      list = r.call("push", list, random, 1, +owned);
      values.unshift(random);
    } else {
      list = r.call("push", list, random, 0, +owned);
      values.push(random);
    }
    if (step % 101 === 0) r.inspect(list);
  }
  snapshots.push({ list, values });
  for (const snapshot of snapshots) {
    r.inspect(snapshot.list);
    deepStrictEqual(Array.from({ length: snapshot.values.length }, (_, i) => r.get(snapshot.list, i)), snapshot.values);
  }
});

Deno.test("chunk static values conversions empty values and private bounds preserve contents", async () => {
  const r = await runtime();
  const before = r.call("heap");
  const empty = r.call("new", 0);
  // Empty values reuse an immutable descriptor; tiny nonempty values detach it.
  const tinyBefore = r.call("heap");
  const tiny = r.create(1);
  ok(r.call("heap") - Math.max(tinyBefore, 65536) <= 128);
  ok(r.call("heap") > before);
  const frozen = r.call("static");
  const changed = r.call("set", frozen, 0, 42, 1);
  const extended = r.call("push", frozen, 99, 0, 1);
  equal(r.get(frozen, 0), 123);
  equal(r.word(frozen), 1);
  equal(r.get(changed, 0), 42);
  equal(r.get(extended, 1), 99);
  const copy = r.call("copy", tiny, 5);
  equal(r.word(copy), 5);
  for (let i = 0; i < 5; i++) equal(r.get(copy, i), 0);
  for (const size of [0, 1, 255, 256, 257, 8300]) {
    const source = r.create(size);
    const array = r.call("to_array", source);
    const restored = r.call("from_array", array);
    r.inspect(restored);
    for (let i = 0; i < size; i++) {
      equal(r.word(array + 4 + i * 4), i);
      equal(r.get(restored, i), i);
    }
    if (size) {
      r.call("set", restored, 0, 42, 1);
      equal(r.get(source, 0), 0);
      equal(r.word(array + 4), 0);
    }
  }
  for (const [name, args] of [["new", [0xffffffff]], ["address", [empty, 0]], ["set", [empty, 0, 42, 0]], ["copy", [tiny, 0]]] as const) {
    let trapped = false;
    try { r.call(name, ...args); } catch (e) { trapped = e instanceof WebAssembly.RuntimeError; }
    ok(trapped, name);
  }
});

Deno.test("empty lists allocate nothing and detach independently on writes", async () => {
  const r = await runtime();
  const before = r.call("heap");
  const first = r.call("new", 0), second = r.call("new", 0);
  equal(first, second);
  equal(r.call("slice", first, 0, 0), first);
  equal(r.call("concat", first, second), first);
  equal(r.call("heap"), before);
  const left = r.call("push", first, 11, 0, 1);
  const right = r.call("push", second, 22, 1, 1);
  equal(r.word(first), 0);
  equal(r.word(second), 0);
  equal(r.get(left, 0), 11);
  equal(r.get(right, 0), 22);
  const joined = r.call("concat", first, left);
  equal(r.word(first), 0);
  equal(r.get(joined, 0), 11);
});

Deno.test("unchanged shared list edits allocate nothing and preserve subsequent snapshots", async () => {
  const r = await runtime();
  const original = r.create(10000);
  const before = r.call("heap");
  const unchanged = r.call("set", original, 5000, 5000, 0);
  equal(r.call("heap"), before);
  const changed = r.call("set", unchanged, 5000, 42, 1);
  const extended = r.call("push", original, 99, 1, 1);
  equal(r.get(original, 5000), 5000);
  equal(r.get(unchanged, 5000), 5000);
  equal(r.get(changed, 5000), 42);
  equal(r.get(extended, 5001), 5000);
  equal(r.word(original), 10000);
  r.inspect(changed); r.inspect(extended);
});

Deno.test("list element layouts distinguish scalar bits from owned references during reclamation", async () => {
  for (const scalar of [true, false]) {
    const r = await runtime();
    const child = r.call("blot:allocate", 64);
    r.put(child, 123456);
    const original = r.call(scalar ? "new" : "new_references", 300);
    for (let i = 0; i < 300; i++) r.put(r.call("address", original, i), child);
    const sliced = r.call("slice", original, 37, 250);
    const changed = r.call("push", sliced, child, 0, 0);
    r.call("collect", changed);
    equal(r.get(changed, 0), child);
    equal(r.get(changed, 250), child);
    equal(r.word(child - 12), scalar ? 0 : 64);
    // A second pass must preserve the leaf's layout flag and reference values.
    r.call("collect", changed);
    equal(r.word(child - 12), scalar ? 0 : 64);
    if (!scalar) equal(r.word(r.get(changed, 100)), 123456);
  }
});

Deno.test("whole slices and concatenation with empty lists share without allocation", async () => {
  const r = await runtime();
  const original = r.create(5000), empty = r.call("new", 0);
  const before = r.call("heap");
  const full = r.call("slice", original, 0, 5000);
  const left = r.call("concat", empty, full), right = r.call("concat", full, empty);
  equal(r.call("heap"), before);
  const changed = r.call("set", left, 42, 99, 1);
  const appended = r.call("push", right, 77, 0, 1);
  equal(r.get(changed, 42), 99);
  equal(r.get(appended, 42), 42);
  equal(r.get(appended, 5000), 77);
  for (const snapshot of [original, full, left, right]) {
    equal(r.word(snapshot), 5000);
    equal(r.get(snapshot, 42), 42);
  }
});

Deno.test("owned list growth balances both ends with output-proportional allocation", async () => {
  const r = await runtime();
  let list = r.call("new", 0);
  const before = r.call("heap");
  const count = 300000;
  for (let i = 0; i < count; i++) list = r.call("push", list, i, i & 1, 1);
  const allocated = r.call("heap") - before;
  ok(allocated < count * 10, `Owned growth allocated ${allocated} bytes`);
  r.inspect(list);
  for (let i = 0; i < count / 2; i++) {
    equal(r.get(list, i), count - i * 2 - 1);
    equal(r.get(list, count / 2 + i), i * 2);
  }
});

Deno.test("structural slices share interior subtrees and detach boundary leaves", async () => {
  const r = await runtime();
  const original = r.create(1_000_000);
  const tree = r.inspect(original);
  let heap = r.call("heap");
  const sliced = r.call("slice", original, 123456, 100000);
  ok(r.call("heap") - heap < 8192, "A slice rebuilds only its boundary spines");
  const cut = r.inspect(sliced);
  ok(cut.chunks.some(node => tree.nodes.has(node)), "Covered leaves remain shared");
  equal(r.get(sliced, 0), 123456);
  equal(r.get(sliced, 99999), 223455);
  heap = r.call("heap");
  const tiny = r.call("slice", original, 123456, 1);
  ok(r.call("heap") - heap < 256, "A tiny slice owns a descriptor and small leaf");
  const tinyTree = r.inspect(tiny);
  equal(tinyTree.nodes.size, 1);
  ok(!tree.nodes.has(tinyTree.chunks[0]), "A partial leaf must not retain discarded neighbors");
  r.call("set", original, 125000, 77, 1);
  equal(r.get(sliced, 1544), 125000);
  r.call("set", sliced, 5000, 99, 1);
  equal(r.get(original, 128456), 128456);
  equal(r.get(tiny, 0), 123456);
  equal(r.word(r.call("slice", original, 1_000_000, 0)), 0);
});

Deno.test("structural concat balances unequal trees and preserves both operands", async () => {
  const r = await runtime();
  const left = r.create(200000), right = r.create(1000);
  const heap = r.call("heap");
  const joined = r.call("concat", left, right);
  ok(r.call("heap") - heap < 4096, "Concat must not flatten either tree");
  r.inspect(joined);
  equal(r.word(joined), 201000);
  for (const index of [0, 1, 247, 248, 99999, 199999]) equal(r.get(joined, index), index);
  for (const index of [0, 247, 248, 999]) equal(r.get(joined, 200000 + index), index);
  r.call("set", left, 500, 17, 1);
  r.call("set", right, 500, 18, 1);
  equal(r.get(joined, 500), 500);
  equal(r.get(joined, 200500), 500);
  r.call("set", joined, 500, 19, 1);
  equal(r.get(left, 500), 17);
  const repeated = r.call("concat", joined, joined);
  equal(r.get(repeated, 201500), 19);
  r.call("set", repeated, 500, 20, 1);
  equal(r.get(repeated, 201500), 19);
});

Deno.test("slicing and concatenating adversarial boundaries match flat sequence values", async () => {
  const r = await runtime();
  let list = r.create(8193);
  let values = Array.from({length: 8193}, (_, index) => index);
  let seed = 123;
  for (let step = 0; step < 400; step++) {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    const start = seed % (values.length + 1);
    const count = (seed >>> 12) % (values.length - start + 1);
    list = r.call("slice", list, start, count);
    values = values.slice(start, start + count);
    const extra = r.create(seed % 260);
    list = step % 2 ? r.call("concat", list, extra) : r.call("concat", extra, list);
    const added = Array.from({length: seed % 260}, (_, index) => index);
    values = step % 2 ? [...values, ...added] : [...added, ...values];
    r.inspect(list);
    equal(r.word(list), values.length);
    for (let i = 0; i < values.length; i++) equal(r.get(list, i), values[i]);
  }
});
