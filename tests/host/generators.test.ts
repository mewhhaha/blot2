import {
  deepStrictEqual as equal,
  match,
  ok,
  rejects,
} from "node:assert/strict";
import { fileURLToPath } from "node:url";
import {
  type AssetDiagnostic,
  blotStdRoot,
  createBlotGenerator,
  createCompiler,
  expandGeneratorRules,
  instantiateGuest,
  resolveProject,
  runBlotTests,
  type ZigProjectBuildResult,
} from "../../mod.ts";
import { runCli } from "../../host/cli.ts";

const executable = Deno.args.at(0) ??
  new URL("../../compiler-goose/build/blotc-goose", import.meta.url);
const examples = new URL("../../examples/generators/", import.meta.url);
const wgsl = `// Reflected declarations and a real compute entry
struct Parameters { clear: f32, dither: f32, active: bool };
struct VecInfo { pos: vec3f };
const stage_light_slot = 16u;
const building_marker = -1.0;
@compute @workgroup_size(1)
fn main() {
  let slot = stage_light_slot;
}
`;

function success(result: ZigProjectBuildResult) {
  ok(result.success, JSON.stringify(result));
  return result;
}

async function workspace(run: (root: string) => Promise<void>) {
  const root = await Deno.realPath(
    await Deno.makeTempDir({ prefix: "blot-generators-" }),
  );
  try {
    await run(root);
  } finally {
    await Deno.remove(root, { recursive: true });
  }
}

async function calls(result: ZigProjectBuildResult, ...names: string[]) {
  const guest = await instantiateGuest(success(result).bytes);
  try {
    return names.map((name) => guest.call(name, null));
  } finally {
    guest.dispose();
  }
}

Deno.test("WGSL generators emit native types and tracked shader references, cache Wasm, and complete edited fields", () =>
  workspace(async (root) => {
    const generator = root + "/wgsl_gen.blot";
    const dependency = root + "/literals.blot";
    const entry = root + "/main.blot";
    const input = root + "/salt.wgsl";
    const log = root + "/compiles";
    const observedCompiler = root + "/compiler";
    const compilerPath = executable instanceof URL
      ? fileURLToPath(executable)
      : await Deno.realPath(executable);
    const shellQuote = (value: string) =>
      "'" + value.replaceAll("'", "'\\''") + "'";
    await Deno.writeTextFile(
      observedCompiler,
      `#!/bin/sh\nprintf 'compiler\\n' >> ${shellQuote(log)}\nexec ${
        shellQuote(compilerPath)
      } "$@"\n`,
      { mode: 0o700 },
    );
    const count = async () =>
      (await Deno.readTextFile(log)).trimEnd().split("\n").length;
    await Promise.all([
      Deno.copyFile(new URL("wgsl_gen.blot", examples), generator),
      Deno.copyFile(new URL("literals.blot", examples), dependency),
      Deno.writeTextFile(input, wgsl),
      Deno.writeTextFile(
        entry,
        `import { Parameters, VecInfo, Shader, shader, stage_light_slot, building_marker } from "./salt.wgsl"
func selected (params: Parameters): Bool => return params.active
func vec_value (info: VecInfo): F32 => return info.pos[1]
io enabled () => return selected ($Parameters { clear: 1.0, dither: 0.5, active: true })
io middle () =>
  let pos: #[3; F32] = #[1.0, 2.0, 3.0]
  return vec_value ($VecInfo { pos })
io slot () => return stage_light_slot
io marker () => return building_marker
io shader_id () => return case shader of
  $Shader id => id
`,
      ),
    ]);
    const compiler = await createCompiler({
      executable,
      entry,
      assets: {
        "./salt.wgsl": {
          path: input,
          parser: createBlotGenerator({
            generator,
            executable: observedCompiler,
            inputMode: "text",
            reference: {
              type: "Shader",
              export: "shader",
              mediaType: "text/wgsl",
            },
          }),
        },
      },
    });
    try {
      const original = success(await compiler.build());
      equal(
        await calls(
          original,
          "enabled",
          "middle",
          "slot",
          "marker",
          "shader_id",
        ),
        [true, 2, 16, -1, 1],
      );
      equal(
        original.assets?.map((
          { id, path, mediaType, bytes },
        ) => [id, path, mediaType, new TextDecoder().decode(bytes)]),
        [[1, input, "text/wgsl", wgsl]],
      );
      ok(original.assetDependencies?.some(({ path }) => path === dependency));
      equal(original.assetStats?.parsed, 1);
      equal(await count(), 1);

      const unchanged = success(await compiler.build());
      equal(unchanged.assetStats?.reused, 1);
      equal(unchanged.assetStats?.parsed, 0);
      equal(unchanged.stats.freshModules, 0);
      equal(unchanged.bytes, original.bytes);
      equal(await count(), 1);

      await Deno.writeTextFile(input, wgsl.replace("16u", "24u"));
      const edited = success(await compiler.build());
      equal(edited.assetStats?.parsed, 1);
      equal(await calls(edited, "slot"), [24]);
      equal(await count(), 1);

      await Deno.writeTextFile(
        generator,
        (await Deno.readTextFile(generator))
          .replace("text.from_u32 value", "text.from_u32 (value + 1)"),
      );
      const rewritten = success(await compiler.build());
      equal(rewritten.assetStats?.parsed, 1);
      equal(await calls(rewritten, "slot"), [25]);
      equal(await count(), 2);

      await Deno.writeTextFile(
        dependency,
        (await Deno.readTextFile(dependency))
          .replace("if start == 1:", "if false:"),
      );
      const dependencyEdit = success(await compiler.build());
      equal(dependencyEdit.assetStats?.parsed, 1);
      equal(await calls(dependencyEdit, "slot", "marker"), [25, 1]);
      equal(await count(), 3);

      const overlay = success(
        await compiler.build({
          assetSources: { "./salt.wgsl": wgsl.replace("16u", "30u") },
        }),
      );
      equal(await calls(overlay, "slot"), [31]);
      equal(overlay.assetStats?.parsed, 1);
      equal(await calls(await compiler.build(), "slot"), [25]);
      equal(await count(), 3);

      const query =
        'import { Parameters } from "./salt.wgsl"\nfunc preview (params: Parameters) => return params.';
      const completion = await compiler.complete({
        filename: entry,
        position: new TextEncoder().encode(query).length,
        snapshot: 1,
        sources: { [entry]: query },
        assetSources: {
          "./salt.wgsl": wgsl.replace("dither: f32", "glow: f32"),
        },
      });
      ok(completion.success, JSON.stringify(completion));
      equal(
        completion.items.filter((item) => item.kind === "field").map((item) =>
          item.label
        ).sort(),
        ["active", "clear", "glow"],
      );
      equal(success(await compiler.build()).assetStats?.reused, 1);
      equal(await count(), 3);

      const malformed = await compiler.build({
        assetSources: {
          "./salt.wgsl": "struct Parameters { clear: texture_2d }",
        },
      });
      checkAssetError(
        malformed,
        input,
        /Unsupported WGSL field type in Parameters/,
      );
    } finally {
      await compiler.dispose();
    }
  }));

Deno.test("WGSL generator preserves exact unsuffixed U32 constants, scientific floats, and rejects reserved Blot keywords", () =>
  workspace(async (root) => {
    const entry = root + "/main.blot";
    const input = root + "/shader.wgsl";
    const compiler = await createCompiler({
      executable,
      entry,
      assets: {
        "./shader.wgsl": {
          path: input,
          parser: createBlotGenerator({
            executable,
            generator: new URL("wgsl_gen.blot", examples),
            inputMode: "text",
          }),
        },
      },
    });
    try {
      const built = await compiler.build({
        sources: {
          [entry]:
            `import { exactly, eps, scale, half, whole_f } from "./shader.wgsl"
io exact_u32 (): U32 => return exactly
io sci_small (): F32 => return eps
io sci_neg (): F32 => return scale
io suffix_f (): F32 => return half + whole_f
`,
        },
        assetSources: {
          "./shader.wgsl": `const exactly = 16777217;
const eps = 1e-6;
const scale = -2.5E+2;
const half = 0.5f;
const whole_f = 2f;
`,
        },
      });
      equal(
        await calls(built, "exact_u32", "sci_small", "sci_neg", "suffix_f"),
        [16777217, Math.fround(1e-6), -250, 2.5],
      );
      checkAssetError(
        await compiler.build({
          sources: {
            [entry]:
              'import { bad } from "./shader.wgsl"\nio run () => return bad\n',
          },
          assetSources: { "./shader.wgsl": "const bad = 4294967296;\n" },
        }),
        input,
        /Unsupported WGSL constant value for bad/,
      );
      checkAssetError(
        await compiler.build({
          sources: {
            [entry]:
              'import { bad } from "./shader.wgsl"\nio run () => return bad\n',
          },
          assetSources: { "./shader.wgsl": "const bad = -5;\n" },
        }),
        input,
        /Unsupported WGSL constant value for bad/,
      );
      checkAssetError(
        await compiler.build({
          sources: {
            [entry]:
              'import { Bad } from "./shader.wgsl"\nio run (): U32 => return 0\n',
          },
          assetSources: { "./shader.wgsl": "struct Bad { spark: f32 };\n" },
        }),
        input,
        /WGSL field 'spark' in Bad collides with a reserved Blot keyword/,
      );
      checkAssetError(
        await compiler.build({
          sources: {
            [entry]:
              'import { fork } from "./shader.wgsl"\nio run (): U32 => return 0\n',
          },
          assetSources: { "./shader.wgsl": "const fork = 1u;\n" },
        }),
        input,
        /WGSL constant 'fork' collides with a reserved Blot keyword/,
      );
    } finally {
      await compiler.dispose();
    }
  }));

Deno.test("CSV generator embeds typed rows, decimal speed and quoted Unicode names in Wasm", () =>
  workspace(async (root) => {
    const entry = root + "/main.blot";
    const compiler = await createCompiler({
      executable,
      entry,
      assets: {
        "./units.csv": {
          path: "./units.csv",
          parser: createBlotGenerator({
            executable,
            generator: new URL("csv_gen.blot", examples),
            inputMode: "text",
          }),
        },
      },
    });
    try {
      const built = await compiler.build({
        sources: {
          [entry]: `import { UnitSpec, specs } from "./units.csv"
func hit_points (spec: UnitSpec): U32 => return spec.hp
io hp () => return hit_points specs[1]
io speed () => return specs[0].speed
io name_char () => return specs[0].name[0]
io rows () => return specs.length
`,
        },
        assetSources: {
          "./units.csv":
            'name,hp,speed\r\n"雪, ""scout""",25,1.25\r\nTank,120,02\r\n',
        },
      });
      equal(await calls(built, "hp", "speed", "name_char", "rows"), [
        120,
        1.25,
        38634,
        2,
      ]);
    } finally {
      await compiler.dispose();
    }
  }));

function checkAssetError(
  result: ZigProjectBuildResult,
  input: string,
  message: RegExp,
) {
  ok(!result.success, "Expected an asset diagnostic");
  const [error] = result.diagnostics;
  equal([error.stage, error.code, error.filename], [
    "asset",
    "asset_import",
    input,
  ]);
  match(error.message, message);
}

Deno.test("Stage 0 supports structural record inputs, alternate names, and the lossless bytes mode", () =>
  workspace(async (root) => {
    const entry = root + "/main.blot";
    const generator = root + "/gen.blot";
    const input = root + "/雪.asset";
    const options = {
      sources: {
        [entry]:
          'import { answer } from "./generated"\nio run () => return answer\n',
      },
      assetSources: { [input]: "🙂" },
    };
    await Deno.writeTextFile(
      generator,
      `// 雪🙂
import * as text from "std/text"
io reflect (input: { path: Text, text: Text }): Result [Text, Text] =>
  if text.equal input.path ${JSON.stringify(input)} and input.text[0] == 128578:
    return $Ok "const answer: U32 = 42"
  return $Err "Unexpected path or Unicode scalar"
`,
    );
    const compiler = await createCompiler({
      executable,
      entry,
      assets: {
        "./generated": {
          path: input,
          parser: createBlotGenerator({
            executable,
            generator,
            exportName: "reflect",
            inputMode: "text",
          }),
        },
      },
    });
    try {
      equal(await calls(await compiler.build(options), "run"), [42]);
      checkAssetError(
        await compiler.build({
          ...options,
          assetSources: { [input]: new Uint8Array([255]) },
        }),
        input,
        /Expected UTF-8/,
      );
    } finally {
      await compiler.dispose();
    }

    await Deno.writeTextFile(
      generator,
      `io generate (input: { path: #[U32], bytes: #[U32] }): #[U32] =>
  if input.path.length > 0 and input.bytes[0] == 255 and input.bytes[1] == 0:
    return "const answer: U32 = 90"
  return "const answer: U32 = 0"
`,
    );
    const binary = await createCompiler({
      executable,
      entry,
      assets: {
        "./generated": {
          path: input,
          parser: createBlotGenerator({ executable, generator }),
        },
      },
    });
    try {
      equal(
        await calls(
          await binary.build({
            ...options,
            assetSources: { [input]: new Uint8Array([255, 0]) },
          }),
          "run",
        ),
        [90],
      );
    } finally {
      await binary.dispose();
    }
  }));

Deno.test("generator Err, trap, compile failure, missing export and unsupported ABI use asset diagnostics", () =>
  workspace(async (root) => {
    const entry = root + "/main.blot";
    const generator = root + "/gen.blot";
    const input = root + "/input.txt";
    const compiler = await createCompiler({
      executable,
      entry,
      assets: {
        "./input.txt": {
          path: input,
          parser: createBlotGenerator({ executable, generator }),
        },
      },
    });
    try {
      const build = () =>
        compiler.build({
          sources: {
            [entry]:
              'import { answer } from "./input.txt"\nio run () => return answer\n',
          },
          assetSources: { [input]: "contents" },
        });
      for (
        const [source, message] of [
          [
            'io generate (x: Text): Result [Text, Text] => return $Err "bad schema"',
            /bad schema/,
          ],
          [
            'io generate (x: Text): Text => return @panic "oh no"',
            /generator generate trapped.*panic: "oh no"/,
          ],
          [
            "io generate (x: Text): Text => return nonexistent",
            /Could not compile generator.*\n.*unknown value: nonexistent/,
          ],
          [
            "io other (x: Text): Text => return x",
            /Missing io entry function generate/,
          ],
          [
            "io generate (x: U32): U32 => return x",
            /Unsupported signature for generator generate/,
          ],
          [
            "io generate (x: Text): Text => return #[0xD800]",
            /Invalid Unicode scalar/,
          ],
          [
            `io generate (x: Text): Text => return x
io requires_io (send: U32 -> U32 ! {Foreign}) => return send 1`,
            /Stage 0 grants no capabilities/,
          ],
        ] as const
      ) {
        await Deno.writeTextFile(generator, source + "\n");
        checkAssetError(await build(), input, message);
      }
      await Deno.writeTextFile(
        generator,
        'io generate (x: Text): Text => return "const answer = 90"\n',
      );
      equal(await calls(await build(), "run"), [90]);
    } finally {
      await compiler.dispose();
    }
  }));

Deno.test("blot.json generator rules drive blot check, build, and test from a nested entry", () =>
  workspace(async (root) => {
    await Deno.mkdir(root + "/assets");
    await Deno.mkdir(root + "/src");
    const entry = root + "/src/main.blot";
    const output = root + "/main.wasm";
    const rules = [
      { module: "aliased", input: "input.txt", generator: "gen.blot" },
      {
        match: "assets/*.wgsl",
        generator: "./wgsl_gen.blot",
        inputMode: "text" as const,
      },
    ];
    await Promise.all([
      Deno.writeTextFile(
        root + "/blot.json",
        JSON.stringify({
          generators: rules,
          dependencies: {
            std: { path: fileURLToPath(new URL("../../", import.meta.url)) },
          },
          prelude: "std",
          tests: { files: ["src/main.blot"] },
        }),
      ),
      Deno.writeTextFile(
        root + "/gen.blot",
        "io generate (input: #[U32]): #[U32] => return input\n",
      ),
      Deno.writeTextFile(root + "/input.txt", "const value: U32 = 20\n"),
      Deno.copyFile(
        new URL("wgsl_gen.blot", examples),
        root + "/wgsl_gen.blot",
      ),
      Deno.copyFile(
        new URL("literals.blot", examples),
        root + "/literals.blot",
      ),
      Deno.writeTextFile(root + "/assets/z.wgsl", "const value = 2u;\n"),
      Deno.writeTextFile(root + "/assets/a.wgsl", "const value = 20u;\n"),
      Deno.writeTextFile(
        entry,
        `import { value as left } from "../aliased"
import { value as right } from "../assets/z.wgsl"
import { value as middle } from "../assets/a.wgsl"
io test_generated () => return @u32.eq (@u32.add left (@u32.add middle right)) 42
`,
      ),
    ]);
    const expanded = await expandGeneratorRules(root, rules, { executable });
    equal(Object.keys(expanded), [
      root + "/aliased.blot",
      root + "/assets/a.wgsl.blot",
      root + "/assets/z.wgsl.blot",
    ]);
    equal(
      expanded[root + "/assets/a.wgsl.blot"].parser,
      expanded[root + "/assets/z.wgsl.blot"].parser,
    );
    equal(await runCli(executable, ["check", entry]), 0);
    equal(await runCli(executable, ["build", entry, output]), 0);
    const guest = await instantiateGuest(await Deno.readFile(output));
    try {
      equal(guest.call("test_generated", null), true);
    } finally {
      guest.dispose();
    }
    const cli = root + "/cli.ts";
    await Deno.writeTextFile(
      cli,
      `import { runCli } from ${
        JSON.stringify(new URL("../../host/cli.ts", import.meta.url).href)
      };
const [compiler, entry] = Deno.args;
Deno.exitCode = await runCli(compiler, ["check", entry, "--json"]);`,
    );
    const compilerPath = executable instanceof URL
      ? fileURLToPath(executable)
      : await Deno.realPath(executable);
    const runJsonCheck = () =>
      new Deno.Command(Deno.execPath(), {
        cwd: root,
        args: ["run", "--allow-read", "--allow-run", cli, compilerPath, entry],
      }).output();
    const checked = await runJsonCheck();
    const records = (output: Uint8Array) =>
      new TextDecoder().decode(output).trimEnd().split("\n").map((line) =>
        JSON.parse(line)
      );
    equal(checked.code, 0, new TextDecoder().decode(checked.stderr));
    const [compilation] = records(checked.stdout);
    equal([compilation.kind, compilation.stage, compilation.success], [
      "compilation",
      "check-project",
      true,
    ]);
    const report = await runBlotTests({ executable, root, jobs: 1 });
    ok(report.success, JSON.stringify(report));
    equal(report.testsPassed, 1);
    await Deno.writeTextFile(root + "/assets/z.wgsl", "const value = nope;");
    const failed = await runJsonCheck();
    equal(failed.code, 1);
    const [diagnostic, summary] = records(failed.stdout);
    equal([diagnostic.kind, diagnostic.stage, diagnostic.code], [
      "diagnostic",
      "asset",
      "asset_import",
    ]);
    match(diagnostic.message, /Unsupported WGSL constant value/);
    equal(summary.success, false);
  }));

Deno.test("manifest generator rules reject unknown fields, malformed patterns, and escaping paths", () =>
  workspace(async (root) => {
    const entry = root + "/main.blot";
    const base = {
      generator: "gen.blot",
      module: "./virtual",
      input: "./input",
    };
    for (
      const rule of [
        { ...base, module: "../outside" },
        { ...base, input: "/outside" },
        { ...base, generator: "other\0.blot" },
        { ...base, unknown: true },
        { ...base, match: "assets/*.wgsl" },
        { generator: "gen.blot", match: "assets/**/shader.wgsl" },
        {
          ...base,
          reference: { type: "Shader", export: "shader", extra: true },
        },
      ]
    ) {
      await Deno.writeTextFile(
        root + "/blot.json",
        JSON.stringify({ generators: [rule] }),
      );
      await rejects(resolveProject(entry), /generators\[0\]/);
    }
    await Deno.symlink(fileURLToPath(blotStdRoot), root + "/outside");
    await rejects(
      expandGeneratorRules(root, [{ ...base, generator: "outside/text.blot" }]),
      /escapes the project/,
    );
    await rejects(
      expandGeneratorRules(root, [{ ...base, module: "outside/virtual" }]),
      /escapes the project/,
    );
    await rejects(
      expandGeneratorRules(root, [{
        generator: "gen.blot",
        match: "outside/*.blot",
      }]),
      /escapes the project/,
    );
  }));

Deno.test("raw asset source validates Unicode, NUL and the combined structured size budget", () =>
  workspace(async (root) => {
    const entry = root + "/main.blot";
    const input = root + "/input";
    const compiler = await createCompiler({
      executable,
      entry,
      assets: {
        "./input": {
          path: input,
          parser(context) {
            const source = [
              "const raw: U32 = 41",
              "const raw: U32 = 41\0",
              "\uD800",
              "//" + " ".repeat(16 * 1024 * 1024 - 3),
            ][context.bytes[0]];
            return {
              source,
              values: { structured: { type: "U32", value: 1 } },
            };
          },
        },
      },
    });
    const build = (mode: number) =>
      compiler.build({
        sources: {
          [entry]:
            'import { raw, structured } from "./input"\nio run () => return raw + structured\n',
        },
        assetSources: { [input]: Uint8Array.of(mode) },
      });
    try {
      equal(await calls(await build(0), "run"), [42]);
      checkAssetError(
        await build(1),
        input,
        /well-formed Blot text without NUL/,
      );
      checkAssetError(
        await build(2),
        input,
        /well-formed Blot text without NUL/,
      );
      checkAssetError(await build(3), input, /exceeds 16 MiB/);
    } finally {
      await compiler.dispose();
    }
  }));

Deno.test("Stage 0 attaches provenance for execute panics, Err results, compile failures, and virtual generated_source diagnostics", () =>
  workspace(async (root) => {
    const entry = root + "/main.blot";
    const generator = root + "/gen.blot";
    const input = root + "/shader.wgsl";
    const virtualModule = root + "/shader.wgsl.blot";
    const compiler = await createCompiler({
      executable,
      entry,
      assets: {
        "./shader.wgsl": {
          path: input,
          parser: createBlotGenerator({ executable, generator }),
        },
      },
    });
    const build = () =>
      compiler.build({
        sources: {
          [entry]:
            'import { answer } from "./shader.wgsl"\nio run (): U32 => return answer\n',
        },
        assetSources: { [input]: "header" },
      });
    try {
      // 1. Generator @panic surfaces decoded panic payload + provenance.phase === "execute".
      await Deno.writeTextFile(
        generator,
        'io generate (x: Text): Text => return @panic "bad input"\n',
      );
      const panicked = await build();
      ok(!panicked.success);
      const panicDiag = panicked.diagnostics[0] as AssetDiagnostic;
      match(
        panicDiag.message,
        /Blot generator generate trapped for .*shader\.wgsl: panic: "bad input"/,
      );
      equal(panicDiag.provenance, {
        stage: "stage0",
        phase: "execute",
        module: virtualModule,
        input,
        generator,
      });

      // 2. Generator $Err surfaces provenance.phase === "result".
      await Deno.writeTextFile(
        generator,
        'io generate (x: Text): Result [Text, Text] => return $Err "bad header"\n',
      );
      const erred = await build();
      ok(!erred.success);
      const errDiag = erred.diagnostics[0] as AssetDiagnostic;
      equal(errDiag.message, "bad header");
      equal(errDiag.provenance, {
        stage: "stage0",
        phase: "result",
        module: virtualModule,
        input,
        generator,
      });

      // 3. Generator compile failure surfaces provenance.phase === "compile".
      await Deno.writeTextFile(
        generator,
        "io generate (x: Text): Text => return missing_symbol\n",
      );
      const badGen = await build();
      ok(!badGen.success);
      const compileDiag = badGen.diagnostics[0] as AssetDiagnostic;
      match(compileDiag.message, /Could not compile generator/);
      equal(compileDiag.provenance, {
        stage: "stage0",
        phase: "compile",
        module: virtualModule,
        input,
        generator,
      });

      // 4. Generator emitting invalid Blot source preserves virtual_source + provenance.phase === "generated_source".
      const emitted = "const answer: U32 = true\n";
      await Deno.writeTextFile(
        generator,
        `io generate (x: Text): Text => return ${JSON.stringify(emitted)}\n`,
      );
      const stage1Failed = await build();
      ok(!stage1Failed.success);
      const genDiag = stage1Failed.diagnostics.find((diag) =>
        diag.filename === virtualModule
      ) as AssetDiagnostic | undefined;
      ok(genDiag, JSON.stringify(stage1Failed.diagnostics));
      equal(genDiag.code, "type_mismatch");
      equal(genDiag.virtual_source, emitted);
      equal(genDiag.provenance, {
        stage: "stage0",
        phase: "generated_source",
        module: virtualModule,
        input,
        generator,
      });
    } finally {
      await compiler.dispose();
    }
  }));
