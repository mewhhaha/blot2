import { deepStrictEqual, ok } from "node:assert/strict";
import { equal } from "./compile_helpers.ts";

const compiler = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const fixture = new URL(
  "../list-runtime-fixture.wasm",
  new URL(compiler, `file://${Deno.cwd()}/`),
);
async function runtime() {
  const bytes = await Deno.readFile(fixture);
  ok(WebAssembly.validate(bytes));
  const { instance } = await WebAssembly.instantiate(bytes);
  const exports = instance.exports;
  const memory = exports["blot:memory"] as WebAssembly.Memory;
  const call = (name: string, ...args: number[]) =>
    Number((exports[name] as CallableFunction)(...args)) >>> 0;
  const word = (address: number) =>
    new DataView(memory.buffer).getUint32(address, true);
  const put = (address: number, value: number) =>
    new DataView(memory.buffer).setUint32(address, value, true);
  const get = (list: number, index: number) =>
    word(call("address", list, index));
  const create = (count: number) => {
    const list = call("new", count);
    for (let i = 0; i < count; i++) put(call("address", list, i), i);
    return list;
  };
  const inspect = (list: number) => {
    const chunks: number[] = [];
    const nodes = new Set<number>();
    const visit = (node: number): { size: number; height: number } => {
      ok(
        !nodes.has(node),
        "Tree nodes cannot cycle or repeat within one version",
      );
      nodes.add(node);
      const height = word(node + 4), size = word(node + 8);
      if (height === 0) {
        chunks.push(node);
        const capacity = word(node + 12);
        ok(size > 0 && size <= capacity && capacity <= 244);
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

Deno.test("row-aligned leaf limits survive construction, conversion, empty edits and persistent snapshots", async () => {
  const r = await runtime();
  const capacity = r.call("capacity");
  const verify = (list: number, width: number) => {
    const limit = Math.floor(capacity / width) * width;
    equal(r.word(list + 24), limit);
    const visit = (node: number): number => {
      const length = r.word(node + 8);
      equal(length % width, 0);
      if (r.word(node + 4) === 0) {
        ok(length > 0 && length <= limit);
        return length;
      }
      equal(visit(r.word(node + 16)) + visit(r.word(node + 20)), length);
      return length;
    };
    const root = r.word(list + 4);
    equal(root === 0 ? 0 : visit(root), r.word(list));
  };
  for (let width = 1; width <= 16; width++) {
    const limit = Math.floor(capacity / width) * width;
    // Keep a one-row first leaf: its adjacent full leaf cannot coalesce.
    const full = r.call("new_limit", limit * 3, width, limit);
    const short = r.call("slice", full, limit - width, limit + width * 2);
    verify(short, width);
    let first = r.word(short + 4);
    while (r.word(first + 4) !== 0) first = r.word(first + 16);
    equal(r.word(first + 8), width);
    verify(r.call("concat", short, r.call("slice", short, 0, 0)), width);
    verify(full, width);
    const source = r.call("new_limit", 400 * width, width, limit);
    for (let i = 0; i < 400 * width; i++) {
      r.put(r.call("address", source, i), i);
    }
    verify(source, width);
    const copy = r.call("copy", source, 404 * width);
    verify(copy, width);
    const array = r.call("to_array", source);
    r.put(array, 400);
    const converted = r.call("from_array_rows", array, width);
    verify(converted, width);
    for (let i = 0; i < 400 * width; i++) equal(r.get(converted, i), i);
    const empty = r.call("slice", source, 0, 0);
    verify(empty, width);
    verify(r.call("concat", empty, empty), width);
    const emptyArray = r.call("to_array", empty);
    verify(r.call("from_array_rows", emptyArray, width), width);
    let list = empty;
    for (let a = 0; a < 6; a++) {
      for (let b = 0; b < 8; b++) {
        const part = r.call(
          "slice",
          source,
          (a * 47 + b * 5) * width,
          (1 + a + b * 2) * width,
        );
        list = r.call("concat", list, part);
        verify(list, width);
        const saved = list;
        for (const front of [0, 1]) {
          for (let field = 0; field < width; field++) {
            list = r.call("push", list, field, front, 0);
          }
          verify(list, width);
        }
        list = r.call("slice", list, width, r.word(saved));
        verify(list, width);
        verify(saved, width);
      }
    }
    for (let row = 0; row < 300; row++) {
      for (let field = 0; field < width; field++) {
        list = r.call("push", list, field, 0, 1);
      }
    }
    verify(list, width);
    verify(source, width);
    verify(copy, width);
    verify(converted, width);
    verify(empty, width);
    let fresh = r.call("new_limit", 0, width, limit);
    for (let row = 0; row < 300; row++) {
      for (let field = 0; field < width; field++) {
        fresh = r.call("push", fresh, field, row % 2, 1);
      }
    }
    verify(fresh, width);
  }
  const singleArray = r.call("to_array", r.create(1));
  let wideTrapped = false;
  try {
    r.call("from_array_rows", singleArray, 17);
  } catch (error) {
    wideTrapped = error instanceof WebAssembly.RuntimeError;
  }
  ok(wideTrapped);
  for (const leafLimit of [0, capacity + 1]) {
    let trapped = false;
    try {
      r.call("new_limit", 1, 1, leafLimit);
    } catch (error) {
      trapped = error instanceof WebAssembly.RuntimeError;
    }
    ok(trapped);
  }
});

Deno.test("packed constructors fill their leaf directories during existing tree construction", async () => {
  const r = await runtime();
  const capacity = r.call("capacity");
  for (let width = 2; width <= 16; width++) {
    const limit = Math.floor(capacity / width) * width;
    for (
      const rows of [
        0,
        1,
        limit / width - 1,
        limit / width,
        limit / width + 1,
        limit / width * 3 + 5,
      ]
    ) {
      const list = r.call("new_limit", rows * width, width, limit);
      equal(r.word(list + 16), width);
      const directory = r.word(list + 28);
      if (rows <= limit / width) {
        equal(directory, 0);
        if (rows !== 0) {
          const heap = r.call("heap");
          equal(r.call("directory", list), list);
          equal(r.word(list + 4), r.inspect(list).chunks[0]);
          equal(r.call("heap"), heap);
        }
        continue;
      }
      ok(
        directory !== 0,
        "Packed leaf creation supplies the directory before the first read",
      );
      const chunks = r.inspect(list).chunks;
      equal(r.word(directory), Math.ceil(rows * width / limit));
      equal(r.word(directory), chunks.length);
      for (let i = 0; i < chunks.length; i++) {
        equal(r.word(directory + 4 + i * 4), chunks[i]);
      }
      const heap = r.call("heap");
      equal(r.call("directory", list), directory);
      equal(r.call("heap"), heap);
    }
  }
  for (const scalar of [true, false]) {
    const list = r.call(scalar ? "new" : "new_references", 10000);
    equal(r.word(list + 28), 0);
  }
});

Deno.test("leaf directories follow descriptor snapshots and scalar borrowing through reclamation", async () => {
  const r = await runtime();
  const verify = (list: number) => {
    const chunks = r.inspect(list).chunks;
    const directory = r.call("directory", list);
    equal(r.word(directory), chunks.length);
    for (let i = 0; i < chunks.length; i++) {
      equal(r.word(directory + 4 + i * 4), chunks[i]);
    }
    return directory;
  };
  const empty = r.call("new", 0);
  const emptyHeap = r.call("heap");
  equal(r.call("directory", empty), 0);
  equal(r.call("heap"), emptyHeap);
  const original = r.create(10000);
  const directory = verify(original);
  equal(r.word(original + 28), directory);
  const cachedHeap = r.call("heap");
  equal(verify(original), directory);
  equal(r.call("heap"), cachedHeap);
  const unchanged = r.call("set", original, 5000, 5000, 0);
  equal(unchanged, original);
  equal(r.word(unchanged + 28), directory);
  equal(r.call("heap"), cachedHeap);
  let changed = r.call("set", original, 5000, 77, 0);
  equal(r.word(changed + 28), 0);
  equal(r.word(original + 28), directory);
  const changedDirectory = verify(changed);
  ok(changedDirectory !== directory);
  equal(r.get(original, 5000), 5000);
  equal(r.get(changed, 5000), 77);
  changed = r.call("push", changed, 88, 0, 1);
  equal(r.word(changed + 28), 0);
  equal(r.word(original + 28), directory);
  verify(changed);
  const copied = r.call("copy", original, 10000);
  equal(r.word(copied + 28), 0);
  verify(copied);
  const sliced = r.call("slice", original, 247, 400);
  equal(r.word(sliced + 28), 0);
  verify(sliced);
  const joined = r.call("concat", sliced, copied);
  equal(r.word(joined + 28), 0);
  verify(joined);
  const staticList = r.call("static");
  const firstStatic = verify(staticList);
  equal(r.word(staticList + 28), 0);
  equal(firstStatic, staticList);
  equal(verify(staticList), firstStatic);
  const staticMany = r.call("slice", original, 0, 1000);
  // A static descriptor with several leaves exercises the permanent cache
  // in source execution laws; this fixture's static value has one leaf.
  verify(staticMany);
  r.call("collect", original);
  equal(verify(original), directory);
  for (const index of [0, 247, 248, 5000, 9999]) {
    equal(r.get(original, index), index);
  }
  // Scalar leaf bases are borrowed addresses, not independent owning edges.
  const orphan = r.create(1000);
  const orphanLeaves = r.inspect(orphan).chunks;
  const orphanDirectory = verify(orphan);
  r.call("collect", orphanDirectory);
  for (const leaf of orphanLeaves) equal(r.word(leaf - 12), 0);
  equal(r.word(orphanDirectory), orphanLeaves.length);
});

Deno.test("list growth preserves balanced trees and dense leaves at boundaries", async () => {
  const r = await runtime();
  for (
    const size of [
      0,
      1,
      8,
      9,
      24,
      25,
      243,
      244,
      245,
      255,
      256,
      257,
      8191,
      8192,
      8193,
      262143,
      262144,
      262145,
    ]
  ) {
    const original = r.create(size);
    const appended = r.call("push", original, 0xfffffffe, 0, 0);
    const prepended = r.call("push", original, 0xffffffff, 1, 0);
    r.inspect(original);
    r.inspect(appended);
    r.inspect(prepended);
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
  ok(
    copiedBytes > 0 && copiedBytes < 4096,
    `Shared copy allocated ${copiedBytes} bytes`,
  );
  const changedTree = r.inspect(changed);
  equal(
    changedTree.chunks.filter((p) => tree.nodes.has(p)).length,
    tree.chunks.length - 1,
  );
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
    deepStrictEqual(
      Array.from(
        { length: snapshot.values.length },
        (_, i) => r.get(snapshot.list, i),
      ),
      snapshot.values,
    );
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
  for (
    const [name, args] of [["new", [0xffffffff]], ["address", [empty, 0]], [
      "set",
      [empty, 0, 42, 0],
    ], ["copy", [tiny, 0]]] as const
  ) {
    let trapped = false;
    try {
      r.call(name, ...args);
    } catch (e) {
      trapped = e instanceof WebAssembly.RuntimeError;
    }
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
  r.inspect(changed);
  r.inspect(extended);
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
    equal(r.word(child - 28), scalar ? 0 : 64);
    // A second pass must preserve the leaf's layout flag and reference values.
    r.call("collect", changed);
    equal(r.word(child - 28), scalar ? 0 : 64);
    if (!scalar) equal(r.word(r.get(changed, 100)), 123456);
  }
});

Deno.test("whole slices and concatenation with empty lists share without allocation", async () => {
  const r = await runtime();
  const original = r.create(5000), empty = r.call("new", 0);
  const before = r.call("heap");
  const full = r.call("slice", original, 0, 5000);
  const left = r.call("concat", empty, full),
    right = r.call("concat", full, empty);
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
  ok(
    cut.chunks.some((node) => tree.nodes.has(node)),
    "Covered leaves remain shared",
  );
  equal(r.get(sliced, 0), 123456);
  equal(r.get(sliced, 99999), 223455);
  heap = r.call("heap");
  const tiny = r.call("slice", original, 123456, 1);
  ok(
    r.call("heap") - heap < 256,
    "A tiny slice owns a descriptor and small leaf",
  );
  const tinyTree = r.inspect(tiny);
  equal(tinyTree.nodes.size, 1);
  ok(
    !tree.nodes.has(tinyTree.chunks[0]),
    "A partial leaf must not retain discarded neighbors",
  );
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
  for (const index of [0, 1, 247, 248, 99999, 199999]) {
    equal(r.get(joined, index), index);
  }
  for (const index of [0, 247, 248, 999]) {
    equal(r.get(joined, 200000 + index), index);
  }
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
  let values = Array.from({ length: 8193 }, (_, index) => index);
  let seed = 123;
  for (let step = 0; step < 400; step++) {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    const start = seed % (values.length + 1);
    const count = (seed >>> 12) % (values.length - start + 1);
    list = r.call("slice", list, start, count);
    values = values.slice(start, start + count);
    const extra = r.create(seed % 260);
    list = step % 2
      ? r.call("concat", list, extra)
      : r.call("concat", extra, list);
    const added = Array.from({ length: seed % 260 }, (_, index) => index);
    values = step % 2 ? [...values, ...added] : [...added, ...values];
    r.inspect(list);
    equal(r.word(list), values.length);
    for (let i = 0; i < values.length; i++) equal(r.get(list, i), values[i]);
  }
});

Deno.test("regular directory lookup counts duplicate leaf occurrences and declines irregular prefixes", async () => {
  const r = await runtime();
  const capacity = r.call("capacity");
  const leaves = (list: number) => {
    const ordered: { node: number; base: number; count: number }[] = [];
    let base = 0;
    const visit = (node: number) => {
      if (r.word(node + 4) !== 0) {
        visit(r.word(node + 16));
        visit(r.word(node + 20));
        return;
      }
      const count = r.word(node + 8);
      ordered.push({ node, base, count });
      base += count;
    };
    if (r.word(list + 4)) visit(r.word(list + 4));
    equal(base, r.word(list));
    return ordered;
  };
  const verify = (list: number, expected: number[]) => {
    const ordered = leaves(list);
    const directory = r.call("directory", list);
    if (ordered.length > 1) {
      equal(r.word(directory), ordered.length);
      ordered.forEach(({ node }, index) => {
        equal(r.word(directory + 4 + index * 4), node);
      });
    }
    for (const { node, base, count } of ordered) {
      for (let i = 0; i < count; i++) {
        equal(r.get(list, base + i), expected[base + i]);
        equal(r.word(list + 8), node);
        equal(r.word(list + 12), base);
      }
    }
  };
  const original = r.create(capacity * 3);
  const values = Array.from({ length: capacity * 3 }, (_, i) => i);
  const repeated = r.call("concat", original, original);
  const ordered = leaves(repeated);
  ok(new Set(ordered.map(({ node }) => node)).size < ordered.length);
  verify(repeated, [...values, ...values]);
  for (const start of [1, capacity - 1, capacity + 1]) {
    const part = r.call("slice", original, start, capacity + 7);
    const partValues = values.slice(start, start + capacity + 7);
    const twice = r.call("concat", part, part);
    verify(twice, [...partValues, ...partValues]);
  }
});

Deno.test("mixed concat limits bound both ordered leaf families before directory lookup", async () => {
  const r = await runtime();
  const capacity = r.call("capacity");
  for (const [leftWidth, rightWidth] of [[7, 3], [3, 7], [13, 1], [1, 13]]) {
    const leftLimit = Math.floor(capacity / leftWidth) * leftWidth;
    const rightLimit = Math.floor(capacity / rightWidth) * rightWidth;
    const leftCount = leftLimit * 2 + 17;
    const rightCount = rightLimit * 2 + 23;
    const left = r.call("new_limit", leftCount, leftWidth, leftLimit);
    const right = r.call("new_limit", rightCount, rightWidth, rightLimit);
    for (let i = 0; i < leftCount; i++) r.put(r.call("address", left, i), i);
    for (let i = 0; i < rightCount; i++) {
      r.put(r.call("address", right, i), 10000 + i);
    }
    const joined = r.call("concat", left, right);
    equal(r.word(joined + 24), Math.max(leftLimit, rightLimit));
    r.call("directory", joined);
    for (let i = 0; i < leftCount + rightCount; i++) {
      let expected = i;
      if (i >= leftCount) expected = 10000 + i - leftCount;
      equal(r.get(joined, i), expected);
    }
  }
});

Deno.test("small mixed leaf limits keep joined nodes within the descriptor bound", async () => {
  const r = await runtime();
  for (
    const [leftLimit, rightLimit] of [[1, 1], [3, 7], [7, 3], [17, 31], [
      31,
      17,
    ]]
  ) {
    for (
      const [leftCount, rightCount] of [[leftLimit, rightLimit], [
        leftLimit * 3 + 1,
        rightLimit * 3 + 1,
      ]]
    ) {
      const left = r.call("new_limit", leftCount, 1, leftLimit);
      const right = r.call("new_limit", rightCount, 1, rightLimit);
      const joined = r.call("concat", left, right);
      const bound = Math.max(leftLimit, rightLimit);
      equal(r.word(joined + 24), bound);
      for (const leaf of r.inspect(joined).chunks) {
        ok(r.word(leaf + 8) <= bound);
      }
      r.call("directory", joined);
      for (let index = 0; index < r.word(joined); index++) {
        equal(r.get(joined, index), 0);
      }
    }
  }
});
