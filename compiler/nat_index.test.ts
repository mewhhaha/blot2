import { strictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";

interface NatIndex {
  "nat_index.new"(): unknown;
  "nat_index.set"(index: unknown, key: bigint, value: bigint): unknown;
  "nat_index.get"(index: unknown, key: bigint, otherwise: bigint): bigint;
}

const index = compiled as unknown as NatIndex;
const limit = (1n << 48n) - 1n;

Deno.test("numeric Patricia index preserves snapshots and Nat48 boundary keys", () => {
  const keys = [0n, 1n, 2n, (1n << 47n) - 1n, 1n << 47n, limit];
  let current = index["nat_index.new"]();
  const snapshots = [current];
  for (let position = 0; position < keys.length; position++) {
    current = index["nat_index.set"](
      current,
      keys[position],
      BigInt(position + 1),
    );
    snapshots.push(current);
  }
  for (let count = 0; count <= keys.length; count++) {
    for (let position = 0; position < keys.length; position++) {
      equal(
        index["nat_index.get"](snapshots[count], keys[position], 99n),
        position < count ? BigInt(position + 1) : 99n,
      );
    }
  }
  const replaced = index["nat_index.set"](current, 1n, 77n);
  equal(index["nat_index.get"](replaced, 1n, 99n), 77n);
  equal(index["nat_index.get"](current, 1n, 99n), 2n);
});

Deno.test("numeric Patricia index agrees with Map through mixed updates and reads", () => {
  let state = 0x12345678n;
  const random = () => {
    state = (state * 1664525n + 1013904223n) & 0xffffffffn;
    return state;
  };
  const expected = new Map<bigint, bigint>();
  let current = index["nat_index.new"]();
  for (let step = 0; step < 600; step++) {
    const key = step % 23 === 0 ? limit - BigInt(step) : random() % 257n;
    const value = BigInt(step + 1);
    current = index["nat_index.set"](current, key, value);
    expected.set(key, value);
    for (let probe = 0; probe < 4; probe++) {
      const query = probe === 0
        ? key
        : probe === 1
        ? limit - BigInt(step)
        : random() % 257n;
      equal(
        index["nat_index.get"](current, query, 0n),
        expected.get(query) ?? 0n,
      );
    }
  }
});
