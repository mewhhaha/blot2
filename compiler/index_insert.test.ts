import { deepStrictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";

// Compare the complete Patricia tree, not just successful lookups. Existing
// serialization and deterministic diagnostics rely on the same traversal order.
const index = compiled as unknown as {
  "index.set"(map: unknown, key: string, value: bigint): unknown;
  "index.set_reference"(map: unknown, key: string, value: bigint): unknown;
  "index.find"(map: unknown, key: string): unknown;
};

Deno.test("symbol insertion preserves exact Base.Map shape, Unicode, overwrites and snapshots", () => {
  const keys = [
    "",
    "a",
    "aa",
    "ab",
    "\0",
    "a\0",
    "a\0x",
    "é",
    "e\u0301",
    "🦆",
    "𐀀",
    "日本語",
    "\uffff",
    String.fromCodePoint(0x10ffff),
    ...Array.from({ length: 128 }, (_, i) => "namespace/".repeat(12) + i),
  ];
  let seed = 123456789;
  const next = () => seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
  for (let i = 0; i < 256; i++) {
    keys.push(
      String.fromCodePoint(0x10000 + next() % 0x100000) + "/" + next() % 128,
    );
  }
  for (const ordered of [keys, [...keys].reverse()]) {
    let current: unknown = { $: "MTip" };
    let reference: unknown = { $: "MTip" };
    const retained: [unknown, unknown][] = [];
    for (let i = 0; i < ordered.length * 2; i++) {
      const key = ordered[i % ordered.length];
      const value = BigInt(i);
      const snapshot = structuredClone(current);
      const updated = index["index.set"](current, key, value);
      reference = index["index.set_reference"](reference, key, value);
      equal(updated, reference, `insertion ${i}: ${JSON.stringify(key)}`);
      equal(current, snapshot, "input map was mutated");
      if (i % 31 === 0) retained.push([current, snapshot]);
      current = updated;
    }
    for (
      const key of [
        ...ordered,
        "$missing",
        ...ordered.map((s) => s + "missing"),
      ]
    ) {
      equal(
        index["index.find"](current, key),
        index["index.find"](reference, key),
      );
    }
    for (const [map, snapshot] of retained) equal(map, snapshot);
  }
});
