import { deepStrictEqual as equal, ok, rejects } from "node:assert/strict";
import { createCompiler, instantiateGuest } from "../mod.ts";
import {
  createZigProjectCompiler,
  type ZigProjectBuildResult,
} from "./zig_project_client.ts";
import type { NativeAssetOptions } from "./native_assets.ts";
import { fileURLToPath } from "node:url";

const executable = Deno.args[0] ??
  new URL("../zig-native/zig-out/bin/blotc", import.meta.url);
function success(result: ZigProjectBuildResult) {
  ok(result.success, JSON.stringify(result));
  return result;
}
async function answer(result: ZigProjectBuildResult, name = "answer") {
  const guest = await instantiateGuest(success(result).bytes);
  try {
    return guest.call(name, null);
  } finally {
    guest.dispose();
  }
}
Deno.test("native asset modules execute retained edits rejection recovery and copied overlays", async () => {
  const directory = await Deno.makeTempDir();
  const entry = directory + "/main.blot";
  const source =
    'import * as config from "./config.json"\nentry const answer = func () => return @u32.add (config.value).offset (config.value).items[1].value\n';
  const original = '{"offset":20,"items":[{"value":10},{"value":22}]}';
  const compiler = await createCompiler({
    executable,
    entry,
    prelude: null,
    cacheDirectory: false,
    nativeAssets: {
      imports: [{
        module: "./config.json",
        path: "./config.json",
        kind: "json",
      }],
    },
  });
  const options = (
    asset: string | Uint8Array<ArrayBuffer> | null = original,
  ) => ({
    sources: { [entry]: source },
    assetSources: { "./config.json": asset },
  });
  try {
    const first = success(await compiler.build(options()));
    equal(await answer(first), 42);
    equal(first.assetStats?.parsed, 1);
    equal(first.assets, []);
    const noOp = success(await compiler.build(options()));
    equal(noOp.bytes, first.bytes);
    equal(noOp.assetStats?.reused, 1);
    const bytes = new TextEncoder().encode(
      original.replace('"offset":20', '"offset":21'),
    );
    const pending = compiler.build(options(bytes));
    bytes.fill(255);
    const edited = success(await pending);
    equal(await answer(edited), 43);
    for (const invalid of ["{", null]) {
      const failure = await compiler.build(options(invalid));
      ok(!failure.success);
      equal(failure.revision, edited.revision);
      equal(failure.diagnostics[0].stage, "asset");
    }
    const recovered = success(await compiler.build(options()));
    equal(recovered.bytes, first.bytes);
    equal(await answer(recovered), 42);
    await rejects(
      Deno.stat(directory + "/config.json.blot"),
      Deno.errors.NotFound,
    );
    await compiler.close();
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
Deno.test("native references publish deterministic handles and independent binary snapshots", async () => {
  const directory = await Deno.makeTempDir();
  const entry = directory + "/main.blot";
  const source =
    'import * as a from "./a.bin"\nimport * as b from "./b.bin"\nentry const answer = func () => return do:\n  let $a.Content handle = a.content\n  break handle\n';
  const compiler = await createCompiler({
    executable,
    entry,
    prelude: null,
    cacheDirectory: false,
    nativeAssets: {
      imports: [
        {
          module: "./b.bin",
          path: "./b.bin",
          kind: "reference",
          type: "Content",
          export: "content",
        },
        {
          module: "./a.bin",
          path: "./a.bin",
          kind: "reference",
          type: "Content",
          export: "content",
        },
      ],
    },
  });
  const a = Uint8Array.of(0, 255, 1), b = Uint8Array.of(9, 8);
  const options = (value = a) => ({
    sources: { [entry]: source },
    assetSources: { "./a.bin": value, "./b.bin": b },
  });
  try {
    const first = success(await compiler.build(options()));
    equal(first.assets?.map((item) => item.id), [1, 2]);
    equal(await answer(first), 1);
    equal(first.assets?.[0].bytes, a);
    const before = first.assets![0].bytes.slice();
    const second = success(
      await compiler.build(options(Uint8Array.of(3, 4, 5))),
    );
    equal(first.assets![0].bytes, before);
    equal(second.assets![0].bytes, Uint8Array.of(3, 4, 5));
    second.assets![0].bytes.fill(17);
    const third = success(await compiler.build(options()));
    equal(third.assets![0].bytes, a);
    equal(first.assets![0].bytes, before);
    await compiler.close();
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
function quote(value: string) {
  return "'" + value.replaceAll("'", "'\\''") + "'";
}
async function peer(mode: string) {
  const directory = await Deno.makeTempDir();
  const log = directory + "/log.jsonl";
  const executable = directory + "/peer";
  const script = fileURLToPath(
    new URL("./fixtures/native_asset_peer.ts", import.meta.url),
  );
  await Deno.writeTextFile(
    executable,
    `#!/bin/sh\nexec ${quote(Deno.execPath())} run --quiet --allow-all ${
      quote(script)
    } ${quote(mode)} ${quote(log)}\n`,
  );
  await Deno.chmod(executable, 0o755);
  const options = {
    executable,
    entry: directory + "/entry.blot",
    prelude: null,
    cacheDirectory: false as const,
    nativeAssets: { imports: [] },
  };
  return {
    directory,
    log,
    options,
    async records() {
      return (await Deno.readTextFile(log)).trim().split("\n").map((line) =>
        JSON.parse(line)
      );
    },
    async cleanup() {
      await Deno.remove(directory, { recursive: true });
    },
  };
}
Deno.test("native client captures definitions and queued raw/source partitions before awaits", async () => {
  const fixture = await peer("valid");
  const module = new URL("file://" + fixture.directory + "/config.json");
  const path = new URL("file://" + fixture.directory + "/config.json");
  const definitions: NativeAssetOptions = {
    imports: [{ module, path, kind: "json" }],
  };
  const pending = createZigProjectCompiler({
    ...fixture.options,
    nativeAssets: definitions,
  });
  module.pathname = "/changed";
  path.pathname = "/changed";
  const compiler = await pending;
  try {
    const source = { [fixture.options.entry]: "hello" };
    const data = Uint8Array.of(1, 2, 3);
    const first = compiler.build({
      sources: source,
      assetSources: { "./config.json": data },
    });
    source[fixture.options.entry] = "mutated";
    data.fill(9);
    const second = compiler.build({
      assetSources: { "./empty": "", "./deleted": null },
    });
    const replies = await Promise.all([first, second]);
    ok(replies[0].success && replies[1].success);
    replies[0].assets![0].bytes.fill(8);
    equal(replies[1].assets![0].bytes, Uint8Array.of(0, 255, 42));
    await compiler.close();
    const records = await fixture.records();
    const open = records.find((item) => item.kind === "open");
    equal(
      open.nativeAssets.imports[0].module,
      fixture.directory + "/config.json.blot",
    );
    equal(
      open.nativeAssets.imports[0].path,
      fixture.directory + "/config.json",
    );
    const builds = records.filter((item) => item.kind === "build");
    equal(builds[0].sources[0].start, 0);
    equal(builds[0].assetSources[0].start, 5);
    equal(builds[0].payload, [104, 101, 108, 108, 111, 1, 2, 3]);
    equal(
      builds[1].assetSources.map((
        item: { start: number; length: number; deleted: boolean },
      ) => [item.start, item.length, item.deleted]),
      [[0, 0, false], [0, 0, true]],
    );
  } finally {
    await compiler.dispose();
    await fixture.cleanup();
  }
});
Deno.test("native assets require negotiated capability and conflict with parser assets", async () => {
  const fixture = await peer("no-capability");
  try {
    await rejects(
      createZigProjectCompiler(fixture.options),
      /does not support native assets/,
    );
    equal((await fixture.records()).length, 1);
    await rejects(
      createZigProjectCompiler({ ...fixture.options, assets: {} }),
      /cannot be used together/,
    );
  } finally {
    await fixture.cleanup();
  }
});
for (
  const mode of [
    "wasm-length",
    "gap",
    "trailing",
    "hash-format",
    "hash-data",
    "id",
    "path",
    "media",
    "dependency",
    "stats",
    "missing",
  ]
) {
  Deno.test(`native client rejects malformed ${mode} resource replies`, async () => {
    const fixture = await peer(mode);
    const compiler = await createZigProjectCompiler(fixture.options);
    try {
      await rejects(compiler.build());
      await rejects(
        compiler.build(),
        /disposed|invalid|native asset|assetStats/i,
      );
    } finally {
      await compiler.dispose();
      await fixture.cleanup();
    }
  });
}
Deno.test("native roots discover four readers and refresh membership before retained admission", async () => {
  const directory = await Deno.makeTempDir();
  const entry = directory + "/main.blot";
  await Deno.mkdir(directory + "/assets");
  await Deno.writeTextFile(
    directory + "/assets/catalog.json",
    '{"meshes":["thing.mesh.json","other.mesh.json"]}',
  );
  await Deno.writeTextFile(directory + "/text.json", '{"word":"A"}');
  await Deno.writeTextFile(
    directory + "/tunables.json",
    '{"tunables":[{"name":"camera.zoom","default":4,"min":0,"max":8}]}',
  );
  await Deno.writeTextFile(
    directory + "/assets/shader.wgsl",
    "struct Parameters { strength:f32 } const factor=2.0;",
  );
  await Deno.writeTextFile(
    entry,
    'import * as catalog from "./assets/catalog.json"\nimport * as words from "./text.json"\nimport * as tunes from "./tunables.json"\nimport * as shader from "./assets/shader.wgsl"\nentry const answer = func () => return @u32.add (catalog.meshes).other (words.text).word[0]\nentry const tune = func () => return @product.get (tunes.tunables).camera_zoom 1\nentry const factor = func () => return shader.factor\n',
  );
  const compiler = await createCompiler({
    executable,
    entry,
    cacheDirectory: false,
    nativeAssets: { roots: ["."] },
  });
  try {
    const first = success(await compiler.build());
    equal(await answer(first), 66);
    equal(await answer(first, "tune"), 4);
    equal(await answer(first, "factor"), 2);
    equal(first.assetStats?.parsed, 4);
    await Deno.writeTextFile(directory + "/text.json", '{"word":"B"}');
    const edited = success(await compiler.build());
    equal(await answer(edited), 67);
    equal(edited.assetStats?.parsed, 1);
    equal(edited.assetStats?.reused, 3);
    const bad = directory + "/assets/new.wgsl";
    await Deno.writeTextFile(bad, "func broken {");
    const failed = await compiler.build();
    ok(!failed.success);
    equal(failed.revision, edited.revision);
    equal(failed.diagnostics[0].stage, "asset");
    await Deno.remove(bad);
    const recovered = success(await compiler.build());
    equal(recovered.bytes, edited.bytes);
    equal(recovered.assetStats?.reused, 4);
    await compiler.close();
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
