import {
  deepStrictEqual as assertEquals,
  ok as assert,
} from "node:assert/strict";
import { join } from "node:path";

function assertStringIncludes(actual: string, expected: string): void {
  assert(
    actual.includes(expected),
    `Expected ${JSON.stringify(actual)} to include ${JSON.stringify(expected)}`,
  );
}
import {
  extractDeclDoc,
  extractIntraDocLinkTargets,
  extractModuleDoc,
  formatSquidType,
  generateDocs,
  precompileDocExamples,
  renderCompactApi,
  runDocCli,
  runDocTests,
  searchDocPackage,
  TypeVarRenamer,
  writeMarkdownDocs,
} from "../../host/doc.ts";
import {
  DOC_RUNNER_JS,
  generateHtmlDocs,
  type PrecompiledDocExample,
} from "../../host/doc_html.ts";

const compilerExecutable = Deno.args[0] ??
  new URL("../../compiler-goose/build/squidc-goose", import.meta.url);

Deno.test("formatSquidType cleans arrows, arrays, own params, effects and tuples", () => {
  assertEquals(
    formatSquidType("(U32 -> (Array U32 -> Array F32))"),
    "U32 -> #[U32] -> #[F32]",
  );
  assertEquals(
    formatSquidType("(Array ?t42 -> (U32 -> Maybe ?t42))", 1, 2),
    "own #[a] -> U32 -> Maybe a",
  );
  assertEquals(
    formatSquidType("(U32 -> (Array U32 -> (Array U32, Array F32, Bool)))"),
    "U32 -> #[U32] -> (#[U32], #[F32], Bool)",
  );
  assertEquals(
    formatSquidType("(?t1 -> (?t2 -> Bool ! { | ?e}))"),
    "a -> b -> Bool ! { | e}",
  );
  const renamer = new TypeVarRenamer();
  const ty = formatSquidType("(Array ?t99 -> Array U32)", 0, 0, renamer);
  const wh = renamer.rename("Codec ?t99");
  assertEquals(ty, "#[a] -> #[U32]");
  assertEquals(wh, "Codec a");
});

Deno.test("doc comment extraction handles //!, //, ///, attributes, and indentation", () => {
  const src = [
    "//! Module summary line.",
    "//! Second line.",
    "",
    "// Ignored comment separated by blank line.",
    "",
    "/// Function docs.",
    "/// ```squid",
    "/// let x = 1",
    "///   x + 1",
    "/// ```",
    "@[inline]",
    "func f (x: U32) => x",
  ];
  const mod = extractModuleDoc(src);
  assertEquals(mod.doc, "Module summary line.\nSecond line.");
  assertEquals(mod.consumedEndLine, 2);

  const declDoc = extractDeclDoc(src, 11, mod.consumedEndLine);
  assertEquals(
    declDoc,
    "Function docs.\n```squid\nlet x = 1\n  x + 1\n```",
  );
});

Deno.test("extractIntraDocLinkTargets skips code fences and finds all link forms", () => {
  const md = [
    "See [`Vec2`], [dot product](`Vec2.dot`), and [codec](squid:std/codec/Codec).",
    "```squid",
    "// [`NotALink`]",
    "```",
    "Also [`std/text`].",
  ].join("\n");
  assertEquals(extractIntraDocLinkTargets(md), [
    "Vec2",
    "Vec2.dot",
    "std/codec/Codec",
    "std/text",
  ]);
});

Deno.test("squid doc extracts checked API, hides opaque/private, resolves links, runs doctests, and builds runnable HTML", async () => {
  const dir = await Deno.makeTempDir({ prefix: "squid-doc-test-" });
  try {
    const libDir = join(dir, "lib");
    await Deno.mkdir(libDir, { recursive: true });
    await Deno.writeTextFile(
      join(libDir, "geom.sq"),
      `//! Geometry primitives for testing \`squid doc\`.
//!
//! See [\`Point\`], [\`Point.manhattan\`], and [scaling](\`scale_x\`).
//!
//! \`\`\`squid
//! let p = $Point { x: 3.0, y: 4.0 }
//! p.manhattan // => 7.0
//! \`\`\`

// A 2D point with defaultable coordinates.
type Point is data = $Point {
  // Horizontal coordinate.
  x: F32 = 0.0,
  // Vertical coordinate.
  y: F32 = 0.0,
}

// Secret handle whose representation must stay hidden in public docs.
type SecretToken is opaque = { raw: U32 }

// Scalar weight alias.
type Weight = F32

// Printable trait for test formatting.
type Labelled a is trait = {
  label: a -> Text
}

// Logging effect for testing effect docs.
type Log is effect = {
  emit: U32 -> Unit
}

// Private helper omitted by default.
private func hidden_helper (n: U32) => n + 1

// Manhattan distance from the origin.
//
// \`\`\`squid
// ($Point { x: 2.0, y: 5.0 }).manhattan // => 7.0
// \`\`\`
func Point.manhattan (p: Point) => F32.abs p.x + F32.abs p.y

// Scale the x coordinate; return type is inferred by the checker.
func scale_x (p: Point) -> (k: Weight) => p.x * k

// Consume an owned array and return its length.
//
// \`\`\`squid
// test "consume_len works":
//   if consume_len #[10, 20, 30] != 3:
//     @panic "bad length"
//
// test expect_trap "explicit panic is decoded":
//   @panic "boom from doc"
// \`\`\`
func consume_len (items: own #[U32]) => items.length

// Record an event using the [\`Log\`] effect.
//
// \`\`\`squid check
// func check_only (n: U32): Unit ! { Log } => use Log.emit n
// \`\`\`
func emit_twice (n: U32): Unit ! { Log } =>
  use Log.emit n
  use Log.emit n
  return ()

// Non-runnable snippet that still type-checks, plus an ignored snippet.
//
// \`\`\`squid no_run
// let t: Point = $Point { x: 1.0, y: 2.0 }
// t
// \`\`\`
//
// \`\`\`squid ignore
// this is not valid squid syntax !!!
// \`\`\`
func make_origin () => $Point { x: 0.0 }
`,
    );

    await Deno.writeTextFile(
      join(libDir, "extra.sq"),
      `//! Secondary module linking back to [\`geom/Point\`] and [\`geom/scale_x\`].
import { Point } from "./geom"

// Greeting example returning \`Text\`.
//
// \`\`\`squid
// greet () // => "hello squid"
// \`\`\`
func greet (): Text => "hello squid"

// Double x using imported [\`Point\`].
func double_x (p: Point) => p.x * 2.0
`,
    );

    // 1. Public API extraction
    const { pkg, context, resolveLink } = await generateDocs({
      target: libDir,
      executable: compilerExecutable,
    });
    assertEquals(pkg.modules.length, 2);
    for (const m of pkg.modules) {
      assertEquals(m.diagnostics, [], `diagnostics in ${m.id}`);
    }
    assertEquals(pkg.brokenLinks, []);

    const geom = pkg.modules.find((m) => m.id === "geom")!;
    assert(geom, "expected geom module");
    assertStringIncludes(geom.doc, "Geometry primitives");

    // Private helper hidden by default
    assertEquals(
      geom.values.find((v) => v.name === "hidden_helper"),
      undefined,
    );

    // Opaque type hides representation/constructors
    const secret = geom.types.find((t) => t.name === "SecretToken")!;
    assertEquals(secret.kind, "opaque");
    assertEquals(secret.opaque, true);
    assertEquals(secret.constructors.length, 0);

    // Data type preserves field defaults & field doc comments, and attaches methods
    const point = geom.types.find((t) => t.name === "Point")!;
    assertEquals(point.kind, "data");
    assertEquals(point.constructors.length, 1);
    assertEquals(point.constructors[0].fields.length, 2);
    assertEquals(point.constructors[0].fields[0].name, "x");
    assertEquals(point.constructors[0].fields[0].hasDefault, true);
    assertEquals(point.constructors[0].fields[0].doc, "Horizontal coordinate.");
    assertEquals(point.methods.map((m) => m.name), ["Point.manhattan"]);
    assertEquals(
      point.methods[0].signature,
      "func Point.manhattan: Point -> F32",
    );

    // Inferred return type, own parameter, effect row, trait, alias
    const scaleX = geom.values.find((v) => v.name === "scale_x")!;
    assertEquals(scaleX.signature, "func scale_x: Point -> F32 -> F32");

    const consumeLen = geom.values.find((v) => v.name === "consume_len")!;
    assertStringIncludes(consumeLen.signature, "own #[U32] -> U32");

    const emitTwice = geom.values.find((v) => v.name === "emit_twice")!;
    assertStringIncludes(emitTwice.signature, "! {");
    assertStringIncludes(emitTwice.signature, "emit");

    assertEquals(geom.traits.map((t) => t.name), ["Labelled"]);
    assertEquals(geom.effects.map((e) => e.name), ["Log"]);
    assertEquals(geom.effects[0].operations[0].name, "emit");

    // includePrivate reveals hidden_helper and SecretToken constructor
    const withPriv = await generateDocs({
      target: libDir,
      executable: compilerExecutable,
      includePrivate: true,
    });
    const geomPriv = withPriv.pkg.modules.find((m) => m.id === "geom")!;
    assert(geomPriv.values.some((v) => v.name === "hidden_helper"));
    assertEquals(
      geomPriv.types.find((t) => t.name === "SecretToken")!.constructors.length,
      1,
    );

    // 2. Doctests (`run`, `test "..."`, `Text`, `check`, `no_run`, `ignore`)
    const report = await runDocTests(pkg, context, compilerExecutable);
    assertEquals(report.failed, 0, JSON.stringify(report.results, null, 2));
    assertEquals(report.passed, 6);
    assertEquals(report.skipped, 1);

    // 3. Static Markdown export + link rewriting
    const mdOut = join(dir, "docs-md");
    const mdFiles = await writeMarkdownDocs(pkg, resolveLink, mdOut);
    assert(mdFiles.length >= 4);
    const extraMd = await Deno.readTextFile(join(mdOut, "modules", "extra.md"));
    assertStringIncludes(
      extraMd,
      "[`geom/Point`](../modules/geom.md#type-point)",
    );
    assertStringIncludes(
      extraMd,
      "[`geom/scale_x`](../modules/geom.md#fn-scale-x)",
    );
    const apiMd = await Deno.readTextFile(join(mdOut, "API.md"));
    assertStringIncludes(apiMd, "type SecretToken is opaque");
    assertStringIncludes(apiMd, "func consume_len: own #[U32] -> U32");

    // 4. Static HTML export + live browser runner execution of precompiled base64 Wasm!
    const htmlOut = join(dir, "docs-html");
    const examples = await precompileDocExamples(
      pkg,
      context,
      compilerExecutable,
    );
    const { files: htmlFiles, exampleCount } = await generateHtmlDocs(
      pkg,
      resolveLink,
      { outDir: htmlOut, examples },
    );
    assert(htmlFiles.length >= 7);
    assertEquals(exampleCount, 4); // module Point, Point.manhattan, consume_len test, extra greet

    const geomHtml = await Deno.readTextFile(
      join(htmlOut, "modules", "geom.html"),
    );
    assertStringIncludes(geomHtml, "▶ Run");
    assertStringIncludes(geomHtml, 'href="#type-point"');

    // Execute the actual generated runner.js against every precompiled example in examples.js!
    const examplesJs = await Deno.readTextFile(join(htmlOut, "examples.js"));
    const runnerFn = new Function(
      `${examplesJs}\n${DOC_RUNNER_JS}\nreturn { examples: globalThis.__SQUID_DOC_EXAMPLES, run: globalThis.__squidDocRunExample };`,
    );
    const { examples: loadedExamples, run } = runnerFn() as {
      examples: Record<string, PrecompiledDocExample>;
      run: (
        spec: PrecompiledDocExample,
      ) => Promise<{ ok: boolean; text: string }>;
    };
    const keys = Object.keys(loadedExamples);
    assertEquals(keys.length, 4);
    const outputs: string[] = [];
    for (const k of keys) {
      const res = await run(loadedExamples[k]);
      assert(res.ok, `browser runner failed for ${k}: ${res.text}`);
      outputs.push(res.text);
    }
    assert(
      outputs.some((o) => o.includes("=> 7.0")),
      `missing 7.0 in ${outputs}`,
    );
    assert(
      outputs.some((o) => o.includes('=> "hello squid"')),
      `missing "hello squid" in ${outputs}`,
    );
    assert(
      outputs.some((o) =>
        o.includes("✓ consume_len works") &&
        o.includes('panic: "boom from doc"')
      ),
      `missing test suite + decoded trap output in ${outputs}`,
    );

    // 5. Search
    const hits = searchDocPackage(pkg, "manhattan");
    assertEquals(hits.length, 1);
    assertEquals(hits[0].name, "Point.manhattan");
    assertStringIncludes(
      renderCompactApi(pkg),
      "func scale_x: Point -> F32 -> F32",
    );
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});

Deno.test("squid doc detects broken intra-doc links and failing doctests", async () => {
  const dir = await Deno.makeTempDir({ prefix: "squid-doc-fail-" });
  try {
    const file = join(dir, "broken.sq");
    await Deno.writeTextFile(
      file,
      `//! Broken link to [\`DoesNotExist\`].
//!
//! \`\`\`squid
//! 1 + 1 // => 3
//! \`\`\`

func ok () => 1
`,
    );
    const { pkg, context } = await generateDocs({
      target: file,
      executable: compilerExecutable,
    });
    assertEquals(pkg.brokenLinks.length, 1);
    assertEquals(pkg.brokenLinks[0].target, "DoesNotExist");

    const report = await runDocTests(pkg, context, compilerExecutable);
    assertEquals(report.failed, 1);
    assertStringIncludes(report.results[0].error ?? "", "Expected 3, got 2");

    const cliExit = await runDocCli(compilerExecutable, [
      file,
      "--check-links",
      "--test",
    ]);
    assertEquals(cliExit, 1);
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});

Deno.test("squid doc discovers pen.json alias imports", async () => {
  const dir = await Deno.makeTempDir({ prefix: "squid-doc-pen-" });
  try {
    await Deno.mkdir(join(dir, "lib"), { recursive: true });
    const stdPath = new URL("../../std", import.meta.url).pathname;
    await Deno.writeTextFile(
      join(dir, "pen.json"),
      JSON.stringify({
        compiler: {
          plugin: "squid",
          settings: {
            std: stdPath,
            imports: { "demo/": "lib/" },
          },
        },
      }),
    );
    await Deno.writeTextFile(
      join(dir, "lib", "math.sq"),
      `//! Demo math library.
func triple (n: U32) => n * 3
`,
    );
    const { pkg } = await generateDocs({
      target: "demo",
      cwd: dir,
      executable: compilerExecutable,
    });
    assertEquals(pkg.name, "demo");
    assertEquals(pkg.modules.length, 1);
    assertEquals(pkg.modules[0].importPath, "demo/math");
    assertEquals(
      pkg.modules[0].values[0].signature,
      "func triple: U32 -> U32",
    );
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});

Deno.test("squid doc std has zero broken links and all runnable examples pass", async () => {
  const { pkg, context } = await generateDocs({
    target: "std",
    executable: compilerExecutable,
  });
  assert(pkg.modules.length >= 10);
  assertEquals(pkg.brokenLinks, []);
  const report = await runDocTests(pkg, context, compilerExecutable);
  assertEquals(report.failed, 0, JSON.stringify(report.results, null, 2));
  assert(report.passed >= 3);
  const hits = searchDocPackage(pkg, "Vec2.dot");
  assert(hits.some((h) => h.name === "Vec2.dot" && h.module === "std/vector"));
});
