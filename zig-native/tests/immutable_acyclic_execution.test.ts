import { strict as assert } from "node:assert";
import { compileAndRun } from "./compile_helpers.ts";

const tree = `
const grow = fn (count: U32) => do:
  let root: Link = #End
  for index in 0..count:
    root := #Next (self, index)
  return root
entry const run = fn (count: U32) => do:
  let original = grow count
  let changed = #Next (original, 8192)
  let saved = case original of
    #End => 0
    #Next (_, value) => value
  return case changed of
    #End => 0
    #Next (tail, value) => case tail of
      #End => 0
      #Next (_, latest) => @u32.add value (@u32.add latest saved)
entry const memory = fn () -> Array U32 => #[]
`;

function inspect(bytes: Uint8Array<ArrayBuffer>, acyclic: boolean) {
  const module = new WebAssembly.Module(bytes);
  assert.deepEqual([
    ...new Uint8Array(
      WebAssembly.Module.customSections(module, "blot:ownership")[0],
    ),
  ], [2, 2, 0]);
  const raw = new WebAssembly.Instance(module).exports;
  const count = (name: string) =>
    Number((raw[`blot:${name}`] as WebAssembly.Global).value);
  const run = raw.run as CallableFunction;
  assert.equal(run(8192), 8192 + 8191 * 2);
  const memory = raw["blot:memory"] as WebAssembly.Memory;
  const warm = memory.buffer.byteLength;
  const destroyed = count("rc_destroyed");
  for (let iteration = 0; iteration < 8; iteration++) {
    assert.equal(run(4096), 8192 + 4095 * 2);
    assert.equal(memory.buffer.byteLength, warm);
    assert.equal(count("rc_roots"), 0);
    assert.equal(count("rc_leases"), 0);
  }
  assert(count("rc_destroyed") > destroyed, "aliases must retire iteratively");
  if (acyclic) {
    for (const name of ["cycle_passes", "cycle_vertices", "cycle_edges"]) {
      assert.equal(count(name), 0, "immutable trees must avoid trial scans");
    }
  } else {
    assert(
      count("cycle_vertices") > 0,
      "foreign shapes must decline the proof",
    );
  }
  (raw["blot:ownership_leave"] as CallableFunction)(2);
}

Deno.test("immutable source trees preserve aliases and skip all trial work", async () => {
  await compileAndRun(
    "type Link is data = #End | #Next (Link, U32)\n" + tree,
    (_, bytes) => inspect(bytes, true),
  );
});

Deno.test("foreign constructor definitions retain conservative cycle work", async () => {
  const directory = await Deno.makeTempDir({
    dir: new URL("../../build", import.meta.url).pathname,
    prefix: "blot-acyclic-owner-",
  });
  try {
    await Deno.writeTextFile(
      `${directory}/link.blot`,
      "type Link is data = #End | #Next (Link, U32)\n",
    );
    await Deno.writeTextFile(
      `${directory}/main.blot`,
      'import * as link from "./link"\n' +
        tree.replaceAll("Link", "link.Link").replaceAll("#End", "#link.End")
          .replaceAll("#Next", "#link.Next"),
    );
    const compiler = Deno.args[0] ??
      new URL("../zig-out/bin/blotc", import.meta.url).pathname;
    const output = `${directory}/main.wasm`;
    const result = await new Deno.Command(compiler, {
      args: ["build-project", `${directory}/main.blot`, output],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert(result.success, new TextDecoder().decode(result.stdout));
    const metrics = new TextDecoder().decode(result.stdout).trim().split("\n")
      .map((line) => JSON.parse(line)).at(-1);
    assert.equal(metrics.memory.live_bytes, 0);
    inspect(await Deno.readFile(output), false);
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
