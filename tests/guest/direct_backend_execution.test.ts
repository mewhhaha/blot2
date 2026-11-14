// The direct backend (tasks/FAST_COMPILE.md) must run each fixture's entries
// to the same results as the scoped backend.
import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

type Call = [name: string, argument: number, expected: number];
const cases: Record<string, Call[]> = {
  "calls.blot": [["answer", 40, 42]],
  "data_and_control.blot": [
    ["shape_area", 0, 12],
    ["shape_area", 1, 12],
    ["shape_area", 2, 0],
    ["swapped", 3, 1003],
    ["record_field", 4, 5],
    ["maybe", 9, 18],
    ["maybe", 2, 7],
    ["generic", 3, 5.5],
    ["factorial", 5, 120],
    ["sum_to", 10, 38],
    ["first_big", 20, 8],
  ],
  "storage.blot": [
    ["sum_array", 10, 285],
    ["fixed", 7, 49],
    ["records", 5, 1002],
    ["views", 1, 91],
    ["copies", 9, 109],
    ["generated", 5, 16],
    ["returned", 3, 2003],
  ],
  "nested_updates.blot": [["run", 5, 609]],
  "inferred_types.blot": [["run", 5, 7], ["loopuse", 4, 9]],
  "dispatch.blot": [["ids", 3, 1], ["ids", 4, 0], ["vec", 1, 79]],
  "iterators.blot": [["chained", 1, 31], ["taken", 2, 26]],
  "open_codec.blot": [["run", 5, 12], ["written", 1, 3]],
  "policy_record.blot": [["run", 5, 17]],
  "boxed_records.blot": [
    ["fields", 5, 138],
    ["nested", 2, 69],
    ["stored", 4, 87],
    ["carried", 5, 105],
    ["chosen", 7, 14],
    ["chosen", 1, 1001],
  ],
  "view_calls.blot": [["run", 1, 25], ["run", 0, 3]],
  "comprehensions.blot": [
    ["comp", 10, 45],
    ["simple", 2, 15],
    ["guarded", 2, 7],
    ["from_view", 1, 9],
    ["nested", 4, 4],
  ],
  "unused_stages.blot": [["top", 4, 5], ["nested", 1, 7]],
  "simd_lanes.blot": [
    ["shuffled", 5, 6060],
    ["swizzled", 9, 4329],
    ["broadcast", 7, 28],
    ["shifted", 65536, 65856],
  ],
  "generated_from_filter.blot": [["run", 4, 308], ["run", 10, 508]],
  "empty_literals.blot": [["empty_generic", 5, 5], ["mixed", 3, 3]],
  "carried_owners.blot": [["plain", 10, 40], ["callbacks", 0, 12], ["stored", 5, 20]],
  "providers.blot": [
    ["nested", 1, 120],
    ["counted", 1, 42082],
    ["returned", 9, 799],
    ["returned", 1, 2099],
  ],
  "generic_comprehensions.blot": [
    ["annotated_count", 4, 3],
    ["generic_count", 4, 3],
    ["generic_view_count", 4, 3],
  ],
  "closures.blot": [
    ["offset_twice", 2, 6],
    ["partials", 1, 123],
    ["composed", 4, 15],
    ["counter", 10, 46],
    ["moved", 7, 1705],
    ["maybe_map", 21, 42],
    ["ctor_value", 5, 5],
  ],
};

async function build(fixture: string, backend: "direct" | "scoped") {
  const entry = new URL(`../../compiler/fixtures/direct/${fixture}`, import.meta.url).pathname;
  const compiler = await createZigProjectCompiler({
    executable: Deno.args[0],
    entry,
    prelude: new URL("../../std/prelude.blot", import.meta.url).pathname,
    stdRoot: new URL("../../std", import.meta.url).pathname,
    cacheDirectory: false,
    backend,
  });
  try {
    const built = await compiler.build({ signal: AbortSignal.timeout(20000) });
    if (!built.success) assert.fail(JSON.stringify(built));
    return await instantiateGuest(built.bytes);
  } finally {
    await compiler.close();
  }
}

for (const backend of ["direct", "scoped"] as const) {
  Deno.test(`global array pools persist across calls on the ${backend} backend`, async () => {
    const guest = await build("pools.blot", backend);
    assert.equal(guest.call("append", 5), 2);
    assert.equal(guest.call("append", 6), 3);
    assert.equal(guest.call("read", 0), 41);
    assert.equal(guest.call("read", 2), 6);
    assert.deepEqual(Array.from(guest.call("doubled", Uint32Array.of(1, 2, 3)) as Uint32Array), [2, 4, 6]);
    assert.equal(guest.call("scaled", Float32Array.of(0.5, 1.5, 2)), 4);
  });
  Deno.test(`exported constants on the ${backend} backend`, async () => {
    const guest = await build("constants.blot", backend);
    assert.equal(guest.read("answer"), 42);
    assert.equal(guest.read("unit_match"), 7);
    assert.equal(guest.read("flag"), true);
    assert.equal(guest.read("half"), 3);
    assert.equal(guest.call("add", 2), 42);
  });
  Deno.test(`Foreign callbacks exchange packets on the ${backend} backend`, async () => {
    const guest = await build("host.blot", backend);
    let calls = 0;
    const host = guest.capability({
      parameter: "Array F32",
      result: "Array F32",
      call: (packet: Float32Array) => {
        calls++;
        return Float32Array.from(packet, (value) => value * 2);
      },
    });
    assert.deepEqual(Array.from(guest.call("main", host) as Float32Array), [9.5, 3, 10]);
    assert.equal(calls, 2);
    const counter = guest.capability({ parameter: "U32", result: "U32", call: (value: number) => value + 1 });
    assert.equal(guest.call("scalar_host", counter), 43);
  });
}

// The scoped backend rejects these: generic function values every use
// leaves open, and array elements whose layout only an instance fixes.
const directOnly = new Set([
  "open_codec.blot",
  "policy_record.blot",
  "generic_comprehensions.blot",
  "generated_from_filter.blot",
  "carried_owners.blot",
]);
for (const [fixture, calls] of Object.entries(cases)) {
  for (const backend of ["direct", "scoped"] as const) {
    if (backend === "scoped" && directOnly.has(fixture)) continue;
    Deno.test(`${fixture} entries run on the ${backend} backend`, async () => {
      const guest = await build(fixture, backend);
      for (const [name, argument, expected] of calls) {
        assert.equal(guest.call(name, argument), expected, `${name} ${argument}`);
      }
    });
  }
}
