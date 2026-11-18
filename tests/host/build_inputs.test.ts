import { strict as assert } from "node:assert";
import { createCompiler, instantiateGuest } from "../../mod.ts";

const executable = Deno.args[0] ??
  new URL("../../compiler-goose/build/blotc-goose", import.meta.url);
Deno.test("a staged asset catalog reads only the selected files and rolls back a missing input", async () => {
  const dir = await Deno.makeTempDir();
  const entry = dir + "/main.blot";
  const select = dir + "/select.blot";
  const names = ["light", "dark"];
  const compiler = await createCompiler({
    entry,
    executable,
    prelude: null,
    nativeAssets: {
      imports: names.map((name) => ({
        module: "./" + name,
        path: "./" + name + ".bin",
        kind: "input",
      })),
    },
  });
  const input = `import { file as light } from "./light"
import { file as dark } from "./dark"
import { alternate } from "./select"
import { include } from "std/build"
func catalog () => return { bytes: include (if alternate then dark else light), version: 7 }
entry func read () => return do:
  let asset = #run (catalog ())
  return asset.bytes
`;
  const selection = (other: boolean) =>
    `const alternate = ${other}
`;
  const build = (
    alternate: boolean,
    light: string | null,
    dark: string | null,
  ) =>
    compiler.build({
      sources: { [entry]: input, [select]: selection(alternate) },
      assetSources: { "./light.bin": light, "./dark.bin": dark },
    });
  async function verify(
    alternate: boolean,
    light: string | null,
    dark: string | null,
  ) {
    const r = await build(alternate, light, dark);
    if (!r.success) throw new Error(JSON.stringify(r.diagnostics));
    const name = names[Number(alternate)];
    assert.deepEqual(r.assetDependencies?.map((d) => d.path), [
      dir + "/" + name + ".bin",
    ]);
    const expected = new TextEncoder().encode((alternate ? dark : light)!);
    const guest = await instantiateGuest(r.bytes);
    try {
      assert.deepEqual(
        Array.from(guest.call("read", null) as Uint32Array),
        Array.from(expected),
      );
    } finally {
      guest.dispose();
    }
    return r;
  }
  try {
    const first = await verify(false, "a", null);
    const unrelated = await verify(false, "a", "z");
    assert.deepEqual(unrelated.bytes, first.bytes);
    assert.equal(unrelated.stats.freshModules, 0);
    assert.equal(unrelated.stats.reusedStagedWasm, true);
    assert.equal(unrelated.assetStats?.reused, 1);
    assert.equal(first.stats.reusedStagedWasm, false);
    assert.deepEqual(
      unrelated.stats.stagedDefinitions,
      first.stats.stagedDefinitions,
    );
    const files = (first.stats.stagedDefinitions as { filename: string }[]).map(
      (read) => read.filename,
    );
    assert(files.includes(select));
    assert(files.includes(dir + "/light.blot"));
    assert(!files.includes(dir + "/dark.blot"));
    const edited = await verify(false, "bb", null);
    assert.equal(edited.stats.reusedStagedWasm, false);
    assert.notDeepEqual(edited.bytes, first.bytes);
    const failed = await build(true, "bb", null);
    assert(!failed.success);
    assert.equal(failed.revision, edited.revision);
    const active = await verify(true, null, "z");
    const recovered = await verify(false, "a", null);
    assert.notDeepEqual(active.bytes, first.bytes);
    assert.deepEqual(recovered.bytes, first.bytes);
  } finally {
    await compiler.dispose();
    await Deno.remove(dir, { recursive: true });
  }
});

Deno.test("a file can choose the next input and a rejected branch preserves the last receipt", async () => {
  const dir = await Deno.makeTempDir();
  const entry = dir + "/main.blot";
  const paths = ["mode", "left", "right"];
  const c = await createCompiler({
    entry,
    executable,
    prelude: null,
    nativeAssets: {
      imports: paths.map((path) => ({
        module: "./" + path,
        path: "./" + path + ".bin",
        kind: "input",
      })),
    },
  });
  const source = `import { file as mode } from "./mode"
import { file as left } from "./left"
import { file as right } from "./right"
import { include } from "std/build"
func pick () => return if @u32.eq (@array.get (include mode) 0) 0 then left else right
entry func answer () => return #run (@array.get (include (pick ())) 0)
`;
  async function build(program = source) {
    return await c.build({ sources: { [entry]: program } });
  }
  try {
    await Deno.writeFile(dir + "/mode.bin", new Uint8Array([0]));
    await Deno.writeFile(dir + "/left.bin", new Uint8Array([255]));
    const initial = await build();
    if (!initial.success) throw Error(JSON.stringify(initial.diagnostics));
    const bad = await build(
      source.replace("include (pick ())", "include 9999"),
    );
    assert(!bad.success);
    assert.equal(bad.revision, initial.revision);
    const outside = await build(source.replace("#run ", ""));
    assert(!outside.success);
    const reused = await build();
    assert(reused.success && reused.stats.reusedStagedWasm);
    await Deno.remove(dir + "/left.bin");
    await Deno.writeFile(dir + "/mode.bin", new Uint8Array([1]));
    await Deno.writeFile(dir + "/right.bin", new Uint8Array([42]));
    const switched = await build();
    if (!switched.success) throw Error(JSON.stringify(switched.diagnostics));
    assert.deepEqual(switched.assetDependencies?.map((d) => d.path).sort(), [
      dir + "/mode.bin",
      dir + "/right.bin",
    ]);
    assert(!switched.stats.reusedStagedWasm);
    const guest = await instantiateGuest(switched.bytes);
    try {
      assert.equal(guest.call("answer", null), 42);
    } finally {
      guest.dispose();
    }
    const repeat = await build();
    assert(repeat.success && repeat.stats.reusedStagedWasm);
    assert.deepEqual(repeat.bytes, switched.bytes);
    await Deno.writeFile(dir + "/right.bin", new Uint8Array());
    const bounds = await build();
    assert(
      !bounds.success &&
        bounds.diagnostics.some((d) => d.message.includes("out of bounds")),
    );
  } finally {
    await c.dispose();
    await Deno.remove(dir, { recursive: true });
  }
});
