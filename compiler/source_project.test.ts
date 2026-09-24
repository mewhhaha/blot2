import {
  deepStrictEqual as equal,
  ok,
  rejects,
  throws,
} from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { bendArray } from "./bend_list.ts";
import { createNativeCompiler } from "./native.ts";
import { createSourceCompiler } from "./source.ts";
import {
  createSourceProjectLoader,
  loadSourceProject,
} from "./source_project.ts";
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

Deno.test("source project loader protects retained syntax from caller mutation", async () => {
  const entry = new URL("file:///blot-project/main.blot");
  const loader = await createSourceProjectLoader({
    readSource: () => Promise.resolve("const answer = fn () => 42\n"),
  });
  try {
    const first = await loader.load(entry);
    const declaration = bendArray(first.modules[0].root.children)[0];
    ok(Object.isFrozen(declaration));
    throws(() => Object.assign(declaration, { text: "poison" }), TypeError);
    let terminal = declaration.children;
    while (terminal.$ === "Con") terminal = terminal.tail;
    ok(Object.isFrozen(terminal));
    throws(() => Object.assign(terminal, { $: "Con" }), TypeError);
    const second = await loader.load(entry);
    equal(second.modules[0].root, first.modules[0].root);
  } finally {
    loader.dispose();
  }
});

Deno.test("source project loader snapshots import URLs at creation", async () => {
  const entry = new URL("file:///blot-project/main.blot");
  const original = new URL("file:///blot-project/one/");
  const imports = { "library/": original };
  const loader = await createSourceProjectLoader({
    imports,
    readSource(url) {
      if (url.href === entry.href) {
        return Promise.resolve(
          'import * as lib from "library/value"\nconst answer = fn () => lib.value ()\n',
        );
      }
      if (url.href === "file:///blot-project/one/value.blot") {
        return Promise.resolve("const value = fn () => 42\n");
      }
      throw new Error(`Unexpected module ${url}`);
    },
  });
  try {
    original.pathname = "/blot-project/two/";
    imports["library/"] = new URL("file:///blot-project/three/");
    const project = await loader.load(entry);
    equal(project.modules.map((module) => module.name), [
      "one/value.blot",
      "main.blot",
    ]);
  } finally {
    loader.dispose();
  }
});

Deno.test("source projects resolve diamond imports once and keep local names in their module scopes", async () => {
  const { loaded, reads } = project({
    "main.blot": `import * as left from "./left"
import { result as right_result } from "./right.blot"
const answer = fn () => left.result () + right_result ()
`,
    "left.blot": `import { twice } from "library/arithmetic"
const hidden = fn value => twice value
const result = fn () => hidden 10
`,
    "right.blot": `import * as arithmetic from "library/arithmetic"
const hidden = fn value => arithmetic.twice value
const result = fn () => hidden 11
`,
    "library/arithmetic.blot": "const twice = fn value => value * 2\n",
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
const unpack = fn (value: direct.Box) => case value of
  EscapedBox inner => inner
const answer = fn () => unpack (EscapedBox 42)
`,
    "library.blot": "data Box = Box U32\n",
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
const x = fn (point: geometry.Point) => coordinate point
const y = fn (point: Position) => x point
const answer = fn () => y (make 42)
`,
    "geometry.blot": `data Point = Point U32
const make = fn value => Point value
const coordinate = fn point => case point of
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
const case_point = fn point => case point of
  geometry.Point value => value
const guard_point = fn point => do:
  let geometry.Point value = point else:
    return 0
  if let geometry.Point copied = point:
    return @u32.add value copied
  return 0
const answer = fn () => @u32.add (case_point (geometry.Point 14)) (guard_point (geometry.Point 14))
`,
    "geometry.blot": "data Point = Point U32\n",
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
const answer = fn () => do provider:
  return operation.compute 40
`,
    "operation.blot": `effect read : U32 -> U32
const compute = fn value => do:
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

Deno.test("source projects import bindings by default and reject missing exports and duplicate local names", async () => {
  const compiler = await createSourceCompiler();
  try {
    const publicBindings = await project({
      "main.blot":
        'import { value } from "./library"\nconst answer = fn () => value\n',
      "library.blot": "const value = 42\n",
    }).loaded;
    const artifact = compiler.compile(publicBindings);
    const { instance } = await WebAssembly.instantiate(artifact.bytes);
    equal((instance.exports.answer as CallableFunction)(), 42);
    const missingSource =
      'import { absent } from "./library"\nconst answer = fn () => 42\n';
    const missingImport = await project({
      "main.blot": missingSource,
      "library.blot": "const value = 42\n",
    }).loaded;
    throws(
      () => compiler.compile(missingImport),
      diagnostic("unknown_export", "main.blot", missingSource),
    );
    const { loaded } = project({
      "main.blot": 'import { value } from "./library"\nconst value = 1\n',
      "library.blot": "const value = 42\n",
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
    'import * as shared from "./left"\nconst shared = fn value => value\n',
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
        "left.blot": "const left = 20\n",
        "right.blot": "const right = 22\n",
        "types.blot": "data Point = Make U32\n",
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
  const dependency = "const answer = fn () => missing_value\n";
  const { loaded } = project({
    "main.blot":
      'import * as library from "./library"\nconst main = fn () => library.answer ()\n',
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

Deno.test("source project reads overlap with a bounded fanout and retain dependency order", async () => {
  const sources = Array.from(
    { length: 8 },
    (_, index) => `branch${index}.blot`,
  );
  const waiting = new Map<string, (source: string) => void>();
  const started = Promise.withResolvers<void>();
  let active = 0;
  let peak = 0;
  const loaded = loadSourceProject(new URL("file:///blot-project/main.blot"), {
    readSource(url) {
      const name = fileURLToPath(url).split("/").at(-1)!;
      if (name === "main.blot") {
        return Promise.resolve(
          sources.map((name, index) =>
            `import * as branch${index} from "./${name}"`
          ).join("\n"),
        );
      }
      active++;
      peak = Math.max(peak, active);
      const result = new Promise<string>((resolve) =>
        waiting.set(name, resolve)
      );
      if (waiting.size === 4) started.resolve();
      return result.finally(() => active--);
    },
  });
  await started.promise;
  equal([...waiting.keys()], sources.slice(0, 4));
  for (let batch = 0; batch < 2; batch++) {
    for (const name of sources.slice(batch * 4, batch * 4 + 4).reverse()) {
      waiting.get(name)!("const answer = fn () => 42\n");
    }
    if (batch === 0) {
      while (waiting.size < 8) {
        await new Promise((resolve) => setTimeout(resolve, 0));
      }
    }
  }
  const project = await loaded;
  equal(peak, 4);
  equal(project.modules.map((module) => module.name), [
    ...sources,
    "main.blot",
  ]);
});

Deno.test("prefetched read failures cannot overtake an earlier imported syntax diagnostic", async () => {
  const missing = new Error("later read failed");
  await rejects(
    loadSourceProject(new URL("file:///blot-project/main.blot"), {
      readSource(url) {
        if (url.pathname.endsWith("main.blot")) {
          return Promise.resolve(
            'import * as first from "./first"\nimport * as second from "./second"\n',
          );
        }
        if (url.pathname.endsWith("first.blot")) {
          return Promise.resolve("fn =\n");
        }
        return Promise.reject(missing);
      },
    }),
    (error) => {
      ok(error instanceof SourceError);
      equal(error.origin?.filename, "/blot-project/first.blot");
      return true;
    },
  );
});

Deno.test("parallel module lowering preserves earlier body errors before later scope errors", async () => {
  const { loaded } = project({
    "main.blot":
      'import * as first from "./first"\nimport * as second from "./second"\nconst answer = fn () => 42\n',
    "first.blot": "const broken = fn value => @missing.operation value\n",
    "second.blot":
      "const duplicate = fn () => 1\nconst duplicate = fn () => 2\n",
  });
  const input = await loaded;
  for (const threads of [1, 2, 4, 8]) {
    const compiler = await createNativeCompiler({ threads });
    try {
      await rejects(() => compiler.compile(input), (error) => {
        ok(error instanceof SourceError);
        equal(error.origin?.filename, "/blot-project/first.blot");
        ok(error.message.includes("missing.operation"));
        return true;
      });
    } finally {
      await compiler.dispose();
    }
  }
});

Deno.test("large independent module bodies preserve native artifacts and nominal catalogs", async () => {
  const sources: Record<string, string> = {};
  sources["main.blot"] = Array.from(
    { length: 8 },
    (_, index) => `import * as part${index} from "./part${index}"`,
  ).join("\n") + "\nconst answer = fn (value: U32) => part0.answer value\n";
  for (let module = 0; module < 8; module++) {
    sources[`part${module}.blot`] = Array.from({ length: 8 }, (_, index) =>
      `data T${index} = C${index} ${
        index ? `T${index - 1}` : "U32"
      }\nconst identity${index} = fn (value: T${index}) => value\n`).join("") +
      "const answer = fn value => " + Array.from({ length: 96 }, () =>
        "value").join(" + ") +
      "\n";
  }
  const input = await project(sources).loaded;
  const js = await createSourceCompiler();
  try {
    const expected = js.compile(input);
    for (const threads of [1, 8]) {
      const native = await createNativeCompiler({ threads });
      try {
        const actual = await native.compile(input);
        equal(actual, expected);
        const { instance } = await WebAssembly.instantiate(actual.bytes);
        equal((instance.exports.answer as CallableFunction)(1), 96);
      } finally {
        await native.dispose();
      }
    }
  } finally {
    js.dispose();
  }
});
