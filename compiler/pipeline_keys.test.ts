import { deepStrictEqual as equal, notStrictEqual } from "node:assert/strict";
import { structuralKey } from "./pipeline.ts";

Deno.test("compilation cache keys distinguish signed zero and every non-finite value", () => {
  const values = [0, -0, Infinity, -Infinity, NaN, null, "NaN", 1, 1n];
  equal(new Set(values.map(structuralKey)).size, values.length);
  for (const value of values) {
    equal(structuralKey({ value }), structuralKey({ value }));
  }
  notStrictEqual(
    structuralKey({ $: "F32Value", value: 0 }),
    structuralKey({ $: "F32Value", value: -0 }),
  );
});

Deno.test("compilation cache keys preserve representable NaN payload distinctions", () => {
  const bits = new DataView(new ArrayBuffer(8));
  bits.setUint32(0, 0x7ff80000);
  bits.setUint32(4, 1);
  const first = bits.getFloat64(0);
  bits.setUint32(4, 2);
  const second = bits.getFloat64(0);
  notStrictEqual(structuralKey(first), structuralKey(second));
});
