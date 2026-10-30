import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { observeGuestAllocations } from "../../scripts/bench/guest_heap_observer.ts";

const source = `
import * as array from "std/array"
type Box is data = #Box { a: U32, b: U32 }
const fields = func value => return { a: value, b: value + 1 }
const read = func row => return row.a + row.b
const named = read
const apply = func callback -> row => return callback row
const boxed = func value => return #Box { a: value, b: value + 1 }
const read_box = func (row: Box) => return row.a + row.b
entry const direct = func value => return do:
  let row = fields value
  break row.a + row.b
entry const helper = func value => return read (fields value)
entry const named_callback = func value => return named (fields value)
entry const inline_callback = func value => return apply (func row => return row.a + row.b) (fields value)
entry const generic_callback = func value => return apply read (fields value)
entry const aliased_callback = func value => return apply named (fields value)
entry const local_callback = func value => return do:
  let callback = func row => return row.a + row.b
  break apply callback (fields value)
entry const nominal_record = func value => return read_box (boxed value)
const replace = array.replace
const wrapped_replace = func index -> value -> values => return replace index value values
const direct_wrapper = func index -> value -> values => return array.replace index value values
const reordered_wrapper = func values -> index -> value => return array.replace index value values
entry const list_build = func count => return do:
  let values: List U32 = []
  for index in 0..count:
    values := [...self, index]
  break values.length
entry const array_generate = func count => return do:
  let values = array.generate count (func index => return index + 1)
  break values[count - 1]
entry const update_direct = func count => return do:
  let values = array.fill count 0
  for index in 0..count:
    values := array.replace index (index + 1) values
  break values[count - 1]
entry const update_wrapped = func count => return do:
  let values = array.fill count 0
  for index in 0..count:
    values := wrapped_replace index (index + 1) values
  break values[count - 1]
entry const update_direct_wrapper = func count => return do:
  let values = array.fill count 0
  for index in 0..count:
    values := direct_wrapper index (index + 1) values
  break values[count - 1]
entry const update_reordered_wrapper = func count => return do:
  let values = array.fill count 0
  for index in 0..count:
    values := reordered_wrapper values index (index + 1)
  break values[count - 1]
entry const update_snapshot = func count => return do:
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
            "aliased_callback",
            "local_callback",
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
        assert.equal(
          traffic("local_callback", 5).rounded_allocation_bytes,
          traffic("inline_callback", 5).rounded_allocation_bytes,
          `${codegenTier} locally bound callback cost differs from inline callback`,
        );
        assert.equal(
          traffic("aliased_callback", 5).rounded_allocation_bytes,
          traffic("generic_callback", 5).rounded_allocation_bytes,
          `${codegenTier} global alias cost differs from generic callback`,
        );
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
          for (
            const name of [
              "generic_callback",
              "aliased_callback",
            ]
          ) {
            assert.equal(
              traffic(name, 5).rounded_allocation_bytes,
              traffic("local_callback", 5).rounded_allocation_bytes,
              `${name} retained a global callable adapter allocation`,
            );
          }
          const changedSource = source.replace(
            "const wrapped_replace = func index -> value -> values => return replace index value values",
            "const wrapped_replace = func index -> value -> values => return replace index (value + 1) values",
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
