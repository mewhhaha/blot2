import { deepStrictEqual as equal, ok, rejects } from "node:assert/strict";
import { createCompiler, instantiateGuest, jsonAssetParser } from "../mod.ts";
import type {
  AssetModule,
  AssetParser,
  ZigProjectBuildResult,
} from "../mod.ts";

const executable = Deno.args[0] ??
  new URL("../zig-native/zig-out/bin/blotc", import.meta.url);
const encoder = new TextEncoder();
function success(result: ZigProjectBuildResult) {
  ok(result.success, JSON.stringify(result));
  return result;
}
async function call(
  result: ZigProjectBuildResult,
  name = "answer",
  value: unknown = null,
) {
  const guest = await instantiateGuest(success(result).bytes);
  try {
    return guest.call(
      name,
      (typeof value === "function"
        ? guest.capability({
          parameter: "U32",
          result: "U32",
          call: value as (input: number) => number,
        })
        : value) as never,
    );
  } finally {
    guest.dispose();
  }
}

Deno.test("typed JSON modules execute, reuse, edit, reject, and recover without disk output", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  let calls = 0;
  const compiler = await createCompiler({
    executable,
    entry,
    prelude: null,
    assets: {
      "./config.json": {
        path: "./config.json",
        parser: (context) => {
          calls++;
          return jsonAssetParser(context);
        },
      },
    },
  });
  const source = `import * as config from "./config.json"
const read = fn (config_value: config.Data) => @u32.add config_value.offset config_value.items[1].value
entry const answer = fn () => read config.value
entry const text = fn () => (config.value).title.bytes[0]
entry const fraction = fn () => (config.value).scale
`;
  const original =
    '{"offset":20,"items":[{"value":10},{"value":22}],"title":"雪","scale":-1.5}';
  const options = (text = original) => ({
    sources: { [entry]: source },
    assetSources: { "./config.json": text },
  });
  try {
    const first = success(await compiler.build(options()));
    equal(await call(first), 42);
    equal(await call(first, "text"), 233);
    equal(await call(first, "fraction"), -1.5);
    equal(first.assetStats?.parsed, 1);
    const noop = success(await compiler.build(options()));
    equal(noop.bytes, first.bytes);
    equal(noop.assetStats?.reused, 1);
    equal(calls, 1);
    const edited = success(
      await compiler.build(
        options(original.replace('"offset":20', '"offset":21')),
      ),
    );
    equal(await call(edited), 43);
    const failed = await compiler.build(options("{"));
    ok(!failed.success);
    equal(failed.revision, edited.revision);
    equal(failed.diagnostics[0].stage, "asset");
    const recovered = success(await compiler.build(options()));
    equal(recovered.bytes, first.bytes);
    const fresh = await createCompiler({
      executable,
      entry,
      prelude: null,
      assets: {
        "./config.json": { path: "./config.json", parser: jsonAssetParser },
      },
    });
    try {
      equal(success(await fresh.build(options())).bytes, recovered.bytes);
    } finally {
      await fresh.dispose();
    }
    await rejects(
      Deno.stat(`${directory}/config.json.blot`),
      Deno.errors.NotFound,
    );
    await rejects(Deno.stat(`${directory}/config.json`), Deno.errors.NotFound);
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("shader parser exports input types and content handles with tracked includes", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  let calls = 0;
  // Explicit metadata stands in for a real shader parser. No regex reflection.
  const parser: AssetParser = async (context) => {
    calls++;
    const value = Number(
      new TextDecoder().decode(await context.read("./scale.txt")),
    );
    return {
      types: [{ name: "Inputs", fields: { scale: "U32" } }],
      values: {
        shader: {
          type: { reference: "Shader" },
          value: await context.reference(undefined, "text/wgsl"),
        },
        scale: { type: "U32", value },
      },
    };
  };
  const compiler = await createCompiler({
    executable,
    entry,
    prelude: null,
    assets: { "./shader.wgsl": { path: "./shader.wgsl", parser } },
  });
  const source = `import * as shader from "./shader.wgsl"
const read = fn (value: shader.Inputs) => value.scale
entry const answer = fn () => read (#shader.Inputs { scale: shader.scale })
entry const handle = fn () => case shader.shader of
  #shader.Shader id => id
entry const upload = fn (send: U32 -> U32 ! {Foreign}) => case shader.shader of
  #shader.Shader id => send id
`;
  const shader =
    "@vertex fn main() -> @builtin(position) vec4f { return vec4f(0); }";
  const options = (scale: string | null = "42") => ({
    sources: { [entry]: source },
    assetSources: { "./shader.wgsl": shader, "./scale.txt": scale },
  });
  try {
    const first = success(await compiler.build(options()));
    equal(await call(first), 42);
    const id = await call(first, "handle");
    const resource = first.assets?.find((asset) => asset.id === id);
    ok(resource);
    equal(new TextDecoder().decode(resource.bytes), shader);
    equal(resource.mediaType, "text/wgsl");
    equal(resource.sha256.length, 64);
    equal(
      await call(
        first,
        "upload",
        (received: number) => received === id ? 42 : 0,
      ),
      42,
    );
    // Caller mutation cannot alter cached resource bytes.
    resource.bytes.fill(0);
    const noop = success(await compiler.build(options()));
    equal(calls, 1);
    equal(new TextDecoder().decode(noop.assets![0].bytes), shader);
    const edited = success(await compiler.build(options("43")));
    equal(calls, 2);
    equal(await call(edited), 43);
    const missing = await compiler.build(options(null));
    ok(!missing.success);
    equal(missing.revision, edited.revision);
    equal(await call(await compiler.build(options())), 42);
    const rejected = await compiler.build({
      ...options(),
      sources: {
        [entry]: source.replace("scale: shader.scale", "scale: #True"),
      },
    });
    ok(!rejected.success);
    equal(rejected.diagnostics[0].code, "type_mismatch");
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("asset templates own parser results and queued byte overlays", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  let result: AssetModule | undefined;
  const compiler = await createCompiler({
    executable,
    entry,
    prelude: null,
    assets: {
      "./value": {
        path: "./value.bin",
        parser: (context) =>
          result = {
            values: {
              value: {
                type: { name: "Data", fields: { value: "U32" } },
                value: { value: context.bytes[0] },
              },
            },
          },
      },
    },
  });
  const sources = {
    [entry]:
      'import { value } from "./value"\nentry const answer = fn () => value.value\n',
  };
  try {
    const bytes = new Uint8Array([42]);
    const queued = compiler.build({
      sources,
      assetSources: { "./value.bin": bytes },
    });
    bytes[0] = 99;
    equal(await call(await queued), 42);
    (result!.values!.value.type as { name: string }).name = "Injected";
    (result!.values!.value.value as { value: number }).value = 99;
    equal(
      await call(
        await compiler.build({
          sources,
          assetSources: { "./value.bin": new Uint8Array([42]) },
        }),
      ),
      42,
    );
    const aborted = new AbortController();
    aborted.abort();
    await rejects(compiler.build({ signal: aborted.signal, sources }));
    equal(
      await call(
        await compiler.build({
          sources,
          assetSources: { "./value.bin": new Uint8Array([43]) },
        }),
      ),
      43,
    );
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("asset disposal rejects active and queued builds even when a parser ignores cancellation", async () => {
  const directory = await Deno.makeTempDir();
  const started = Promise.withResolvers<void>();
  const paused = Promise.withResolvers<AssetModule>();
  let parserSignal: AbortSignal | undefined;
  const entry = `${directory}/main.blot`;
  const compiler = await createCompiler({
    executable,
    entry,
    prelude: null,
    assets: {
      "./value": {
        path: "./value.bin",
        parser: (context) => {
          parserSignal = context.signal;
          started.resolve();
          return paused.promise;
        },
      },
    },
  });
  let timeout: ReturnType<typeof setTimeout> | undefined;
  try {
    const options = {
      sources: { [entry]: "entry const answer = 42\n" },
      assetSources: { "./value.bin": "value" },
    };
    const active = compiler.build(options);
    await started.promise;
    const queued = compiler.build(options);
    const rejected = Promise.all([
      rejects(active, /closed/),
      rejects(queued, /closed/),
    ]);
    await compiler.dispose();
    equal(parserSignal?.aborted, true);
    await Promise.race([
      rejected,
      new Promise((_, reject) => {
        timeout = setTimeout(
          () => reject(new Error("Asset disposal left waiting builds pending")),
          3000,
        );
      }),
    ]);
    await compiler.close();
    await rejects(compiler.build(options), /closed/);
  } finally {
    clearTimeout(timeout);
    paused.resolve({ values: { value: { type: "U32", value: 42 } } });
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("asset parser rejects invalid fields, forged references and unrepresentable values", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const cases: AssetParser[] = [
    () => ({ values: { value: { type: "U32", value: -1 } } }),
    () => ({ values: { value: { type: "F32", value: Infinity } } }),
    () => ({ values: { value: { type: { reference: "Shader" }, value: {} } } }),
    () => ({ types: [{ name: "Bad", fields: { "x; injected": "U32" } }] }),
    () => ({
      types: [{ name: "Bad", fields: { value: "U32" } }, {
        name: "Bad",
        fields: { value: "Bool" },
      }],
    }),
    jsonAssetParser,
  ];
  try {
    for (const parser of cases) {
      const compiler = await createCompiler({
        executable,
        entry,
        prelude: null,
        assets: { "./asset": { path: "./asset.json", parser } },
      });
      try {
        const built = await compiler.build({
          sources: {
            [entry]:
              'import * as asset from "./asset"\nentry const answer = 42\n',
          },
          assetSources: {
            "./asset.json": encoder.encode('{"invalid-field":42}'),
          },
        });
        ok(!built.success);
        equal(built.diagnostics[0].stage, "asset");
        equal(built.revision, 0);
      } finally {
        await compiler.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("optional includes track absence, addition, removal and obsolete dependencies", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  let calls = 0;
  const parser: AssetParser = async (context) => {
    calls++;
    let value = 42;
    if (context.bytes[0] !== 0) {
      try {
        value = Number(
          new TextDecoder().decode(await context.read("./optional.txt")),
        );
      } catch (error) {
        if (!(error instanceof Deno.errors.NotFound)) throw error;
      }
    }
    return { values: { value: { type: "U32", value } } };
  };
  const compiler = await createCompiler({
    executable,
    entry,
    prelude: null,
    assets: { "./config": { path: "./root.bin", parser } },
  });
  const sources = {
    [entry]:
      'import { value } from "./config"\nentry const answer = fn () => value\n',
  };
  const options = (optional: string | null, root = 1) => ({
    sources,
    assetSources: {
      "./root.bin": new Uint8Array([root]),
      "./optional.txt": optional,
    },
  });
  try {
    const first = success(await compiler.build(options(null)));
    equal(
      first.assetDependencies?.find((input) =>
        input.path.endsWith("optional.txt")
      )?.sha256,
      null,
    );
    equal(await call(await compiler.build(options(null))), 42);
    equal(calls, 1);
    equal(await call(await compiler.build(options("43"))), 43);
    equal(calls, 2);
    equal(await call(await compiler.build(options(null))), 42);
    equal(calls, 3);
    // A changed parser branch drops its previous include dependency.
    const dropped = success(await compiler.build(options(null, 0)));
    equal(dropped.assetDependencies?.length, 1);
    equal(await call(await compiler.build(options("99", 0))), 42);
    equal(calls, 4);
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("asset IDs and snapshots are deterministic across parser order and shader-only edits", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const parser: AssetParser = async (context) => ({
    values: {
      shader: {
        type: { reference: "Shader" },
        value: await context.reference(),
      },
    },
  });
  const imports = {
    "./a": { path: "./a.wgsl", parser },
    "./b": { path: "./b.wgsl", parser },
  };
  const first = await createCompiler({
    executable,
    entry,
    prelude: null,
    assets: imports,
  });
  const second = await createCompiler({
    executable,
    entry,
    prelude: null,
    assets: Object.fromEntries(Object.entries(imports).reverse()),
  });
  const sources = {
    [entry]:
      'import * as a from "./a"\nimport * as b from "./b"\nentry const answer = fn () => case a.shader of\n  #a.Shader id => id\n',
  };
  const options = (shader = "first") => ({
    sources,
    assetSources: { "./a.wgsl": shader, "./b.wgsl": "second" },
  });
  try {
    const a = success(await first.build(options()));
    const b = success(await second.build(options()));
    equal(a.bytes, b.bytes);
    equal(a.assets, b.assets);
    const changed = success(await first.build(options("changed")));
    equal(changed.bytes, a.bytes);
    equal(new TextDecoder().decode(changed.assets![0].bytes), "changed");
    ok(changed.assets![0].sha256 !== a.assets![0].sha256);
    equal(new TextDecoder().decode(a.assets![0].bytes), "first");
    equal(success(await second.build(options("changed"))).bytes, changed.bytes);
  } finally {
    await first.dispose();
    await second.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("retargeting an asset symlink with identical bytes invalidates relative includes", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  for (const [name, value] of [["one", "42"], ["two", "43"]]) {
    await Deno.mkdir(`${directory}/${name}`);
    await Deno.writeTextFile(`${directory}/${name}/root.txt`, "identical");
    await Deno.writeTextFile(`${directory}/${name}/include.txt`, value);
  }
  await Deno.symlink(`${directory}/one/root.txt`, `${directory}/current.txt`);
  let calls = 0;
  const parser: AssetParser = async (context) => {
    calls++;
    return {
      values: {
        value: {
          type: "U32",
          value: Number(
            new TextDecoder().decode(await context.read("./include.txt")),
          ),
        },
      },
    };
  };
  const compiler = await createCompiler({
    executable,
    entry,
    prelude: null,
    assets: { "./asset": { path: "./current.txt", parser } },
  });
  const options = {
    sources: {
      [entry]:
        'import { value } from "./asset"\nentry const answer = fn () => value\n',
    },
  };
  try {
    equal(await call(await compiler.build(options)), 42);
    await Deno.remove(`${directory}/current.txt`);
    await Deno.symlink(`${directory}/two/root.txt`, `${directory}/current.txt`);
    equal(await call(await compiler.build(options)), 43);
    equal(calls, 2);
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("JSON root values always export their exact Data type, including empty shapes", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const cases = [
    ["42", "value", 42],
    ["1.5", "@f32.to_u32 value", 1],
    ["true", "if value then 42 else 0", 42],
    ["null", "(fn (_: Data) => 42) value", 42],
    ["[]", "(fn (_: Data) => 42) value", 42],
    ["{}", "(fn (_: Data) => 42) value", 42],
    ["[40,2]", "@u32.add value[0] value[1]", 42],
    ["[40,true]", "@product.get value 0", 40],
  ] as const;
  try {
    const compiler = await createCompiler({
      executable,
      entry,
      prelude: null,
      assets: {
        "./config": { path: "./config.json", parser: jsonAssetParser },
      },
    });
    try {
      for (const [json, expression, expected] of cases) {
        const source =
          `import { value, Data } from "./config"\nconst identity = fn (input: Data) -> Data => input\nentry const answer = fn () => ${expression}\n`;
        equal(
          await call(
            await compiler.build({
              sources: { [entry]: source },
              assetSources: { "./config.json": json },
            }),
          ),
          expected,
        );
      }
    } finally {
      await compiler.dispose();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
