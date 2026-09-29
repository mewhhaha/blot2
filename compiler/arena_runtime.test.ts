import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import generated from "../generated/compiler/compiler.js";

type List = { $: "Nil" } | { $: "Con"; head: number; tail: List };
const backend = generated as unknown as Record<
  string,
  (imports: bigint) => List
>;
const leb = (value: number): number[] =>
  value < 128
    ? [value]
    : [(value & 127) | 128, ...leb(Math.floor(value / 128))];
const sized = (value: number[]) => [...leb(value.length), ...value];
const name = (value: string) => sized([...new TextEncoder().encode(value)]);
const section = (id: number, payload: number[]) => [id, ...sized(payload)];
function body(key: string): number[] {
  const result: number[] = [];
  for (
    let list = backend[`arena_runtime.${key}`](0n);
    list.$ === "Con";
    list = list.tail
  ) {
    result.push(list.head);
  }
  return sized(result);
}
async function arena() {
  const bytes = new Uint8Array([
    0,
    97,
    115,
    109,
    1,
    0,
    0,
    0,
    ...section(1, [2, 96, 3, 127, 127, 127, 1, 127, 96, 1, 127, 1, 127]),
    ...section(3, [3, 1, 0, 0]),
    ...section(5, [1, 1, 1, ...leb(65536)]),
    ...section(6, [1, 127, 1, 65, 128, 2, 11]),
    ...section(7, [
      3,
      ...name("allocate"),
      0,
      0,
      ...name("collect"),
      0,
      2,
      ...name("memory"),
      2,
      0,
    ]),
    ...section(10, [
      3,
      ...body("allocate"),
      ...body("mark"),
      ...body("collect"),
    ]),
  ]);
  const { instance } = await WebAssembly.instantiate(bytes);
  const memory = instance.exports.memory as WebAssembly.Memory;
  return {
    allocate: instance.exports.allocate as (bytes: number) => number,
    collect: instance.exports.collect as (
      root: number,
      floor: number,
      unused: number,
    ) => number,
    memory,
    read: (pointer: number) =>
      new DataView(memory.buffer).getUint32(pointer, true),
    write: (pointer: number, value: number) =>
      new DataView(memory.buffer).setUint32(pointer, value, true),
  };
}

Deno.test("arena collector retains pinned edges, shared cycles, and exact scalar bits", async () => {
  const a = await arena();
  const pinned = a.allocate(4), floor = a.allocate(0);
  const first = a.allocate(8), second = a.allocate(4);
  a.write(pinned, first);
  a.write(first, second);
  a.write(first + 4, 0x7fc01234);
  a.write(second, first);
  equal(a.collect(0, floor, 0), 0);
  equal(a.read(pinned), first);
  equal(a.read(first), second);
  equal(a.read(first + 4), 0x7fc01234);
  equal(a.read(second), first);
  a.write(pinned, 0);
  a.collect(0, floor, 0);
  const cursor = a.allocate(0);
  const reused = [a.allocate(8), a.allocate(4)];
  equal(new Set(reused), new Set([first, second]));
  equal(a.allocate(0), cursor);
});

Deno.test("arena collector rejects interior addresses and preserves conservative pointer collisions", async () => {
  const a = await arena();
  const floor = a.allocate(0), object = a.allocate(16);
  a.write(object, 42);
  a.collect(object + 4, floor, 0);
  equal(a.allocate(16), object, "an interior scalar is not an allocation root");
  const holder = a.allocate(8);
  a.write(holder, object); // May equally represent U32 bits: never rewrite it.
  a.write(holder + 4, object);
  a.collect(holder, floor, 0);
  equal(a.read(holder), object);
  equal(a.read(holder + 4), object);
  equal(a.read(object), 42);
});

Deno.test("arena collection reuses a bounded nested graph over 10000 iterations", async () => {
  const a = await arena();
  const pinned = a.allocate(4), floor = a.allocate(0);
  a.write(pinned, 7);
  for (let turn = 0; turn < 10000; turn++) {
    const child = a.allocate(4096), root = a.allocate(12);
    a.write(child, turn);
    a.write(root, child);
    a.write(root + 4, child);
    a.write(root + 8, pinned);
    equal(a.collect(root, floor, 0), root);
    equal(a.read(a.read(root)), turn);
    equal(a.read(root), a.read(root + 4));
    equal(a.read(pinned), 7);
  }
  ok(a.memory.buffer.byteLength <= 128 * 1024);
  const before = a.allocate(0);
  throws(() => a.allocate(0xffffffff), WebAssembly.RuntimeError);
  equal(a.allocate(0), before, "failed allocation does not advance the cursor");
});

Deno.test("arena reserves the first page without advancing on failed first allocation", async () => {
  const a = await arena();
  const floor = a.allocate(0);
  equal(floor, 256);
  throws(() => a.allocate(0xffffffff), WebAssembly.RuntimeError);
  equal(a.allocate(0), floor);
  equal(a.read(4), 0);
  equal(a.read(12), 0);
  const first = a.allocate(4);
  ok(first >= 65536 + 16);
  equal(a.read(4), first - 16);
  a.write(first, 42);
  // A small integer that formerly coincided with the first payload is not a root.
  a.collect(272, floor, 0);
  equal(a.allocate(4), first);
});

Deno.test("arena caches block starts across reuse and rebuilds them after bump allocation", async () => {
  const a = await arena();
  const pinned = a.allocate(4), floor = a.allocate(0);
  a.write(pinned, 0);
  const child = a.allocate(4), root = a.allocate(8), dead = a.allocate(8);
  a.write(child, 42);
  a.write(root, child);
  a.write(root + 4, 7);
  a.write(dead, 0);
  a.write(dead + 4, 0);
  a.collect(root, floor, 0);
  const indexed = a.allocate(0);
  equal(a.read(12), indexed);
  const reused = a.allocate(8);
  equal(reused, dead);
  equal(a.allocate(0), indexed);
  equal(a.read(12), indexed, "free-bin reuse preserves physical block starts");
  a.write(reused, child);
  a.write(reused + 4, 11);
  a.write(root, reused);
  for (let turn = 0; turn < 3; turn++) {
    a.collect(root, floor, 0);
    equal(a.read(12), indexed);
    equal(a.read(a.read(a.read(root))), 42);
  }
  const nestedFloor = a.allocate(0);
  const inner = a.allocate(1024);
  equal(a.read(12), 0, "a fresh block invalidates the cached bitmap");
  a.write(inner, 99);
  a.collect(inner, nestedFloor, 0);
  equal(a.read(inner), 99);
  equal(
    a.read(a.read(a.read(root))),
    42,
    "nested collection retains pinned outer edges",
  );
  equal(a.read(12), a.allocate(0));
  a.collect(root, floor, 0);
  equal(
    a.allocate(1024),
    inner,
    "the outer collection releases the inner temporary",
  );
  const fresh = a.allocate(8192);
  equal(a.read(12), 0);
  a.write(fresh, child);
  a.write(root + 4, fresh);
  a.collect(root, floor, 0);
  equal(a.read(12), a.allocate(0));
  equal(a.read(a.read(a.read(root))), 42);
  equal(a.read(a.read(fresh)), 42);
});

Deno.test("arena leaf layouts skip scalar collisions and survive marking and bin reuse", async () => {
  const a = await arena();
  const floor = a.allocate(0);
  const scalar = a.allocate(4), child = a.allocate(4);
  a.write(scalar - 8, 2); // Compiler-proven pointer-free payload.
  a.write(scalar, child); // Numerically equals a pointer, but is scalar data.
  a.write(child, 42);
  a.collect(scalar, floor, 0);
  equal(a.read(scalar - 8), 2, "sweep must preserve the leaf layout bit");
  equal(a.read(scalar), child, "scalar bits are never rewritten");
  equal(
    a.allocate(4),
    child,
    "a leaf's scalar collision must not retain a child",
  );
  a.write(child, 99);
  a.collect(child, floor, 0);
  equal(a.allocate(4), scalar);
  equal(a.read(scalar - 8), 0, "reuse must reset the previous leaf layout");
  a.write(scalar, child);
  a.collect(scalar, floor, 0);
  equal(
    a.read(child - 12),
    4,
    "a reused pointerful object must trace its child",
  );
  equal(a.read(child), 99);
  a.collect(0, floor, 0);
  equal(new Set([a.allocate(4), a.allocate(4)]), new Set([scalar, child]));
});

Deno.test("arena mixed leaf graphs match exact reachability across collections", async () => {
  const a = await arena();
  const pinned = a.allocate(16), floor = a.allocate(0);
  const objects = new Map<number, { leaf: boolean; words: number[] }>();
  objects.set(pinned, { leaf: false, words: [0, 0, 0, 0] });
  let random = 0x12345678;
  const next = () => random = (Math.imul(random, 1664525) + 1013904223) >>> 0;
  for (let turn = 0; turn < 80; turn++) {
    for (let index = 0; index < 24; index++) {
      const pointer = a.allocate(16);
      equal(a.read(pointer - 8), 0);
      const leaf = (next() & 3) === 0;
      a.write(pointer - 8, leaf ? 2 : 0);
      objects.set(pointer, { leaf, words: [0, 0, 0, 0] });
    }
    const pointers = [...objects.keys()];
    for (const [pointer, object] of objects) {
      object.words = object.words.map(() => {
        // Leaves deliberately contain pointer-looking scalar values too.
        const n = next();
        return (n & 7) < 3 ? pointers[n % pointers.length] : n | 1;
      });
      object.words.forEach((word, index) => a.write(pointer + index * 4, word));
    }
    const root = pointers[next() % pointers.length];
    const live = new Set<number>();
    const pending = [pinned, root];
    while (pending.length) {
      const pointer = pending.pop()!;
      if (live.has(pointer)) continue;
      const object = objects.get(pointer);
      if (!object) continue;
      live.add(pointer);
      if (!object.leaf) pending.push(...object.words);
    }
    equal(a.collect(root, floor, 0), root);
    for (const [pointer, object] of objects) {
      equal(a.read(pointer - 12) !== 0, live.has(pointer));
      if (live.has(pointer)) {
        equal(a.read(pointer - 8), object.leaf ? 2 : 0);
        object.words.forEach((word, index) =>
          equal(a.read(pointer + index * 4), word >>> 0)
        );
      } else objects.delete(pointer);
    }
  }
});

Deno.test("arena collector retains dynamic graphs cached in static memo cells", async () => {
  const a = await arena();
  const memo = 256;
  a.write(16, memo);
  a.write(memo, 2);
  a.write(memo + 4, 0);
  a.write(memo + 12, 0);
  const value = a.allocate(8);
  a.write(value, 42);
  a.write(memo + 8, value);
  a.collect(0, 65536, 0);
  const next = a.allocate(8);
  ok(next !== value);
  equal(a.read(value), 42);
  a.write(memo + 8, 0);
  a.collect(next, 65536, 0);
  equal(a.allocate(8), value);
});
