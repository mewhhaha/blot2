import { deepStrictEqual as equal } from "node:assert/strict";
import { Fifo } from "./fifo.ts";

Deno.test("FIFO preserves order across compaction, drain, and reuse", () => {
  const queue = new Fifo<number>();
  equal(queue.shift(), undefined);
  for (let cycle = 0; cycle < 8; cycle++) {
    for (let i = 0; i < 4096; i++) queue.push(i);
    for (let i = 0; i < 3072; i++) equal(queue.shift(), i);
    for (let i = 4096; i < 6144; i++) queue.push(i);
    for (let i = 3072; i < 6144; i++) equal(queue.shift(), i);
    equal(queue.length, 0);
    equal(queue.shift(), undefined);
  }
  queue.push(42);
  queue.clear();
  equal(queue.length, 0);
  queue.push(7);
  equal(queue.shift(), 7);
});

Deno.test("FIFO randomized operations match the array oracle including undefined", () => {
  const queue = new Fifo<number | undefined>();
  const oracle: (number | undefined)[] = [];
  let state = 0x12345678;
  for (let i = 0; i < 50000; i++) {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    if ((state & 15) === 0) {
      queue.clear();
      oracle.length = 0;
    } else if ((state & 3) !== 0) {
      const value = (state & 7) === 1 ? undefined : state;
      queue.push(value);
      oracle.push(value);
    } else {
      equal(queue.shift(), oracle.shift());
    }
    equal(queue.length, oracle.length);
  }
  while (oracle.length) equal(queue.shift(), oracle.shift());
});
