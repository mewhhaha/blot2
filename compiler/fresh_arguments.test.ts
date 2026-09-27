import { deepStrictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";

type Arguments = { readonly $: "Nil" } | {
  readonly $: "Con";
  readonly head: { readonly $: "model.VariableTy"; readonly index: bigint };
  readonly tail: Arguments;
};

const types = compiled as unknown as {
  "type_data.fresh_arguments"(count: bigint, start: bigint): Arguments;
};

Deno.test("fresh type arguments retain ascending identities after a small warm call", () => {
  const start = 0x100000003n;
  for (const count of [0, 1, 128, 8192]) {
    let cursor = types["type_data.fresh_arguments"](BigInt(count), start);
    let index = 0;
    while (cursor.$ === "Con") {
      equal(cursor.head, {
        $: "model.VariableTy",
        index: start + BigInt(index),
      });
      index++;
      cursor = cursor.tail;
    }
    equal(index, count);
  }
  equal(types["type_data.fresh_arguments"](0n, 0xFFFFFFFFFFFFn), { $: "Nil" });
});
