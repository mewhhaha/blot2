import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
import { observeGuestAllocations } from "../../scripts/bench/guest_heap_observer.ts";
import {
  numericAggregateSources,
  numericShapes,
} from "../../scripts/bench/numeric_aggregates.ts";

Deno.test("numeric aggregates preserve imported calls, lane order and immutable array snapshots", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-numeric-rows-" });
  const entry = `${directory}/main.blot`, library = `${directory}/shapes.blot`;
  const fixture = numericAggregateSources();
  const main = fixture.main + numericShapes.map(([shape]) => `
entry const array_dynamic_${shape} = fn (choice: Bool) => do:
  let read = if choice then shape.read_${shape} else shape.alternate_${shape}
  let values = @array.generate 32 (fn index => shape.make_${shape} (@u32.to_f32 index))
  let total = 0.0
  for value in values:
    total := self + read value
  return total
entry const escaped_${shape} = fn (count: U32) => do:
  let values = @array.generate count (fn index => shape.make_${shape} (@u32.to_f32 index))
  let selected = shape.make_${shape} 0.0
  for value in values:
    selected := value
  return shape.read_${shape} selected
entry const captured_${shape} = fn (count: U32) => do:
  let matrix = shape.make_${shape} 5.0
  let rows = @array.generate count (fn index => matrix)
  return shape.read_${shape} matrix + shape.read_${shape} rows[count - 1]
entry const interrupted_${shape} = fn (count: U32) => do:
  let rows = @array.generate count (fn index => if index == 1 then @panic "interrupted row" else shape.make_${shape} 0.0)
  return @array.length rows
entry const stored_bits_${shape} = fn (seed: F32) => do:
  let rows = @array.fill 1 (shape.make_${shape} 0.0)
  rows[0].${shape.endsWith("nested") ? "a.x" : "ax"} := seed
  return shape.wire_${shape} rows[0]
`).join("");
  const sources = { [entry]: main, [library]: fixture.shapes };
  const executable = Deno.args[0] ??
    new URL("../zig-out/bin/blotc", import.meta.url);
  try {
    await Deno.writeTextFile(entry, main);
    await Deno.writeTextFile(library, fixture.shapes);
    for (const codegenTier of ["development", "optimized"] as const) {
      const options = {
        executable,
        entry,
        stdRoot: new URL("../../std", import.meta.url),
        prelude: new URL("../../std/prelude.blot", import.meta.url),
        cacheDirectory: false as const,
        codegenTier,
      };
      const compiler = await createZigProjectCompiler(options);
      try {
        const first = await compiler.build({ sources });
        assert(first.success, JSON.stringify(first));
        const guest = await instantiateGuest(first.bytes);
        try {
          for (const [shape] of numericShapes) {
            assert.equal(guest.call(`array_${shape}`, 0), 0);
            assert.equal(guest.call(`escaped_${shape}`, 0), 120);
            for (const seed of [-0, 1.5, -1000, 16777216]) {
              const lanes = Array.from(
                { length: 16 },
                (_, i) => Math.fround(seed + i),
              );
              const total = lanes.reduce((a, b) => Math.fround(a + b));
              assert.equal(guest.call(`direct_${shape}`, seed), total);
              assert.equal(guest.call(`callback_${shape}`, seed), total);
              assert.deepEqual(
                [...guest.call(`wire_${shape}`, seed) as Float32Array],
                lanes,
              );
              assert.deepEqual(
                [...guest.call(`stored_wire_${shape}`, seed) as Float32Array],
                lanes,
              );
              const stored = guest.call(
                `stored_bits_${shape}`,
                seed,
              ) as Float32Array;
              const expected = Float32Array.from([
                seed,
                ...Array.from({ length: 15 }, (_, i) => i + 1),
              ]);
              assert.deepEqual(
                new Uint32Array(
                  stored.buffer,
                  stored.byteOffset,
                  stored.length,
                ),
                new Uint32Array(expected.buffer),
              );
              const edited = [
                seed,
                ...Array.from({ length: 15 }, (_, i) => i + 2),
              ]
                .reduce((a, b) => Math.fround(a + b));
              assert.equal(
                guest.call(`nested_edit_${shape}`, seed),
                Math.fround(edited + 136),
              );
            }
            for (const choice of [false, true]) {
              assert.equal(guest.call(`dynamic_${shape}`, choice), 200);
              assert.equal(guest.call(`array_dynamic_${shape}`, choice), 11776);
            }
            for (const count of [1, 32, 33, 128, 129, 512]) {
              const traffic = observeGuestAllocations(first.bytes, [[
                `array_${shape}`,
                count,
                8 * count * count + 112 * count,
              ], [`snapshot_${shape}`, count, 16240]]);
              assert(traffic.committed_bytes > 0);
              assert.equal(
                guest.call(`escaped_${shape}`, count),
                16 * count + 104,
              );
              assert.equal(guest.call(`captured_${shape}`, count), 400);
              assert.equal(
                guest.call(`list_${shape}`, count),
                8 * count * count + 112 * count + 16120,
              );
            }
            assert.equal(guest.call(`constant_${shape}`, null), 136);
            observeGuestAllocations(first.bytes, [[
              `interrupted_${shape}`,
              2,
              "trap",
            ]]);
            if (codegenTier === "optimized") {
              // Function-valued callbacks keep their conservative ABI. This
              // representation law concerns the newly exposed direct calls.
              for (const call of ["direct"]) {
                const traffic = observeGuestAllocations(first.bytes, [[
                  `${call}_${shape}`,
                  call === "dynamic" ? 1 : 5,
                  200,
                ]]);
                assert.equal(
                  traffic.rounded_allocation_bytes,
                  0,
                  `${call}_${shape}`,
                );
                assert.equal(traffic.retains, 0);
                assert.equal(traffic.releases, 0);
              }
            }
          }
        } finally {
          guest.dispose();
        }
        const rejected = await compiler.build({
          sources: {
            ...sources,
            [entry]: main +
              "\nentry const wrong = fn () => shape.read_nominal_nested (shape.make_nominal_flat 0.0)\n",
          },
        });
        assert(!rejected.success, "distinct nominal matrices must not unify");
        const changedSources = {
          ...sources,
          [library]: fixture.shapes.replaceAll("seed + 15.0", "seed + 16.0"),
        };
        const changed = await compiler.build({ sources: changedSources });
        assert(changed.success, JSON.stringify(changed));
        const fresh = await createZigProjectCompiler(options);
        try {
          const control = await fresh.build({ sources: changedSources });
          assert(control.success, JSON.stringify(control));
          assert.deepEqual(changed.bytes, control.bytes);
        } finally {
          await fresh.dispose();
        }
        const restored = await compiler.build({ sources });
        assert(restored.success, JSON.stringify(restored));
        assert.deepEqual(restored.bytes, first.bytes);
      } finally {
        await compiler.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
