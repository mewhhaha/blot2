import {
  deepStrictEqual as equal,
  ok,
  rejects,
  throws,
} from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { createNativeCompiler } from "./native.ts";
import { createSourceCompiler } from "./source.ts";
import { loadSourceProject } from "./source_project.ts";
import { SourceError } from "./syntax.ts";

function project(
  sources: Readonly<Record<string, string>>,
  entry = new URL("file:///blot-project/main.blot"),
) {
  const reads: string[] = [];
  const loaded = loadSourceProject(entry, {
    imports: { "library/": new URL("file:///blot-project/library/") },
    readSource(url) {
      const name = fileURLToPath(url).slice("/blot-project/".length);
      reads.push(name);
      const source = sources[name];
      if (source === undefined) throw new Error(`Missing test module: ${name}`);
      return Promise.resolve(source);
    },
  });
  return { loaded, reads };
}

function diagnostic(code: string, filename: string, source?: string) {
  return (error: unknown) => {
    ok(error instanceof SourceError, String(error));
    equal(error.code, code, error.message);
    equal(error.origin?.filename, `/blot-project/${filename}`);
    if (source !== undefined) equal(error.origin?.source, source);
    return true;
  };
}

Deno.test("source projects resolve diamond imports once and keep private names module-local", async () => {
  const { loaded, reads } = project({
    "main.blot": `import * as left from "./left"
import { result as right_result } from "./right.blot"
export fn answer () => left.result () + right_result ()
`,
    "left.blot": `import { twice } from "library/arithmetic"
fn hidden value => twice value
export fn result () => hidden 10
`,
    "right.blot": `import * as arithmetic from "library/arithmetic"
fn hidden value => arithmetic.twice value
export fn result () => hidden 11
`,
    "library/arithmetic.blot": "export fn twice value => value * 2\n",
  });
  const source = await loaded;
  equal(reads.filter((name) => name === "library/arithmetic.blot").length, 1);
  equal(source.modules.map((module) => module.name), [
    "library/arithmetic.blot",
    "left.blot",
    "right.blot",
    "main.blot",
  ]);
  const js = await createSourceCompiler();
  const native = await createNativeCompiler();
  try {
    const expected = js.compile(source);
    const actual = await native.compile(source);
    equal(actual, expected);
    const { instance } = await WebAssembly.instantiate(actual.bytes);
    equal(Object.keys(instance.exports), ["answer"]);
    equal((instance.exports.answer as CallableFunction)(), 42);
  } finally {
    js.dispose();
    await native.dispose();
  }
});

Deno.test("source projects canonicalize equivalent file URL spellings before loading", async () => {
  const { loaded, reads } = project({
    "main.blot": `import * as direct from "./library.blot"
import { Box as EscapedBox } from "./%6cibrary%2Eblot"
fn unpack (value: direct.Box) => case value of
  EscapedBox inner => inner
export fn answer () => unpack (EscapedBox 42)
`,
    "library.blot": "export data Box = Box U32\n",
  }, new URL("file:///blot-project/%6dain.blot"));
  const input = await loaded;
  equal(reads, ["main.blot", "library.blot"]);
  equal(input.entry, "main.blot");
  equal(input.modules.map((module) => module.name), [
    "library.blot",
    "main.blot",
  ]);
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    const artifact = compiler.compile(input);
    const { instance } = await WebAssembly.instantiate(artifact.bytes);
    equal((instance.exports.answer as CallableFunction)(), 42);
  } finally {
    compiler.dispose();
  }
});

Deno.test("source projects detect cycles through equivalent file URL spellings", async () => {
  const { loaded, reads } = project({
    "main.blot": 'import * as loop from "./loop"\n',
    "loop.blot": 'import * as main from "./%6dain%2Eblot"\n',
  });
  await rejects(loaded, diagnostic("import_cycle", "loop.blot"));
  equal(reads, ["main.blot", "loop.blot"]);
});

Deno.test("source project imports preserve nominal types and constructor payloads", async () => {
  const { loaded } = project({
    "main.blot": `import * as geometry from "./geometry"
import { Point as Position, make, coordinate } from "./geometry"
fn x (point: geometry.Point) => coordinate point
fn y (point: Position) => x point
export fn answer () => y (make 42)
`,
    "geometry.blot": `export data Point = Point U32
export fn make value => Point value
export fn coordinate point => case point of
  Point value => value
`,
  });
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(await loaded);
    const { instance } = await WebAssembly.instantiate(artifact.bytes);
    equal((instance.exports.answer as CallableFunction)(), 42);
  } finally {
    compiler.dispose();
  }
});

Deno.test("source project namespace constructors work in case and guarded patterns", async () => {
  const { loaded } = project({
    "main.blot": `import * as geometry from "./geometry"
fn case_point point => case point of
  geometry.Point value => value
fn guard_point point => do:
  let geometry.Point value = point else:
    return 0
  if let geometry.Point copied = point:
    return @u32.add value copied
  return 0
export fn answer () => @u32.add (case_point (geometry.Point 14)) (guard_point (geometry.Point 14))
`,
    "geometry.blot": "export data Point = Point U32\n",
  });
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    const artifact = compiler.compile(await loaded);
    const { instance } = await WebAssembly.instantiate(artifact.bytes);
    equal((instance.exports.answer as CallableFunction)(), 42);
  } finally {
    compiler.dispose();
  }
});

Deno.test("source project operation identities survive namespace imports and providers", async () => {
  const { loaded } = project({
    "main.blot": `import * as operation from "./operation"
const provider = @effect.provider operation.read (fn value => value + 2)
export fn answer () => do provider:
  return operation.compute 40
`,
    "operation.blot": `export effect read : U32 -> U32
export fn compute value => do:
  use result <- read value
  return result
`,
  });
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(await loaded);
    const { instance } = await WebAssembly.instantiate(artifact.bytes);
    equal((instance.exports.answer as CallableFunction)(), 42);
  } finally {
    compiler.dispose();
  }
});

Deno.test("source projects reject private and missing named exports and duplicate local names", async () => {
  const compiler = await createSourceCompiler();
  try {
    for (const name of ["hidden", "absent"]) {
      const source =
        `import { ${name} } from "./library"\nexport fn answer () => 42\n`;
      const { loaded } = project({
        "main.blot": source,
        "library.blot": "const hidden = 42\nexport const public_value = 1\n",
      });
      const input = await loaded;
      throws(
        () => compiler.compile(input),
        diagnostic("unknown_export", "main.blot", source),
      );
    }
    const { loaded } = project({
      "main.blot": 'import { value } from "./library"\nconst value = 1\n',
      "library.blot": "export const value = 42\n",
    });
    const input = await loaded;
    throws(
      () => compiler.compile(input),
      diagnostic("duplicate_name", "main.blot"),
    );
  } finally {
    compiler.dispose();
  }
});

Deno.test("source project namespace names cannot merge or collide with bare bindings", async () => {
  const sources = [
    'import * as shared from "./left"\nimport * as shared from "./right"\n',
    'import * as shared from "./empty"\nimport * as shared from "./empty"\n',
    'import * as shared from "./left"\nconst shared = 1\n',
    'import * as shared from "./left"\nfn shared value => value\n',
    'import { right as shared } from "./right"\nimport * as shared from "./left"\n',
    'import * as shared from "./left"\nimport { right as shared } from "./right"\n',
    'import { Point as shared } from "./types"\nimport * as shared from "./left"\n',
    'import * as shared from "./left"\nimport { Point as shared } from "./types"\n',
  ];
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    for (const source of sources) {
      const { loaded } = project({
        "main.blot": source,
        "left.blot": "export const left = 20\n",
        "right.blot": "export const right = 22\n",
        "types.blot": "export data Point = Make U32\n",
        "empty.blot": "",
      });
      const input = await loaded;
      throws(
        () => compiler.compile(input),
        diagnostic("duplicate_name", "main.blot", source),
      );
    }
  } finally {
    compiler.dispose();
  }
});

Deno.test("source project diagnostics identify the failing dependency and its local offset", async () => {
  const dependency = "export fn answer () => missing_value\n";
  const { loaded } = project({
    "main.blot":
      'import * as library from "./library"\nexport fn main () => library.answer ()\n',
    "library.blot": dependency,
  });
  const compiler = await createSourceCompiler();
  try {
    const input = await loaded;
    throws(() => compiler.compile(input), (error) => {
      diagnostic("unknown_value", "library.blot", dependency)(error);
      equal((error as SourceError).start, dependency.indexOf("missing_value"));
      return true;
    });
  } finally {
    compiler.dispose();
  }
});

Deno.test("source projects diagnose cycles and unmapped imports at the importing file", async () => {
  await rejects(
    project({
      "main.blot": 'import * as loop from "./loop"\n',
      "loop.blot": 'import * as main from "./main"\n',
    }).loaded,
    diagnostic("import_cycle", "loop.blot"),
  );
  await rejects(
    project({
      "main.blot": 'import * as external from "unmapped/module"\n',
    }).loaded,
    diagnostic("import_path", "main.blot"),
  );
});

Deno.test("raw source compilation does not silently ignore unresolved imports", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    throws(
      () => compiler.compile('import * as dependency from "./dependency"\n'),
      (error) =>
        error instanceof SourceError && error.code === "module_loader_required",
    );
  } finally {
    compiler.dispose();
  }
});
