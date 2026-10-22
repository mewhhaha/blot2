import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { observeGuestAllocations } from "../../scripts/bench/guest_heap_observer.ts";

const source = `
import * as array from "std/array"
type Box is data = #Box { a: U32, b: U32 }
const fields = fn value => { a: value, b: value + 1 }
const read = fn row => row.a + row.b
const named = read
const apply = fn callback row => callback row
const boxed = fn value => #Box { a: value, b: value + 1 }
const read_box = fn (row: Box) => row.a + row.b
entry const direct = fn value => do:
  let row = fields value
  break row.a + row.b
entry const helper = fn value => read (fields value)
entry const named_callback = fn value => named (fields value)
entry const inline_callback = fn value => apply (fn row => row.a + row.b) (fields value)
entry const generic_callback = fn value => apply read (fields value)
entry const nominal_record = fn value => read_box (boxed value)
const replace = array.replace
const wrapped_replace = fn index value values => replace index value values
const direct_wrapper = fn index value values => array.replace index value values
const reordered_wrapper = fn values index value => array.replace index value values
entry const list_build = fn count => do:
  let values: List U32 = []
  for index in 0..count:
    values := [...self, index]
  break values.length
entry const array_generate = fn count => do:
  let values = array.generate count (fn index => index + 1)
  break values[count - 1]
entry const update_direct = fn count => do:
  let values = array.fill count 0
  for index in 0..count:
    values := array.replace index (index + 1) values
  break values[count - 1]
entry const update_wrapped = fn count => do:
  let values = array.fill count 0
  for index in 0..count:
    values := wrapped_replace index (index + 1) values
  break values[count - 1]
entry const update_direct_wrapper = fn count => do:
  let values = array.fill count 0
  for index in 0..count:
    values := direct_wrapper index (index + 1) values
  break values[count - 1]
entry const update_reordered_wrapper = fn count => do:
  let values = array.fill count 0
  for index in 0..count:
    values := reordered_wrapper values index (index + 1)
  break values[count - 1]
entry const update_snapshot = fn count => do:
  let values = array.fill count 0
  let previous = values
  for index in 0..count:
    values := array.replace index (index + 1) values
  break values[count - 1] + previous[count - 1]
`;

Deno.test("allocation cost matrix keeps equivalent results and measures size scaling in both tiers", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-cost-matrix-" });
  const entry = `${directory}/main.blot`;
  const executable = Deno.args[0] ??
    new URL("../zig-out/bin/blotc", import.meta.url);
  try {
    for (const codegenTier of ["development", "optimized"] as const) {
      const compiler = await createZigProjectCompiler({
        executable,
        entry,
        prelude: new URL("../../std/prelude.blot", import.meta.url),
        stdRoot: new URL("../../std", import.meta.url),
        cacheDirectory: false,
        codegenTier,
      });
      try {
        const result = await compiler.build({ sources: { [entry]: source } });
        assert(result.success, JSON.stringify(result));
        const rows: Array<
          & { name: string; input: number }
          & ReturnType<typeof observeGuestAllocations>
        > = [];
        for (
          const name of [
            "direct",
            "helper",
            "named_callback",
            "inline_callback",
            "generic_callback",
            "nominal_record",
          ]
        ) {
          const traffic = observeGuestAllocations(result.bytes, [[
            name,
            5,
            11,
          ]]);
          rows.push({ name, input: 5, ...traffic });
        }
        for (const count of [32, 128, 512]) {
          for (
            const name of [
              "list_build",
              "array_generate",
              "update_direct",
              "update_wrapped",
              "update_direct_wrapper",
              "update_reordered_wrapper",
              "update_snapshot",
            ]
          ) {
            const traffic = observeGuestAllocations(result.bytes, [[
              name,
              count,
              count,
            ]]);
            rows.push({ name, input: count, ...traffic });
          }
        }
        const traffic = (name: string, input: number) =>
          rows.find((row) => row.name === name && row.input === input)!;
        for (const count of [32, 128, 512]) {
          const direct = traffic("update_direct", count);
          for (
            const name of [
              "update_wrapped",
              "update_direct_wrapper",
              "update_reordered_wrapper",
            ]
          ) {
            const wrapped = traffic(name, count);
            assert.equal(
              wrapped.rounded_allocation_bytes,
              direct.rounded_allocation_bytes,
              `${codegenTier} ${name} ${count}`,
            );
            assert.equal(
              wrapped.retains,
              direct.retains,
              `${codegenTier} ${name} ${count}`,
            );
            assert.equal(
              wrapped.releases,
              direct.releases,
              `${codegenTier} ${name} ${count}`,
            );
          }
          assert(
            traffic("update_snapshot", count).rounded_allocation_bytes >
              direct.rounded_allocation_bytes * 10,
          );
        }
        for (const name of ["list_build", "array_generate"]) {
          const small = traffic(name, 32).rounded_allocation_bytes;
          const medium = traffic(name, 128).rounded_allocation_bytes;
          const large = traffic(name, 512).rounded_allocation_bytes;
          assert(
            small > 0,
            `${codegenTier} ${name} has no observed construction cost`,
          );
          assert(
            medium <= small * 8,
            `${codegenTier} ${name} grew faster than linear allowance at 128`,
          );
          assert(
            large <= medium * 8,
            `${codegenTier} ${name} grew faster than linear allowance at 512`,
          );
        }
        if (codegenTier === "optimized") {
          const changedSource = source.replace(
            "const wrapped_replace = fn index value values => replace index value values",
            "const wrapped_replace = fn index value values => replace index (value + 1) values",
          );
          assert.notEqual(changedSource, source);
          const changed = await compiler.build({
            sources: { [entry]: changedSource },
          });
          assert(changed.success, JSON.stringify(changed));
          const changedTraffic = observeGuestAllocations(changed.bytes, [[
            "update_wrapped",
            32,
            33,
          ]]);
          assert(
            changedTraffic.rounded_allocation_bytes >
              traffic("update_wrapped", 32).rounded_allocation_bytes,
          );
          const restored = await compiler.build({
            sources: { [entry]: source },
          });
          assert(restored.success, JSON.stringify(restored));
          assert.deepEqual(restored.bytes, result.bytes);
        }
        console.log(JSON.stringify({ codegenTier, rows }));
      } finally {
        await compiler.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
