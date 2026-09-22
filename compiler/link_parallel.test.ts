import { deepStrictEqual as equal, ok } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { bendArray, type BendList, bendList } from "./bend_list.ts";

type Node = { readonly $: string; readonly [field: string]: unknown };
type Result = { readonly $: "Done"; readonly value: BendList<Node> } | {
  readonly $: "Fail";
  readonly error: Node;
};
const backend = compiled as unknown as {
  "wasm.link_bodies_with_grain"(
    grain: bigint,
    jobs: BendList<Node>,
    entries: BendList<Node>,
    symbols: Node,
    imports: bigint,
  ): Result;
};
const symbols: Node = {
  $: "Catalog",
  entries: { $: "MTip" },
  constructors: { $: "MTip" },
  constants: { $: "MTip" },
  operations: { $: "MTip" },
};
const job = (key: string): Node => ({
  $: "CodegenJob",
  key,
  parameter: "value",
  body: { $: "U32Expr", value: 42 },
  captures: bendList([]),
});
const entry = (key: string, fragments: Node[]): Node => ({
  $: "EntryCode",
  key,
  code: { $: "Code", fragments: bendList(fragments), locals: 0n },
});
const link = (grain: bigint, jobs: Node[], entries: Node[]) =>
  backend["wasm.link_bodies_with_grain"](
    grain,
    bendList(jobs),
    bendList(entries),
    symbols,
    2n,
  );

Deno.test("parallel relocation preserves uneven function order and exact body chunks", () => {
  const jobs = Array.from({ length: 31 }, (_, index) => job(`fn:${index}`));
  const entries = jobs.map((job, index) =>
    entry(
      String(job.key),
      Array.from(
        { length: 1 + index * 3 },
        () => ({ $: "Bytes", bytes: bendList([65, index]) }),
      ),
    )
  );
  const serial = link(1000000n, jobs, entries);
  ok(serial.$ === "Done");
  equal(bendArray(serial.value).length, jobs.length);
  for (const grain of [1n, 16n, 256n]) {
    equal(link(grain, jobs, entries), serial);
  }
  equal(link(1n, [], []), { $: "Done", value: bendList([]) });
});

Deno.test("parallel relocation preserves name, relocation and count failure precedence", () => {
  const jobs = [job("first"), job("second")];
  const good = entry("first", [{ $: "Bytes", bytes: bendList([65, 42]) }]);
  const bad = entry("first", [{ $: "NamedCall", key: "missing" }]);
  for (
    const entries of [
      [bad, entry("wrong", [])],
      [entry("wrong", []), bad],
      [bad],
      [good],
      [good, entry("second", []), entry("extra", [])],
      [],
    ]
  ) {
    const serial = link(1000000n, jobs, entries);
    ok(serial.$ === "Fail");
    equal(link(1n, jobs, entries), serial);
  }
  const missing = link(1n, jobs, [bad]);
  ok(missing.$ === "Fail");
  equal(missing.error.subject, "missing");
  const wrong = link(1n, jobs, [entry("wrong", [])]);
  ok(wrong.$ === "Fail");
  equal(wrong.error.subject, "first");
});
