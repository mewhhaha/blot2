// Observe an actual Gdev terrain update through the ABI 8 owner table.
import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { gdevProject } from "../../scripts/integration/gdev_project.ts";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";

const root = resolve("../gdev");
const project = await gdevProject(
  root,
  resolve("std"),
  "src/terrain_owner_probe.blot",
  resolve(Deno.args[0] ?? "compiler-goose/build/blotc-goose"),
);
const source = `import * as trails from "game/world/trails"
import * as derived from "ink/derived/keyed"
import * as array from "std/array"
io lanes (): Array U32 => return #[0]
io probe (observe: U32 -> U32): U32 => return do:
  let initial = $derived.Revision {epoch: 3221225469, change: 17}
  let surface = $trails.SurfaceEpoch {ground: initial, clearings: initial, surface: initial, tiles: array.fill trails.surface_tile_count initial}
  let saved = trails.copy_surface surface
  let changed = array.fill trails.surface_tile_count false
  changed[0] := true
  use a <- observe 101
  surface := trails.surface_changed changed surface
  use b <- observe 102
  return @u32.add (@u32.add a b) (@u32.add (saved.tiles.at 0).change (surface.tiles.at 0).change)
`;
type TileOwner = {
  slot: number;
  address: number;
  length: number;
  generation: number;
  change: number;
};
const epoch = 3221225469;
function tiles(memory: WebAssembly.Memory): TileOwner[] {
  const u32 = new Uint32Array(memory.buffer);
  const owners: TileOwner[] = [];
  // ABI 8 reserves four words per owner after the 1024-byte prefix.
  for (let slot = 0; slot < 4096; slot++) {
    const header = 256 + slot * 4;
    const address = u32[header];
    const first = address / 4;
    const length = u32[header + 1];
    if (length !== 169 || !address || first + 3 >= u32.length) continue;
    if (u32[first + 1] !== epoch || u32[first + 3] !== epoch) continue;
    owners.push({
      slot,
      address,
      length,
      generation: u32[header + 3],
      change: u32[first],
    });
  }
  return owners;
}

const client = await createZigProjectCompiler(project);
try {
  const result = await client.build({ sources: { [project.entry]: source } });
  if (!result.success) throw Error(JSON.stringify(result.diagnostics));
  const module = await WebAssembly.compile(result.bytes);
  let instance: WebAssembly.Instance;
  const observations: { marker: number; owners: TileOwner[] }[] = [];
  const observe = (_handle: number, marker: number) => {
    const memory = instance.exports["blot:memory"];
    assert(memory instanceof WebAssembly.Memory);
    observations.push({ marker, owners: tiles(memory) });
    return 0;
  };
  assert.deepEqual(WebAssembly.Module.imports(module), [
    { module: "blot:host/1", name: "call_u32_u32", kind: "function" },
  ]);
  instance = await WebAssembly.instantiate(module, {
    "blot:host/1": { call_u32_u32: observe },
  });
  const probe = instance.exports.probe as (callback: number) => number;
  const checksum = probe(1);
  assert.equal(checksum, 35);
  assert.deepEqual(observations.map((s) => s.marker), [101, 102]);
  const [before, after] = observations.map((s) => s.owners);
  const updated = after.filter((x) => x.change === 18);
  assert.equal(updated.length, 1);
  const current = updated[0];
  assert.deepEqual(before.find((x) => x.slot === current.slot), {
    ...current,
    change: 17,
  });
  assert(
    after.some((x) =>
      x.slot !== current.slot && x.address !== current.address &&
      x.change === 17
    ),
  );
  console.log(JSON.stringify({ checksum, observations }));
} finally {
  await client.dispose();
}
