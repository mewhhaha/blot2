// Run from the Blot root, with the Gdev checkout next to it.
import { strict as assert } from "node:assert";
import { basename, join, resolve } from "node:path";
import { createCompiler, instantiateGuest } from "../../mod.ts";

const root = resolve("../gdev/src/assets");
const entry = join(root, "stage-catalog-probe.blot");
const names = ["catalog.json", "aim.png", "checker.png"];
const compiler = await createCompiler({
  executable: resolve(Deno.args[0] ?? "compiler-goose/build/blotc-goose"),
  entry,
  prelude: null,
  nativeAssets: {
    imports: names.map((name, i) => ({
      module: "./input" + i,
      path: "./" + name,
      kind: "input",
    })),
  },
});
const bytes = await Promise.all(
  names.map((name) => Deno.readFile(join(root, name))),
);

async function build(
  alternate: boolean,
  changed: string | null,
  expectReuse: boolean,
) {
  const selected = names[1 + Number(alternate)];
  const overlays: Record<string, Uint8Array<ArrayBuffer>> = {};
  if (changed) {
    const overlay = bytes[names.indexOf(changed)].slice();
    overlay[0] ^= 1;
    overlays["./" + changed] = overlay;
  }
  const source = `import { file as catalog } from "./input0"
import { file as aim } from "./input1"
import { file as checker } from "./input2"
import { include } from "std/build"
func catalog_entry () => return do:
  let index = include catalog
  let image = include (if ${alternate} then checker else aim)
  return { size: @array.length index, signature: @array.get image 0 }
entry func answer () => return #do:
  let row = catalog_entry ()
  break @u32.add row.signature row.size
`;
  const start = performance.now();
  const result = await compiler.build({
    sources: { [entry]: source },
    assetSources: overlays,
  });
  if (!result.success) throw Error(JSON.stringify(result.diagnostics));
  const ms = performance.now() - start;
  const guest = await instantiateGuest(result.bytes);
  try {
    const signature = bytes[names.indexOf(selected)][0] ^
      Number(changed === selected);
    assert.equal(guest.call("answer", null), bytes[0].length + signature);
  } finally {
    guest.dispose();
  }
  const read = result.assetDependencies!.map((d) => ({
    name: basename(d.path),
    sha256: d.sha256,
  }));
  assert.deepEqual(read.map((d) => d.name).sort(), [names[0], selected].sort());
  assert.equal(result.stats.reusedStagedWasm, expectReuse);
  return {
    ms,
    choice: selected,
    edit: changed,
    cached: expectReuse,
    read,
    definitions: result.stats.stagedDefinitions,
    wasm: result.bytes.length,
  };
}

try {
  console.log(JSON.stringify([
    await build(false, null, false),
    await build(false, "checker.png", true),
    await build(false, "aim.png", false),
    await build(true, null, false),
    await build(true, "aim.png", true),
    await build(false, null, false),
  ]));
} finally {
  await compiler.dispose();
}
