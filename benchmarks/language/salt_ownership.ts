import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { gdevProject } from "../../scripts/integration/gdev_project.ts";
import { instrumentMemoryTraffic } from "../tools/guest_copy_observer.ts";

const root = resolve(Deno.args[0] ?? "../gdev");
const compiler = await createZigProjectCompiler({
  ...await gdevProject(
    root,
    resolve("std"),
    "tests/salt_capacity_probe.blot",
    resolve("compiler-goose/build/blotc-goose"),
  ),
  frontendWorkers: 8,
});
const source = `import * as salt from "game/world/salt"
import * as math from "ink/math"
import * as pages from "ink/pages"
import * as fixture from "test/support/owned_world"
entry func measure (observe: U32 -> U32): U32 => return fixture.with_salt (func access => return do:
  access.salt.state[0].ready := true
  access.salt.state[0].cleaning_reset := false
  for i in 0 .. 8:
    access.salt := salt.drop_cargo 0 (math.vec3 (U32.to_f32 i * 4.0) 0.0 0.0) 1 self
  use observe 1
  access.salt.stacks := pages.truncate 6 self
  access.salt.active := pages.truncate 6 self
  access.salt.cleaning_updated := pages.truncate 6 self
  access.salt.state[0].stacks := 6
  access.salt.state[0].active := 6
  access.salt.state[0].cleaning_updated := 6
  use observe 2
  access.salt := salt.drop_cargo 0 (math.vec3 100.0 0.0 0.0) 2 self
  use observe 3
  return access.salt.stacks[6].id)
`;
try {
  const result = await compiler.build({
    sources: { [resolve(root, "tests/salt_capacity_probe.blot")]: source },
  });
  if (!result.success) throw Error(JSON.stringify(result.diagnostics));
  const module = new WebAssembly.Module(
    instrumentMemoryTraffic(result.bytes, { ownerTable: true }),
  );
  const observations: number[][][] = [];
  const instance = new WebAssembly.Instance(module, {
    "blot:host/1": {
      call_u32_u32(_callback: number, marker: number) {
        assert.equal(marker, observations.length + 1);
        const exports = instance.exports;
        const words = new Uint32Array(
          (exports["qual:memory"] as WebAssembly.Memory).buffer,
        );
        const top = Number(
          (exports["qual:owner_top"] as WebAssembly.Global).value,
        );
        const rows = [];
        for (let slot = 1; slot < top; slot++) {
          const at = 256 + 4 * slot;
          rows[slot] = Array.from(words.subarray(at, at + 4));
        }
        observations.push(rows);
        return 0;
      },
    },
  });
  const guest = instance.exports as Record<string, CallableFunction>;
  try {
    assert.equal(guest.measure(1), 9);
  } finally {
    guest["blot:finish_invocation"]();
  }
  assert.equal(observations.length, 3);
  const [before, shortened, appended] = observations;
  const retained = [];
  for (let slot = 1; slot < before.length; slot++) {
    const lengths = [
      before[slot][1],
      shortened[slot]?.[1],
      appended[slot]?.[1],
    ];
    if (lengths.join() !== "8,6,7") continue;
    const [address, , capacity, generation] = before[slot];
    assert(address > 0 && capacity > 0);
    for (const states of [shortened, appended]) {
      assert.deepEqual(states[slot], [
        address,
        states[slot][1],
        capacity,
        generation,
      ]);
    }
    retained.push({
      slot,
      address,
      capacityBytes: capacity & 0x3fffffff,
      generation,
      lengths,
    });
  }
  assert.equal(
    retained.length,
    3,
    "each pile, active-index and cleanup-journal buffer must keep its allocation",
  );
  console.log(JSON.stringify({ nextPileId: 9, retained }, null, 2));
} finally {
  await compiler.dispose();
}
