import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../compiler/guest.ts";
import { compileAndRun } from "./reduction_helpers.ts";

const stdRoot = new URL("../../std", import.meta.url).pathname;
const source = `
entry const snapshots = func (count: U32) => return do:
  let cursor = { index: 0, limit: count }
  let original = cursor
  let total = 0
  for index in 0..count:
    let saved = cursor
    if index == 7:
      break
    cursor := { index: self.index + 1, limit: self.limit }
    total := self + saved.index + cursor.index
  break #[total, original.index, cursor.index, cursor.limit]
entry const nested = func (count: U32) => return do:
  let total = 0
  for outer in 0..count:
    let cursor = { index: outer, limit: count }
    for inner in 0..3:
      let old = cursor
      cursor := { index: self.index + inner, limit: self.limit }
      total := self + old.index + cursor.index
  break total
entry const captured = func (count: U32) => return do:
  let cursor = { index: count, limit: count + 1 }
  let read = func () => return cursor.index
  cursor := { index: 999, limit: self.limit }
  break read () + cursor.index
entry const references = func (seed: U32) => return do:
  let cursor = { value: #[seed, seed + 1], index: 0 }
  let saved = cursor
  cursor := { value: #[99, 100], index: 1 }
  for index in 0..64:
    let pressure = @array.fill 8192 index
    if pressure[8191] != index:
      @panic "pressure"
  break #[saved.value[saved.index], cursor.value[cursor.index]]
entry const suspend = func (host: U32 -> U32 ! {Foreign}) => return do:
  let cursor = { index: 41, limit: 99 }
  let saved = cursor
  use next <- host cursor.index
  cursor := { index: next, limit: self.limit }
  break #[saved.index, cursor.index, saved.limit, cursor.limit]
`;

Deno.test("scalar cursor locals preserve forks branch exits nested activations and heap fallback", async () => {
  await compileAndRun(source, (guest, bytes) => {
    assert.deepEqual([
      ...new Uint8Array(
        WebAssembly.Module.customSections(
          new WebAssembly.Module(bytes),
          "blot:ownership",
        )[0],
      ),
    ], [2, 2, 0]);
    for (const count of [0, 1, 3, 7, 8, 64]) {
      const iterations = Math.min(count, 7);
      assert.deepEqual(
        guest.call("snapshots", count),
        Uint32Array.of(iterations * iterations, 0, iterations, count),
      );
      let total = 0;
      for (let outer = 0; outer < count; outer++) {
        let current = outer;
        for (let inner = 0; inner < 3; inner++) {
          const old = current;
          current += inner;
          total += old + current;
        }
      }
      assert.equal(guest.call("nested", count), total);
      assert.equal(guest.call("captured", count), count + 999);
    }
    for (const seed of [0, 8192, 65536]) {
      assert.deepEqual(
        guest.call("references", seed),
        Uint32Array.of(seed, 100),
      );
    }
  }, { stdRoot });
});

Deno.test("scalar cursor snapshots survive host suspension rejection and cleanup in both host modes", async () => {
  await compileAndRun(source, async (_, bytes) => {
    for (const asynchronous of [false, true]) {
      const guest = await instantiateGuest(bytes, { asynchronous });
      try {
        let capability;
        let rejected;
        if (asynchronous) {
          capability = guest.capabilityAsync({
            parameter: "U32",
            result: "U32",
            call: async (value) => {
              await Promise.resolve();
              return value + 1;
            },
          });
          rejected = guest.capabilityAsync({
            parameter: "U32",
            result: "U32",
            call: async () => {
              throw new Error("cursor host");
            },
          });
        } else {
          capability = guest.capability({
            parameter: "U32",
            result: "U32",
            call: (value) => value + 1,
          });
          rejected = guest.capability({
            parameter: "U32",
            result: "U32",
            call: () => {
              throw new Error("cursor host");
            },
          });
        }
        const expected = Uint32Array.of(41, 42, 99, 99);
        if (asynchronous) {
          assert.deepEqual(
            await guest.callAsync("suspend", capability),
            expected,
          );
        } else assert.deepEqual(guest.call("suspend", capability), expected);
        if (asynchronous) {
          await assert.rejects(guest.callAsync("suspend", rejected));
        } else assert.throws(() => guest.call("suspend", rejected));
        if (asynchronous) {
          assert.equal(await guest.callAsync("captured", 41), 1040);
        } else assert.equal(guest.call("captured", 41), 1040);
        if (asynchronous) {
          assert.deepEqual(
            await guest.callAsync("suspend", capability),
            expected,
          );
        } else assert.deepEqual(guest.call("suspend", capability), expected);
      } finally {
        guest.dispose();
      }
    }
  }, { stdRoot });
});
